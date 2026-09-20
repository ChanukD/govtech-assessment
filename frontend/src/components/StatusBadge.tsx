import type { RunStatus } from "@/api/types";

interface StatusBadgeProps {
  status: RunStatus;
  /** Renders a pulsing dot for in-flight runs. */
  animated?: boolean;
}

const LABELS: Record<RunStatus, string> = {
  QUEUED: "Queued",
  RUNNING: "Running",
  SUCCEEDED: "Succeeded",
  FAILED: "Failed",
};

export function StatusBadge({ status, animated = false }: StatusBadgeProps) {
  const inFlight = status === "QUEUED" || status === "RUNNING";

  return (
    <span className={`badge badge--${status.toLowerCase()}`}>
      <span
        className={`badge__dot${animated && inFlight ? " badge__dot--pulse" : ""}`}
        aria-hidden="true"
      />
      {LABELS[status]}
    </span>
  );
}
