import type { Run } from "@/api/types";
import { StatusBadge } from "@/components/StatusBadge";
import { formatRelative, formatTimestamp, shortId } from "@/lib/format";

interface RunHistoryProps {
  runs: Run[];
  total: number;
  selectedRunId: string | null;
  isLoading: boolean;
  onSelect: (runId: string) => void;
}

export function RunHistory({
  runs,
  total,
  selectedRunId,
  isLoading,
  onSelect,
}: RunHistoryProps) {
  return (
    <section className="panel" aria-labelledby="history-heading">
      <header className="panel__header">
        <h2 id="history-heading">History</h2>
        {total > 0 && <span className="panel__count">{total}</span>}
      </header>

      {isLoading && runs.length === 0 ? (
        <ul className="skeleton-list" aria-hidden="true">
          {[0, 1, 2].map((row) => (
            <li key={row} className="skeleton" />
          ))}
        </ul>
      ) : runs.length === 0 ? (
        <p className="muted">No runs yet. Trigger one to get started.</p>
      ) : (
        <ul className="run-list">
          {runs.map((run) => {
            const isSelected = run.run_id === selectedRunId;
            return (
              <li key={run.run_id}>
                <button
                  type="button"
                  className={`run-list__item${isSelected ? " run-list__item--selected" : ""}`}
                  onClick={() => {
                    onSelect(run.run_id);
                  }}
                  aria-current={isSelected ? "true" : undefined}
                >
                  <span className="run-list__top">
                    <span className="run-list__id mono">{shortId(run.run_id)}</span>
                    <StatusBadge status={run.status} animated />
                  </span>
                  <span className="run-list__meta">
                    <span title={formatTimestamp(run.created_at)}>
                      {formatRelative(run.created_at)}
                    </span>
                    {run.objects_written !== null && (
                      <span>{run.objects_written} objects</span>
                    )}
                  </span>
                </button>
              </li>
            );
          })}
        </ul>
      )}
    </section>
  );
}
