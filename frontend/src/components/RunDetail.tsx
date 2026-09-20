import type { Run } from "@/api/types";
import { PipelineProgress } from "@/components/PipelineProgress";
import { StatusBadge } from "@/components/StatusBadge";
import { useElapsed } from "@/hooks/useElapsed";
import {
  formatDuration,
  formatElapsed,
  formatNumber,
  formatRelative,
  formatTimestamp,
} from "@/lib/format";

interface RunDetailProps {
  run: Run;
  isPolling: boolean;
}

export function RunDetail({ run, isPolling }: RunDetailProps) {
  // Counts from whichever moment the run actually began: started_at once a worker
  // has claimed it, created_at while it is still only queued.
  const elapsed = useElapsed(run.started_at ?? run.created_at, isPolling);

  const duration = isPolling
    ? elapsed === null
      ? "—"
      : formatElapsed(elapsed)
    : formatDuration(run.started_at, run.finished_at);

  return (
    <section className="panel" aria-labelledby="run-heading">
      <header className="panel__header">
        <div className="panel__title">
          <h2 id="run-heading">Run</h2>
          <code className="run-id" title={run.run_id}>
            {run.run_id}
          </code>
        </div>
        <StatusBadge status={run.status} animated />
      </header>

      <PipelineProgress status={run.status} />

      {/*
        Status changes arrive by polling rather than user action, so a screen reader
        needs to be told. Polite, so it does not interrupt.
      */}
      <p className="sr-only" aria-live="polite">
        {`Run ${run.status.toLowerCase()}.`}
      </p>

      <dl className="detail-grid">
        <div>
          <dt>Source</dt>
          <dd className="mono">{run.source_key}</dd>
        </div>
        <div>
          <dt>Triggered</dt>
          <dd title={formatTimestamp(run.created_at)}>{formatRelative(run.created_at)}</dd>
        </div>
        <div>
          <dt>{isPolling ? "Elapsed" : "Duration"}</dt>
          <dd className={isPolling ? "live" : undefined}>{duration}</dd>
        </div>
        <div>
          <dt>Attempts</dt>
          <dd>{run.attempts}</dd>
        </div>
      </dl>

      {run.status === "SUCCEEDED" && (
        <dl className="stat-row">
          <div className="stat">
            <dt>Events read</dt>
            <dd>{formatNumber(run.events_read ?? 0)}</dd>
          </div>
          <div className="stat">
            <dt>Objects written</dt>
            <dd>{formatNumber(run.objects_written ?? 0)}</dd>
          </div>
          <div className="stat stat--muted">
            <dt>Deleted</dt>
            <dd>{formatNumber(run.objects_deleted ?? 0)}</dd>
          </div>
        </dl>
      )}

      {run.status === "FAILED" && run.error !== null && (
        <div className="banner banner--error" role="alert">
          <div className="banner__body">
            <strong>
              Failed after {run.attempts} {run.attempts === 1 ? "attempt" : "attempts"}
            </strong>
            <p className="mono">{run.error}</p>
          </div>
        </div>
      )}
    </section>
  );
}
