"""Application factory."""

from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware import CORSMiddleware

from app.api import router
from app.config import Settings, get_settings
from app.db import initialise

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)

logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Taken from the app, not from get_settings(). Calling the process-wide cache
    # here would ignore whatever settings this particular app was built with and
    # create the schema against the real configured database instead.
    settings: Settings = app.state.settings

    initialise(settings.database_path)
    logger.info(
        "API ready | database=%s source=%s",
        settings.database_path,
        settings.source_file,
    )
    yield


def create_app(settings: Settings | None = None) -> FastAPI:
    """Build an app instance.

    Settings are an argument so that a caller can supply their own - a test, or a
    second instance in one process. Omitted, they come from the environment.
    """
    settings = settings or get_settings()

    app = FastAPI(
        title="Data Transformation Pipeline",
        version="0.1.0",
        summary="Trigger an asynchronous pipeline and read its output.",
        lifespan=lifespan,
    )

    # Set before startup runs, because lifespan reads it.
    app.state.settings = settings

    # Needed only in local development. In AWS the SPA and the API are served from
    # one CloudFront distribution, so requests are same-origin and no CORS applies.
    app.add_middleware(
        CORSMiddleware,
        allow_origins=list(settings.cors_origins),
        allow_methods=["GET", "POST", "OPTIONS"],
        allow_headers=["*"],
    )

    app.include_router(router)
    return app


app = create_app()
