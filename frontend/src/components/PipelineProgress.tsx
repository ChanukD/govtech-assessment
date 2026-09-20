/**
 * The run's position in the pipeline as three stages rather than one badge, which
 * makes the asynchronous handoff visible: accepted at stage one, worked at stage two.
 */

import type { RunStatus } from "@/api/types";

type StageState = "done" | "active" | "pending" | "failed";

interface Stage {
  label: string;
  hint: string;
}

const STAGES: readonly Stage[] = [
  { label: "Queued", hint: "Accepted, waiting for a worker" },
  { label: "Running", hint: "Reading source, transforming" },
  { label: "Complete", hint: "Output written to the database" },
];

/** A failed run marks the stage it died in, not a third completed step. */
function stateFor(index: number, status: RunStatus): StageState {
  switch (status) {
    case "QUEUED":
      return index === 0 ? "active" : "pending";
    case "RUNNING":
      if (index === 0) return "done";
      return index === 1 ? "active" : "pending";
    case "SUCCEEDED":
      return "done";
    case "FAILED":
      if (index === 0) return "done";
      return index === 1 ? "failed" : "pending";
  }
}

interface PipelineProgressProps {
  status: RunStatus;
}

export function PipelineProgress({ status }: PipelineProgressProps) {
  return (
    <ol className="progress" aria-label="Pipeline stages">
      {STAGES.map((stage, index) => {
        const state = stateFor(index, status);
        return (
          <li
            key={stage.label}
            className={`progress__step progress__step--${state}`}
            aria-current={state === "active" ? "step" : undefined}
          >
            <span className="progress__marker" aria-hidden="true">
              {state === "done" ? "✓" : state === "failed" ? "!" : index + 1}
            </span>
            <span className="progress__text">
              <span className="progress__label">{stage.label}</span>
              <span className="progress__hint">{stage.hint}</span>
            </span>
          </li>
        );
      })}
    </ol>
  );
}
