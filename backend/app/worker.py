"""Worker entrypoint.

A separate process, not a background thread in the API. That is the point of the
design: the API can be restarted, scaled or killed mid-run without affecting work in
flight, and the worker can be scaled independently of request traffic.

The loop mirrors what the Fargate worker does against SQS: claim, process, complete
or fail, repeat.
"""

from __future__ import annotations

import logging
import signal
import sys
import time
from types import FrameType

from app.config import get_settings
from app.db import closing_connection, initialise
from app.pipeline.runner import execute_run
from app.queue import claim_next_run, complete_run, fail_run

logger = logging.getLogger("worker")

_shutdown = False


def _request_shutdown(signum: int, _frame: FrameType | None) -> None:
    """Finish the current run, then stop.

    The equivalent of Fargate's stopTimeout: an in-flight message is completed rather
    than abandoned, so it does not have to wait out a visibility timeout.
    """
    global _shutdown
    _shutdown = True
    logger.info("signal %s received, finishing current run then stopping", signum)


def main() -> int:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)-8s %(name)s | %(message)s",
    )

    signal.signal(signal.SIGINT, _request_shutdown)
    signal.signal(signal.SIGTERM, _request_shutdown)

    settings = get_settings()
    initialise(settings.database_path)

    logger.info(
        "worker ready | database=%s source=%s poll=%.1fs visibility=%ds attempts=%d",
        settings.database_path,
        settings.source_file,
        settings.poll_interval_seconds,
        settings.visibility_timeout_seconds,
        settings.max_attempts,
    )

    with closing_connection(settings.database_path) as connection:
        while not _shutdown:
            run = claim_next_run(connection, settings.visibility_timeout_seconds)

            if run is None:
                # Local stand-in for SQS long polling.
                time.sleep(settings.poll_interval_seconds)
                continue

            run_id = run["id"]
            logger.info("run %s: claimed (attempt %d)", run_id, run["attempts"])

            try:
                result = execute_run(connection, run_id, settings)
            except Exception as exc:  # noqa: BLE001 - the loop must survive any run
                terminal = fail_run(
                    connection, run_id, f"{type(exc).__name__}: {exc}", settings.max_attempts
                )
                logger.exception(
                    "run %s: failed (%s)", run_id, "terminal" if terminal else "will retry"
                )
                continue

            complete_run(
                connection,
                run_id,
                events_read=result.events_read,
                objects_written=result.objects_written,
                objects_deleted=result.objects_deleted,
            )
            logger.info(
                "run %s: succeeded | %d events -> %d objects (%d deleted)",
                run_id,
                result.events_read,
                result.objects_written,
                result.objects_deleted,
            )

    logger.info("worker stopped")
    return 0


if __name__ == "__main__":
    sys.exit(main())
