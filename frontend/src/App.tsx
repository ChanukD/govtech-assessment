/**
 * The whole workflow on one screen. App owns only which run is selected; fetching,
 * polling and paging live in hooks.
 */

import { useCallback, useEffect, useState } from "react";

import { ApiError, triggerRun } from "@/api/client";
import { isTerminal } from "@/api/types";
import { ErrorBanner } from "@/components/ErrorBanner";
import { RecordsTable } from "@/components/RecordsTable";
import { RunDetail } from "@/components/RunDetail";
import { RunHistory } from "@/components/RunHistory";
import { TriggerPanel } from "@/components/TriggerPanel";
import { useRunHistory } from "@/hooks/useRunHistory";
import { useRunPolling } from "@/hooks/useRunPolling";
import { RECORDS_PAGE_SIZE, useRunRecords } from "@/hooks/useRunRecords";

export function App() {
  const [selectedRunId, setSelectedRunId] = useState<string | null>(null);
  const [isTriggering, setIsTriggering] = useState(false);
  const [triggerError, setTriggerError] = useState<ApiError | null>(null);

  const history = useRunHistory();
  // Stable useCallback: effects can depend on it without re-running on every render.
  const { reload: reloadHistory } = history;
  const { run, error: pollError, isPolling, refresh } = useRunPolling(selectedRunId);

  // Output is only fetched once the run has finished.
  const isComplete = run !== null && isTerminal(run.status);
  const records = useRunRecords(selectedRunId, isComplete);

  // Show something on first load rather than an empty pane.
  useEffect(() => {
    if (selectedRunId === null && history.runs.length > 0) {
      setSelectedRunId(history.runs[0]?.run_id ?? null);
    }
  }, [history.runs, selectedRunId]);

  // Keeps the list's badge from disagreeing with the detail panel beside it.
  useEffect(() => {
    if (isComplete) reloadHistory();
  }, [isComplete, run?.run_id, reloadHistory]);

  const handleTrigger = useCallback(async (): Promise<void> => {
    setIsTriggering(true);
    setTriggerError(null);

    try {
      const created = await triggerRun();
      setSelectedRunId(created.run_id);
      reloadHistory();
    } catch (cause) {
      if (cause instanceof ApiError) setTriggerError(cause);
      else throw cause;
    } finally {
      setIsTriggering(false);
    }
  }, [reloadHistory]);

  return (
    <div className="app">
      <header className="app__header">
        <h1>Data Transformation Pipeline</h1>
        <p className="muted">
          Trigger an asynchronous pipeline and view its output.
        </p>
      </header>

      <main className="app__main">
        <div className="app__sidebar">
          <TriggerPanel
            onTrigger={() => void handleTrigger()}
            isTriggering={isTriggering}
            isRunInFlight={isPolling}
          />

          {triggerError && (
            <ErrorBanner error={triggerError} onRetry={() => void handleTrigger()} />
          )}

          <RunHistory
            runs={history.runs}
            total={history.total}
            selectedRunId={selectedRunId}
            isLoading={history.isLoading}
            onSelect={setSelectedRunId}
          />

          {history.error && <ErrorBanner error={history.error} onRetry={history.reload} />}
        </div>

        <div className="app__content">
          {selectedRunId === null ? (
            <section className="panel panel--empty">
              <p className="muted">
                No run selected. Trigger the pipeline to create one.
              </p>
            </section>
          ) : pollError && run === null ? (
            <ErrorBanner error={pollError} onRetry={refresh} />
          ) : run === null ? (
            <section className="panel panel--empty">
              <p className="muted">Loading run…</p>
            </section>
          ) : (
            <>
              <RunDetail run={run} isPolling={isPolling} />

              {isPolling && (
                <section className="panel" aria-label="Output pending">
                  <p className="muted">
                    Waiting for the worker. Output appears here once the run completes.
                  </p>
                  <ul className="skeleton-list" aria-hidden="true">
                    {[0, 1, 2].map((row) => (
                      <li key={row} className="skeleton" />
                    ))}
                  </ul>
                </section>
              )}

              {run.status === "SUCCEEDED" && (
                <>
                  <RecordsTable
                    records={records.records}
                    total={records.total}
                    offset={records.offset}
                    pageSize={RECORDS_PAGE_SIZE}
                    isLoading={records.isLoading}
                    onOffsetChange={records.setOffset}
                  />
                  {records.error && <ErrorBanner error={records.error} />}
                </>
              )}
            </>
          )}
        </div>
      </main>
    </div>
  );
}
