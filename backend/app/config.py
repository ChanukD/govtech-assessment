"""Configuration, read once from the environment.

Every value that would be a cloud resource in production (bucket, queue, database)
is a local path or a tuning knob here. That is the only place the local and hosted
versions of this application differ.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parents[1]


def _path(name: str, default: str) -> Path:
    raw = os.environ.get(name, default)
    path = Path(raw).expanduser()
    return path if path.is_absolute() else (BACKEND_ROOT / path).resolve()


def _float(name: str, default: float) -> float:
    try:
        return float(os.environ[name])
    except (KeyError, ValueError):
        return default


def _int(name: str, default: int) -> int:
    try:
        return int(os.environ[name])
    except (KeyError, ValueError):
        return default


@dataclass(frozen=True)
class Settings:
    database_path: Path
    source_file: Path
    visibility_timeout_seconds: int
    max_attempts: int
    poll_interval_seconds: float
    cors_origins: tuple[str, ...]

    @property
    def source_key(self) -> str:
        """The name a run records as its input.

        Against S3 this would be an object key; locally it is the file name. The
        message the API enqueues carries this, never the file contents.
        """
        return self.source_file.name


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    origins = os.environ.get("PIPELINE_CORS_ORIGINS", "http://localhost:5173")
    return Settings(
        database_path=_path("PIPELINE_DATABASE_PATH", "./pipeline.db"),
        source_file=_path("PIPELINE_SOURCE_FILE", "../data/records.csv"),
        visibility_timeout_seconds=_int("PIPELINE_VISIBILITY_TIMEOUT_SECONDS", 30),
        max_attempts=_int("PIPELINE_MAX_ATTEMPTS", 3),
        poll_interval_seconds=_float("PIPELINE_POLL_INTERVAL_SECONDS", 1.0),
        cors_origins=tuple(o.strip() for o in origins.split(",") if o.strip()),
    )
