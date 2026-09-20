/**
 * Mirrors the backend's Pydantic schemas (`backend/app/schemas.py`). Hand-written:
 * at this size, generating from /openapi.json would be more machinery than it saves.
 */

export const RUN_STATUSES = ["QUEUED", "RUNNING", "SUCCEEDED", "FAILED"] as const;

export type RunStatus = (typeof RUN_STATUSES)[number];

/** Statuses the worker will never move away from. Polling stops here. */
const TERMINAL_STATUSES: ReadonlySet<RunStatus> = new Set<RunStatus>(["SUCCEEDED", "FAILED"]);

export function isTerminal(status: RunStatus): boolean {
  return TERMINAL_STATUSES.has(status);
}

export interface Run {
  run_id: string;
  status: RunStatus;
  source_key: string;
  attempts: number;
  created_at: string;
  started_at: string | null;
  finished_at: string | null;
  error: string | null;
  events_read: number | null;
  objects_written: number | null;
  objects_deleted: number | null;
}

export interface BoundingBox {
  min_x: number;
  min_y: number;
  max_x: number;
  max_y: number;
}

export interface PipelineRecord {
  object_id: string;
  type: string | null;
  diameter: number | null;
  geometry: string;
  segment_count: number;
  vertex_count: number;
  length_m: number;
  bbox: BoundingBox;
  last_event_id: number;
  last_event_at: string;
}

export interface Page {
  total: number;
  limit: number;
  offset: number;
}

export interface RunListResponse {
  runs: Run[];
  page: Page;
}

export interface RecordListResponse {
  run_id: string;
  status: RunStatus;
  records: PipelineRecord[];
  page: Page;
}

export interface TriggerRunRequest {
  idempotency_key?: string;
}
