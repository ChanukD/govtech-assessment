interface TriggerPanelProps {
  onTrigger: () => void;
  isTriggering: boolean;
  isRunInFlight: boolean;
}

export function TriggerPanel({
  onTrigger,
  isTriggering,
  isRunInFlight,
}: TriggerPanelProps) {
  return (
    <section className="panel panel--accent" aria-labelledby="trigger-heading">
      <h2 id="trigger-heading">Transformation pipeline</h2>
      <p className="muted">
        Replays the source changelog, folds it to the latest state per object, and
        writes the result to the database. Runs asynchronously — the request returns
        as soon as the run is queued.
      </p>

      <button
        type="button"
        className="button button--primary"
        onClick={onTrigger}
        disabled={isTriggering}
      >
        {isTriggering ? "Starting…" : "Trigger pipeline"}
      </button>

      {/* Allowed: the backend queues it. Said explicitly, or the click looks broken. */}
      {isRunInFlight && !isTriggering && (
        <p className="hint">A run is in progress. Triggering again queues another.</p>
      )}
    </section>
  );
}
