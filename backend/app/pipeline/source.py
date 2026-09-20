"""Source data access.

Stands in for `s3:GetObject`. The worker is given a key, not a payload, exactly as
it would be in AWS - which is why the API needs no access to the source data at all.
Swapping this module for boto3 is the entire change.
"""

from __future__ import annotations

import csv
from pathlib import Path

REQUIRED_COLUMNS = {"id", "record", "timestamp"}


class SourceError(RuntimeError):
    """The source data could not be read."""


def read_rows(source_file: Path) -> list[dict[str, str]]:
    if not source_file.is_file():
        raise SourceError(f"source file not found: {source_file}")

    with source_file.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        missing = REQUIRED_COLUMNS - set(reader.fieldnames or [])
        if missing:
            raise SourceError(f"source file is missing columns: {sorted(missing)}")

        rows = [row for row in reader]

    if not rows:
        raise SourceError(f"source file contains no rows: {source_file}")

    return rows
