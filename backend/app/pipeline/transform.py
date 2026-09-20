"""The transformation itself: pure functions over in-memory data, no I/O.

The input is not a flat dataset. Each CSV row is one event in a change-data-capture
changelog: `record` is base64-encoded JSON, ten distinct object_ids each appear five
times with increasing timestamps, and `action` is either null (upsert) or "DELETE"
(tombstone). Copying rows across would be wrong.

So the transformation replays the log:

    decode -> validate -> order by (timestamp, id)
        -> fold to latest state per object_id (last write wins)
        -> drop objects whose final action is DELETE
        -> derive geometry metrics

Two properties follow, and both matter architecturally. It is a pure fold over
sorted events, so it is deterministic; and it is therefore idempotent, which is what
makes at-least-once queue delivery safe to build on.
"""

from __future__ import annotations

import base64
import binascii
import json
import math
import re
from dataclasses import dataclass

DELETE_ACTION = "DELETE"

# Matches "LINESTRING (...)" and "MULTILINESTRING ((...), (...))", capturing the body.
_WKT_PATTERN = re.compile(r"^\s*(LINESTRING|MULTILINESTRING)\s*\((.*)\)\s*$", re.IGNORECASE)
_PART_PATTERN = re.compile(r"\(([^()]*)\)")


class TransformError(ValueError):
    """A row could not be decoded or is structurally invalid."""


@dataclass(frozen=True)
class ChangeEvent:
    event_id: int
    timestamp: str
    object_id: str
    action: str | None
    type: str | None
    diameter: float | None
    geometry: str | None

    @property
    def is_delete(self) -> bool:
        return (self.action or "").upper() == DELETE_ACTION


@dataclass(frozen=True)
class GeometryMetrics:
    segment_count: int
    vertex_count: int
    length_m: float
    bbox_min_x: float
    bbox_min_y: float
    bbox_max_x: float
    bbox_max_y: float


@dataclass(frozen=True)
class TransformedObject:
    object_id: str
    type: str | None
    diameter: float | None
    geometry: str
    metrics: GeometryMetrics
    last_event_id: int
    last_event_at: str


@dataclass(frozen=True)
class TransformResult:
    objects: tuple[TransformedObject, ...]
    events_read: int
    objects_deleted: int

    @property
    def objects_written(self) -> int:
        return len(self.objects)


def decode_event(row: dict[str, str]) -> ChangeEvent:
    """Decode one CSV row into a change event.

    Raises TransformError with the offending row id rather than letting a malformed
    payload surface as a bare KeyError three frames away.
    """
    try:
        event_id = int(row["id"])
    except (KeyError, TypeError, ValueError) as exc:
        raise TransformError(f"row has no usable integer id: {row!r}") from exc

    try:
        payload = json.loads(base64.b64decode(row["record"], validate=True))
    except (KeyError, binascii.Error, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise TransformError(f"row {event_id}: record is not base64-encoded JSON") from exc

    if not isinstance(payload, dict):
        raise TransformError(f"row {event_id}: decoded record is not an object")

    object_id = payload.get("object_id")
    if not object_id:
        raise TransformError(f"row {event_id}: record has no object_id")

    timestamp = row.get("timestamp")
    if not timestamp:
        raise TransformError(f"row {event_id}: record has no timestamp")

    return ChangeEvent(
        event_id=event_id,
        timestamp=timestamp,
        object_id=str(object_id),
        action=payload.get("action"),
        type=payload.get("type"),
        diameter=payload.get("diameter"),
        geometry=payload.get("geometry"),
    )


def parse_wkt(wkt: str) -> list[list[tuple[float, float]]]:
    """Parse LINESTRING or MULTILINESTRING into a list of coordinate sequences."""
    match = _WKT_PATTERN.match(wkt)
    if not match:
        raise TransformError(f"unsupported geometry: {wkt!r}")

    kind, body = match.group(1).upper(), match.group(2)
    raw_parts = _PART_PATTERN.findall(body) if kind == "MULTILINESTRING" else [body]
    if not raw_parts:
        raise TransformError(f"geometry has no coordinates: {wkt!r}")

    parts: list[list[tuple[float, float]]] = []
    for raw in raw_parts:
        vertices: list[tuple[float, float]] = []
        for pair in raw.split(","):
            values = pair.split()
            if len(values) < 2:
                raise TransformError(f"malformed coordinate {pair!r} in {wkt!r}")
            try:
                vertices.append((float(values[0]), float(values[1])))
            except ValueError as exc:
                raise TransformError(f"non-numeric coordinate {pair!r} in {wkt!r}") from exc

        if len(vertices) < 2:
            raise TransformError(f"geometry part needs at least two vertices: {wkt!r}")
        parts.append(vertices)

    return parts


def derive_metrics(wkt: str) -> GeometryMetrics:
    """Derive vertex and segment counts, length and bounding box from a geometry.

    length_m is a Euclidean sum over the vertices. That is valid only because the
    coordinates are in a projected CRS measured in metres - the value ranges
    (~30,000-49,000 easting, ~20,000-39,000 northing) are consistent with SVY21.
    Geographic coordinates would need a geodesic calculation instead.
    """
    parts = parse_wkt(wkt)

    vertex_count = sum(len(part) for part in parts)
    segment_count = sum(len(part) - 1 for part in parts)

    length = 0.0
    for part in parts:
        for (x1, y1), (x2, y2) in zip(part, part[1:]):
            length += math.hypot(x2 - x1, y2 - y1)

    xs = [x for part in parts for x, _ in part]
    ys = [y for part in parts for _, y in part]

    return GeometryMetrics(
        segment_count=segment_count,
        vertex_count=vertex_count,
        length_m=round(length, 3),
        bbox_min_x=min(xs),
        bbox_min_y=min(ys),
        bbox_max_x=max(xs),
        bbox_max_y=max(ys),
    )


def transform(rows: list[dict[str, str]]) -> TransformResult:
    """Replay the changelog and return the current state of every surviving object."""
    events = [decode_event(row) for row in rows]

    # Sorting by (timestamp, event_id) makes the fold deterministic even if two
    # events share a timestamp, and independent of the order rows arrive in.
    events.sort(key=lambda event: (event.timestamp, event.event_id))

    latest: dict[str, ChangeEvent] = {}
    for event in events:
        latest[event.object_id] = event

    objects: list[TransformedObject] = []
    deleted = 0

    for object_id in sorted(latest):
        event = latest[object_id]

        if event.is_delete:
            deleted += 1
            continue

        if not event.geometry:
            raise TransformError(f"object {object_id}: surviving event has no geometry")

        objects.append(
            TransformedObject(
                object_id=object_id,
                type=event.type,
                diameter=event.diameter,
                geometry=event.geometry,
                metrics=derive_metrics(event.geometry),
                last_event_id=event.event_id,
                last_event_at=event.timestamp,
            )
        )

    return TransformResult(
        objects=tuple(objects),
        events_read=len(events),
        objects_deleted=deleted,
    )
