"""Orchestrates a single run: read, transform, persist."""

from __future__ import annotations

import logging
import sqlite3

from app.config import Settings
from app.pipeline.source import read_rows
from app.pipeline.transform import TransformResult, transform
from app.repository import replace_records

logger = logging.getLogger(__name__)


def execute_run(
    connection: sqlite3.Connection,
    run_id: str,
    settings: Settings,
) -> TransformResult:
    logger.info("run %s: reading %s", run_id, settings.source_file)
    rows = read_rows(settings.source_file)

    logger.info("run %s: transforming %d events", run_id, len(rows))
    result = transform(rows)

    logger.info(
        "run %s: writing %d objects (%d deleted)",
        run_id,
        result.objects_written,
        result.objects_deleted,
    )
    replace_records(connection, run_id, result.objects)

    return result
