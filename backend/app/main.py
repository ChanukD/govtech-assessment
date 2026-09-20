"""Application factory."""

from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

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
    # From the app, not get_settings(): the cache would ignore whatever settings
    # this instance was built with.
    settings: Settings = app.state.settings

    initialise(settings.database_path)
    logger.info(
        "API ready | database=%s source=%s",
        settings.database_path,
        settings.source_file,
    )
    yield


def create_app(settings: Settings | None = None) -> FastAPI:
    """Build an app instance. Settings default to the environment."""
    settings = settings or get_settings()

    app = FastAPI(
        title="Data Transformation Pipeline",
        version="0.1.0",
        summary="Trigger an asynchronous pipeline and read its output.",
        lifespan=lifespan,
    )

    # Set before startup, which reads it.
    app.state.settings = settings

    # Local development only: in AWS both are served from one CloudFront
    # distribution, so requests are same-origin.
    app.add_middleware(
        CORSMiddleware,
        allow_origins=list(settings.cors_origins),
        allow_methods=["GET", "POST", "OPTIONS"],
        allow_headers=["*"],
    )

    app.include_router(router)
    return app


app = create_app()
