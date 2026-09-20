"""HTTP routes.

The only rule that matters here: no endpoint does pipeline work. Creating a run is
one INSERT and a 202. Everything expensive happens in the worker.
"""

from __future__ import annotations

import sqlite3
from collections.abc import Iterator

from fastapi import APIRouter, Depends, HTTPException, Query, Request, Response, status

from app.config import Settings
from app.db import closing_connection
from app.repository import create_run, get_run, list_records, list_runs
from app.schemas import (
    CreateRunRequest,
    HealthResponse,
    Page,
    RecordListResponse,
    RecordOut,
    RunListResponse,
    RunSummary,
)

router = APIRouter()


def get_app_settings(request: Request) -> Settings:
    """Settings belonging to this app instance.

    Read from app.state rather than by calling get_settings(), which is a
    process-wide cache. Going through the app means every layer - routes, and the
    startup hook that creates the schema - sees the same object, so a test or a
    second app instance can supply its own without one of them silently falling back
    to the real configuration.
    """
    return request.app.state.settings


def get_connection(
    settings: Settings = Depends(get_app_settings),
) -> Iterator[sqlite3.Connection]:
    with closing_connection(settings.database_path) as connection:
        yield connection


@router.get("/healthz", response_model=HealthResponse, tags=["meta"])
def healthz() -> HealthResponse:
    """Liveness probe. This is the path the ALB target group polls."""
    return HealthResponse(status="ok")


@router.post(
    "/api/v1/runs",
    response_model=RunSummary,
    status_code=status.HTTP_202_ACCEPTED,
    tags=["runs"],
)
def trigger_run(
    request: CreateRunRequest,
    response: Response,
    connection: sqlite3.Connection = Depends(get_connection),
    settings: Settings = Depends(get_app_settings),
) -> RunSummary:
    """Queue a pipeline run and return immediately.

    202 rather than 201: the run has been accepted, not completed. Response time is
    one insert regardless of how large the input is.
    """
    row = create_run(
        connection,
        source_key=settings.source_key,
        idempotency_key=request.idempotency_key,
    )
    run = RunSummary.from_row(row)
    response.headers["Location"] = f"/api/v1/runs/{run.run_id}"
    return run


@router.get("/api/v1/runs", response_model=RunListResponse, tags=["runs"])
def get_runs(
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    connection: sqlite3.Connection = Depends(get_connection),
) -> RunListResponse:
    rows, total = list_runs(connection, limit=limit, offset=offset)
    return RunListResponse(
        runs=[RunSummary.from_row(row) for row in rows],
        page=Page(total=total, limit=limit, offset=offset),
    )


@router.get("/api/v1/runs/{run_id}", response_model=RunSummary, tags=["runs"])
def get_run_status(
    run_id: str,
    connection: sqlite3.Connection = Depends(get_connection),
) -> RunSummary:
    """The endpoint the frontend polls while a run is in flight."""
    row = get_run(connection, run_id)
    if row is None:
        raise HTTPException(status_code=404, detail=f"run {run_id} not found")
    return RunSummary.from_row(row)


@router.get(
    "/api/v1/runs/{run_id}/records",
    response_model=RecordListResponse,
    tags=["runs"],
)
def get_run_records(
    run_id: str,
    limit: int = Query(default=50, ge=1, le=500),
    offset: int = Query(default=0, ge=0),
    connection: sqlite3.Connection = Depends(get_connection),
) -> RecordListResponse:
    """A run's transformed output.

    Returns 200 with an empty list while the run is still in flight rather than 404 -
    the run exists, its output does not yet. The status field tells the caller which
    of those it is looking at.
    """
    run = get_run(connection, run_id)
    if run is None:
        raise HTTPException(status_code=404, detail=f"run {run_id} not found")

    rows, total = list_records(connection, run_id, limit=limit, offset=offset)
    return RecordListResponse(
        run_id=run_id,
        status=run["status"],
        records=[RecordOut.from_row(row) for row in rows],
        page=Page(total=total, limit=limit, offset=offset),
    )
