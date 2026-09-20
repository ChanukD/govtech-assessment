"""The queue, expressed in SQL.

Local equivalent of SQS: claim is ReceiveMessage plus a visibility timeout, complete
is DeleteMessage, and a run that exhausts max_attempts is the dead-letter queue.
"""

from __future__ import annotations

import sqlite3
from datetime import timedelta

from app.db import to_iso, utc_now, write_transaction


def claim_next_run(
    connection: sqlite3.Connection, visibility_timeout_seconds: int
) -> sqlite3.Row | None:
    """Atomically claim one runnable run, or return None.

    A run is claimable when it is QUEUED, or RUNNING with an expired visibility
    window - which is how a run whose worker died gets picked up again. Selection and
    update are one statement, so a second worker finds no row rather than a duplicate.
    """
    now = utc_now()
    visible_until = now + timedelta(seconds=visibility_timeout_seconds)

    with write_transaction(connection):
        row = connection.execute(
            """
            UPDATE runs
               SET status     = 'RUNNING',
                   attempts   = attempts + 1,
                   started_at = COALESCE(started_at, ?),
                   visible_at = ?
             WHERE id = (
                   SELECT id
                     FROM runs
                    WHERE status = 'QUEUED'
                       OR (status = 'RUNNING' AND visible_at <= ?)
                 ORDER BY created_at
                    LIMIT 1
             )
         RETURNING *
            """,
            (to_iso(now), to_iso(visible_until), to_iso(now)),
        ).fetchone()

    return row


def complete_run(
    connection: sqlite3.Connection,
    run_id: str,
    events_read: int,
    objects_written: int,
    objects_deleted: int,
) -> None:
    with write_transaction(connection):
        connection.execute(
            """
            UPDATE runs
               SET status          = 'SUCCEEDED',
                   finished_at     = ?,
                   error           = NULL,
                   events_read     = ?,
                   objects_written = ?,
                   objects_deleted = ?
             WHERE id = ?
            """,
            (to_iso(utc_now()), events_read, objects_written, objects_deleted, run_id),
        )


def fail_run(
    connection: sqlite3.Connection,
    run_id: str,
    error: str,
    max_attempts: int,
) -> bool:
    """Record a failure. Returns True if the run is now terminal.

    Below max_attempts the run returns to QUEUED and is retried; at max_attempts it
    becomes FAILED and is never claimed again.
    """
    now = utc_now()

    with write_transaction(connection):
        row = connection.execute(
            "SELECT attempts FROM runs WHERE id = ?", (run_id,)
        ).fetchone()
        if row is None:
            return True

        exhausted = row["attempts"] >= max_attempts
        connection.execute(
            """
            UPDATE runs
               SET status      = CASE WHEN ? THEN 'FAILED' ELSE 'QUEUED' END,
                   error       = ?,
                   visible_at  = ?,
                   finished_at = CASE WHEN ? THEN ? ELSE NULL END
             WHERE id = ?
            """,
            (exhausted, error[:2000], to_iso(now), exhausted, to_iso(now), run_id),
        )

    return exhausted
