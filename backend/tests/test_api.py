"""API and queue behaviour against a temporary database."""

from __future__ import annotations

import threading
from concurrent.futures import ThreadPoolExecutor

import pytest
from fastapi.testclient import TestClient

from app.config import Settings, get_settings
from app.db import closing_connection
from app.main import create_app
from app.pipeline.runner import execute_run
from app.queue import claim_next_run, complete_run, fail_run


@pytest.fixture
def settings(tmp_path) -> Settings:
    from tests.test_transform import SAMPLE

    return Settings(
        database_path=tmp_path / "test.db",
        source_file=SAMPLE,
        visibility_timeout_seconds=30,
        max_attempts=3,
        poll_interval_seconds=0.01,
        cors_origins=("http://localhost:5173",),
    )


@pytest.fixture
def client(settings) -> TestClient:
    # Settings are passed in, so startup creates the schema in the temporary
    # database. No dependency override is needed and nothing touches the real one.
    with TestClient(create_app(settings)) as test_client:
        yield test_client


class TestAppConfiguration:
    def test_startup_uses_injected_settings_not_the_process_default(self, settings):
        """Regression: lifespan once called get_settings() directly.

        That bypassed the settings this app was built with, so every test run
        created and migrated the real database configured in the environment.
        """
        default_database = get_settings().database_path
        existed_before = default_database.exists()

        with TestClient(create_app(settings)):
            pass

        assert settings.database_path.exists(), "temporary database was not created"
        if not existed_before:
            assert not default_database.exists(), (
                f"startup created the real database at {default_database}"
            )


def drain(settings) -> None:
    """Run the worker loop once, synchronously."""
    with closing_connection(settings.database_path) as connection:
        run = claim_next_run(connection, settings.visibility_timeout_seconds)
        assert run is not None
        result = execute_run(connection, run["id"], settings)
        complete_run(
            connection,
            run["id"],
            result.events_read,
            result.objects_written,
            result.objects_deleted,
        )


class TestTriggering:
    def test_trigger_returns_202_and_does_not_process(self, client):
        response = client.post("/api/v1/runs", json={})
        assert response.status_code == 202

        body = response.json()
        assert body["status"] == "QUEUED"
        assert body["objects_written"] is None
        assert response.headers["Location"].endswith(body["run_id"])

    def test_idempotency_key_returns_the_same_run(self, client):
        first = client.post("/api/v1/runs", json={"idempotency_key": "abc"}).json()
        second = client.post("/api/v1/runs", json={"idempotency_key": "abc"}).json()
        assert first["run_id"] == second["run_id"]

    def test_unknown_run_is_404(self, client):
        assert client.get("/api/v1/runs/does-not-exist").status_code == 404


class TestEndToEnd:
    def test_run_reaches_succeeded_with_the_expected_output(self, client, settings):
        run_id = client.post("/api/v1/runs", json={}).json()["run_id"]
        drain(settings)

        run = client.get(f"/api/v1/runs/{run_id}").json()
        assert run["status"] == "SUCCEEDED"
        assert run["events_read"] == 50
        assert run["objects_written"] == 9
        assert run["objects_deleted"] == 1

        records = client.get(f"/api/v1/runs/{run_id}/records").json()
        assert records["page"]["total"] == 9
        assert len(records["records"]) == 9
        assert all(r["length_m"] > 0 for r in records["records"])

    def test_records_are_empty_but_not_404_while_queued(self, client):
        run_id = client.post("/api/v1/runs", json={}).json()["run_id"]
        response = client.get(f"/api/v1/runs/{run_id}/records")
        assert response.status_code == 200
        assert response.json()["status"] == "QUEUED"
        assert response.json()["records"] == []

    def test_rerunning_the_same_run_is_idempotent(self, client, settings):
        run_id = client.post("/api/v1/runs", json={}).json()["run_id"]
        drain(settings)

        with closing_connection(settings.database_path) as connection:
            execute_run(connection, run_id, settings)

        assert client.get(f"/api/v1/runs/{run_id}/records").json()["page"]["total"] == 9


class TestQueueSemantics:
    def test_a_run_is_claimed_only_once(self, client, settings):
        client.post("/api/v1/runs", json={})
        with closing_connection(settings.database_path) as connection:
            assert claim_next_run(connection, 30) is not None
            assert claim_next_run(connection, 30) is None

    def test_expired_visibility_makes_a_run_claimable_again(self, client, settings):
        client.post("/api/v1/runs", json={})
        with closing_connection(settings.database_path) as connection:
            first = claim_next_run(connection, visibility_timeout_seconds=0)
            second = claim_next_run(connection, visibility_timeout_seconds=30)
            assert first["id"] == second["id"]
            assert second["attempts"] == 2

    def test_run_is_terminal_after_max_attempts(self, client, settings):
        run_id = client.post("/api/v1/runs", json={}).json()["run_id"]
        with closing_connection(settings.database_path) as connection:
            for _ in range(settings.max_attempts - 1):
                claim_next_run(connection, 0)
                assert fail_run(connection, run_id, "boom", settings.max_attempts) is False

            claim_next_run(connection, 0)
            assert fail_run(connection, run_id, "boom", settings.max_attempts) is True

        assert client.get(f"/api/v1/runs/{run_id}").json()["status"] == "FAILED"


class TestConnectionThreading:
    """Regression: SQLite refuses cross-thread use by default.

    FastAPI runs sync generator dependencies in a worker thread pool and may run the
    generator's setup and teardown on different threads. With the default
    check_same_thread=True, closing the connection raised ProgrammingError as soon as
    two requests overlapped - which sequential curl calls never triggered, but a
    browser loading the page did.
    """

    def test_connection_survives_moving_between_threads(self, settings):
        from app.db import connect

        connection = connect(settings.database_path)
        failures: list[Exception] = []

        def use_and_close() -> None:
            try:
                connection.execute("SELECT 1").fetchone()
                connection.close()
            except Exception as exc:  # noqa: BLE001 - recorded and asserted below
                failures.append(exc)

        thread = threading.Thread(target=use_and_close)
        thread.start()
        thread.join()

        assert failures == [], f"connection could not be used from another thread: {failures}"

    def test_concurrent_requests_all_succeed(self, client, settings):
        """The actual failure mode: parallel requests, as the SPA makes on load."""
        run_id = client.post("/api/v1/runs", json={}).json()["run_id"]
        drain(settings)

        paths = [
            "/api/v1/runs",
            f"/api/v1/runs/{run_id}",
            f"/api/v1/runs/{run_id}/records",
        ] * 6

        with ThreadPoolExecutor(max_workers=8) as pool:
            codes = list(pool.map(lambda path: client.get(path).status_code, paths))

        assert all(code == 200 for code in codes), f"got {sorted(set(codes))}"
