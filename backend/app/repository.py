"""Persistence for runs and their output."""

from __future__ import annotations

import sqlite3
import uuid
from dataclasses import dataclass

from app.db import to_iso, utc_now, write_transaction
from app.pipeline.transform import TransformedObject


@dataclass(frozen=True)
class RunCounts:
    events_read: int
    objects_written: int
    objects_deleted: int


def create_run(
    connection: sqlite3.Connection,
    source_key: str,
    idempotency_key: str | None = None,
) -> sqlite3.Row:
    """Insert a QUEUED run. This insert *is* the enqueue - no work happens here."""
    if idempotency_key:
        existing = find_run_by_idempotency_key(connection, idempotency_key)
        if existing is not None:
            return existing

    now = utc_now()
    run_id = str(uuid.uuid4())

    with write_transaction(connection):
        connection.execute(
            """
            INSERT INTO runs (id, status, source_key, idempotency_key,
                              attempts, visible_at, created_at)
            VALUES (?, 'QUEUED', ?, ?, 0, ?, ?)
            """,
            (run_id, source_key, idempotency_key, to_iso(now), to_iso(now)),
        )

    run = get_run(connection, run_id)
    assert run is not None
    return run


def find_run_by_idempotency_key(
    connection: sqlite3.Connection, key: str
) -> sqlite3.Row | None:
    return connection.execute(
        "SELECT * FROM runs WHERE idempotency_key = ?", (key,)
    ).fetchone()


def get_run(connection: sqlite3.Connection, run_id: str) -> sqlite3.Row | None:
    return connection.execute("SELECT * FROM runs WHERE id = ?", (run_id,)).fetchone()


def list_runs(
    connection: sqlite3.Connection, limit: int, offset: int
) -> tuple[list[sqlite3.Row], int]:
    total = connection.execute("SELECT COUNT(*) AS n FROM runs").fetchone()["n"]
    rows = connection.execute(
        "SELECT * FROM runs ORDER BY created_at DESC, id DESC LIMIT ? OFFSET ?",
        (limit, offset),
    ).fetchall()
    return list(rows), total


def replace_records(
    connection: sqlite3.Connection,
    run_id: str,
    objects: tuple[TransformedObject, ...],
) -> None:
    """Write a run's output.

    Upsert, so a redelivered message rewrites the same rows rather than duplicating.
    """
    with write_transaction(connection):
        connection.executemany(
            """
            INSERT INTO records (
                run_id, object_id, type, diameter, geometry,
                segment_count, vertex_count, length_m,
                bbox_min_x, bbox_min_y, bbox_max_x, bbox_max_y,
                last_event_id, last_event_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT (run_id, object_id) DO UPDATE SET
                type          = excluded.type,
                diameter      = excluded.diameter,
                geometry      = excluded.geometry,
                segment_count = excluded.segment_count,
                vertex_count  = excluded.vertex_count,
                length_m      = excluded.length_m,
                bbox_min_x    = excluded.bbox_min_x,
                bbox_min_y    = excluded.bbox_min_y,
                bbox_max_x    = excluded.bbox_max_x,
                bbox_max_y    = excluded.bbox_max_y,
                last_event_id = excluded.last_event_id,
                last_event_at = excluded.last_event_at
            """,
            [
                (
                    run_id,
                    obj.object_id,
                    obj.type,
                    obj.diameter,
                    obj.geometry,
                    obj.metrics.segment_count,
                    obj.metrics.vertex_count,
                    obj.metrics.length_m,
                    obj.metrics.bbox_min_x,
                    obj.metrics.bbox_min_y,
                    obj.metrics.bbox_max_x,
                    obj.metrics.bbox_max_y,
                    obj.last_event_id,
                    obj.last_event_at,
                )
                for obj in objects
            ],
        )


def list_records(
    connection: sqlite3.Connection, run_id: str, limit: int, offset: int
) -> tuple[list[sqlite3.Row], int]:
    total = connection.execute(
        "SELECT COUNT(*) AS n FROM records WHERE run_id = ?", (run_id,)
    ).fetchone()["n"]
    rows = connection.execute(
        "SELECT * FROM records WHERE run_id = ? ORDER BY object_id LIMIT ? OFFSET ?",
        (run_id, limit, offset),
    ).fetchall()
    return list(rows), total
