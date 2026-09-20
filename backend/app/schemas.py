"""API contract. Separate from the database rows so the two can diverge."""

from __future__ import annotations

import sqlite3
from typing import Literal

from pydantic import BaseModel, Field

RunStatus = Literal["QUEUED", "RUNNING", "SUCCEEDED", "FAILED"]
TERMINAL_STATUSES: frozenset[str] = frozenset({"SUCCEEDED", "FAILED"})


class CreateRunRequest(BaseModel):
    idempotency_key: str | None = Field(
        default=None,
        max_length=200,
        description="Optional. Repeating a request with the same key returns the "
        "original run instead of starting another.",
    )


class BoundingBox(BaseModel):
    min_x: float
    min_y: float
    max_x: float
    max_y: float


class RunSummary(BaseModel):
    run_id: str
    status: RunStatus
    source_key: str
    attempts: int
    created_at: str
    started_at: str | None = None
    finished_at: str | None = None
    error: str | None = None
    events_read: int | None = None
    objects_written: int | None = None
    objects_deleted: int | None = None

    @property
    def is_terminal(self) -> bool:
        return self.status in TERMINAL_STATUSES

    @classmethod
    def from_row(cls, row: sqlite3.Row) -> "RunSummary":
        return cls(
            run_id=row["id"],
            status=row["status"],
            source_key=row["source_key"],
            attempts=row["attempts"],
            created_at=row["created_at"],
            started_at=row["started_at"],
            finished_at=row["finished_at"],
            error=row["error"],
            events_read=row["events_read"],
            objects_written=row["objects_written"],
            objects_deleted=row["objects_deleted"],
        )


class RecordOut(BaseModel):
    object_id: str
    type: str | None
    diameter: float | None
    geometry: str
    segment_count: int
    vertex_count: int
    length_m: float
    bbox: BoundingBox
    last_event_id: int
    last_event_at: str

    @classmethod
    def from_row(cls, row: sqlite3.Row) -> "RecordOut":
        return cls(
            object_id=row["object_id"],
            type=row["type"],
            diameter=row["diameter"],
            geometry=row["geometry"],
            segment_count=row["segment_count"],
            vertex_count=row["vertex_count"],
            length_m=row["length_m"],
            bbox=BoundingBox(
                min_x=row["bbox_min_x"],
                min_y=row["bbox_min_y"],
                max_x=row["bbox_max_x"],
                max_y=row["bbox_max_y"],
            ),
            last_event_id=row["last_event_id"],
            last_event_at=row["last_event_at"],
        )


class Page(BaseModel):
    total: int
    limit: int
    offset: int


class RunListResponse(BaseModel):
    runs: list[RunSummary]
    page: Page


class RecordListResponse(BaseModel):
    run_id: str
    status: RunStatus
    records: list[RecordOut]
    page: Page


class HealthResponse(BaseModel):
    status: Literal["ok"]
