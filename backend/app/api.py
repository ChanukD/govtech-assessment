"""HTTP routes. No endpoint does pipeline work - that is the worker's job."""

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
    """Settings for this app instance.

    Read from app.state, not the process-wide get_settings() cache, so routes and
    startup always agree on which configuration they are using.
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
    """Queue a run and return immediately. 202: accepted, not completed."""
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

    200 with an empty list while in flight, not 404: the run exists, its output does
    not yet. The status field distinguishes the two.
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
