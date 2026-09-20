"""SQLite connection handling and schema.

WAL mode and a busy timeout matter here: the API and worker are separate processes
writing to the same file.
"""

from __future__ import annotations

import sqlite3
from collections.abc import Iterator
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path

SCHEMA = """
CREATE TABLE IF NOT EXISTS runs (
    id                TEXT PRIMARY KEY,
    status            TEXT NOT NULL
                      CHECK (status IN ('QUEUED', 'RUNNING', 'SUCCEEDED', 'FAILED')),
    source_key        TEXT NOT NULL,
    idempotency_key   TEXT UNIQUE,
    attempts          INTEGER NOT NULL DEFAULT 0,
    visible_at        TEXT NOT NULL,
    created_at        TEXT NOT NULL,
    started_at        TEXT,
    finished_at       TEXT,
    error             TEXT,
    events_read       INTEGER,
    objects_written   INTEGER,
    objects_deleted   INTEGER
);

-- Supports the claim query.
CREATE INDEX IF NOT EXISTS idx_runs_claimable ON runs (status, visible_at);
CREATE INDEX IF NOT EXISTS idx_runs_created ON runs (created_at DESC);

CREATE TABLE IF NOT EXISTS records (
    run_id         TEXT NOT NULL REFERENCES runs (id) ON DELETE CASCADE,
    object_id      TEXT NOT NULL,
    type           TEXT,
    diameter       REAL,
    geometry       TEXT NOT NULL,
    segment_count  INTEGER NOT NULL,
    vertex_count   INTEGER NOT NULL,
    length_m       REAL NOT NULL,
    bbox_min_x     REAL NOT NULL,
    bbox_min_y     REAL NOT NULL,
    bbox_max_x     REAL NOT NULL,
    bbox_max_y     REAL NOT NULL,
    last_event_id  INTEGER NOT NULL,
    last_event_at  TEXT NOT NULL,

    -- By run so each run's output stays viewable, by object so a redelivered
    -- message upserts rather than duplicating.
    PRIMARY KEY (run_id, object_id)
);
"""


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def to_iso(moment: datetime) -> str:
    return moment.isoformat()


def connect(database_path: Path) -> sqlite3.Connection:
    database_path.parent.mkdir(parents=True, exist_ok=True)

    connection = sqlite3.connect(
        database_path,
        # Autocommit; transactions are opened explicitly where needed.
        isolation_level=None,
        timeout=5.0,
        # FastAPI may run a sync dependency's setup and teardown on different
        # threadpool threads. Safe to relax: each request gets its own connection and
        # never shares it concurrently.
        check_same_thread=False,
    )
    connection.row_factory = sqlite3.Row

    connection.execute("PRAGMA journal_mode = WAL")
    connection.execute("PRAGMA busy_timeout = 5000")
    connection.execute("PRAGMA foreign_keys = ON")
    connection.execute("PRAGMA synchronous = NORMAL")
    return connection


def initialise(database_path: Path) -> None:
    with closing_connection(database_path) as connection:
        connection.executescript(SCHEMA)


@contextmanager
def closing_connection(database_path: Path) -> Iterator[sqlite3.Connection]:
    connection = connect(database_path)
    try:
        yield connection
    finally:
        connection.close()


@contextmanager
def write_transaction(connection: sqlite3.Connection) -> Iterator[sqlite3.Connection]:
    """Take the write lock up front.

    BEGIN IMMEDIATE avoids the mid-transaction upgrade that produces
    'database is locked' between the API and the worker.
    """
    connection.execute("BEGIN IMMEDIATE")
    try:
        yield connection
    except BaseException:
        connection.execute("ROLLBACK")
        raise
    else:
        connection.execute("COMMIT")
