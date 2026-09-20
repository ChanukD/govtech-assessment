"""The transformation is pure, so it can be tested without a database or an API."""

from __future__ import annotations

import base64
import json
from pathlib import Path

import pytest

from app.pipeline.source import read_rows
from app.pipeline.transform import (
    TransformError,
    derive_metrics,
    parse_wkt,
    transform,
)

SAMPLE = Path(__file__).resolve().parents[2] / "data" / "records.csv"


def event(event_id: int, timestamp: str, object_id: str, **payload) -> dict[str, str]:
    body = {"object_id": object_id, "action": None, "type": "S",
            "diameter": 1.0, "geometry": "LINESTRING (0 0, 3 4)"}
    body.update(payload)
    encoded = base64.b64encode(json.dumps(body).encode()).decode()
    return {"id": str(event_id), "record": encoded, "timestamp": timestamp}


class TestGeometry:
    def test_linestring_length_is_euclidean(self):
        metrics = derive_metrics("LINESTRING (0 0, 3 4)")
        assert metrics.length_m == 5.0
        assert metrics.vertex_count == 2
        assert metrics.segment_count == 1

    def test_multilinestring_sums_parts(self):
        metrics = derive_metrics("MULTILINESTRING ((0 0, 3 4), (0 0, 0 10))")
        assert metrics.length_m == 15.0
        assert metrics.vertex_count == 4
        assert metrics.segment_count == 2

    def test_bounding_box_spans_all_vertices(self):
        metrics = derive_metrics("LINESTRING (10 20, 30 5, 15 40)")
        assert (metrics.bbox_min_x, metrics.bbox_min_y) == (10, 5)
        assert (metrics.bbox_max_x, metrics.bbox_max_y) == (30, 40)

    def test_unsupported_geometry_is_rejected(self):
        with pytest.raises(TransformError):
            parse_wkt("POINT (1 2)")


class TestFold:
    def test_last_write_wins(self):
        result = transform([
            event(0, "2026-01-01 00:00:00", "a", diameter=1.0),
            event(1, "2026-01-01 00:00:01", "a", diameter=9.0),
        ])
        assert result.objects_written == 1
        assert result.objects[0].diameter == 9.0

    def test_final_delete_drops_the_object(self):
        result = transform([
            event(0, "2026-01-01 00:00:00", "a"),
            event(1, "2026-01-01 00:00:01", "a", action="DELETE", geometry=None),
        ])
        assert result.objects_written == 0
        assert result.objects_deleted == 1

    def test_delete_followed_by_recreate_survives(self):
        result = transform([
            event(0, "2026-01-01 00:00:00", "a", action="DELETE", geometry=None),
            event(1, "2026-01-01 00:00:01", "a"),
        ])
        assert result.objects_written == 1

    def test_row_order_does_not_matter(self):
        rows = [
            event(1, "2026-01-01 00:00:01", "a", diameter=9.0),
            event(0, "2026-01-01 00:00:00", "a", diameter=1.0),
        ]
        assert transform(rows).objects[0].diameter == 9.0
        assert transform(list(reversed(rows))).objects[0].diameter == 9.0

    def test_transform_is_idempotent(self):
        rows = [event(0, "2026-01-01 00:00:00", "a")]
        assert transform(rows) == transform(rows)

    def test_malformed_payload_is_rejected(self):
        with pytest.raises(TransformError):
            transform([{"id": "0", "record": "not base64", "timestamp": "2026-01-01"}])


class TestSampleData:
    """Pins the documented result for the provided file."""

    def test_replaying_the_sample_yields_nine_current_objects(self):
        result = transform(read_rows(SAMPLE))
        assert result.events_read == 50
        assert result.objects_written == 9
        assert result.objects_deleted == 1

    def test_every_surviving_object_has_metrics(self):
        for obj in transform(read_rows(SAMPLE)).objects:
            assert obj.metrics.vertex_count >= 2
            assert obj.metrics.segment_count >= 1
            assert obj.metrics.length_m > 0
