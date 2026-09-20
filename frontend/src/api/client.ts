/**
 * The only module that knows how to talk to the backend.
 *
 * Requests use relative paths. In development Vite proxies /api to the backend; in
 * production CloudFront forwards it to the ALB. Same-origin in both, so there is no
 * base URL to configure per environment and no CORS to negotiate.
 */

import type {
  RecordListResponse,
  Run,
  RunListResponse,
  TriggerRunRequest,
} from "@/api/types";

/** A failed request, carrying enough context for the UI to say something useful. */
export class ApiError extends Error {
  readonly status: number;
  readonly detail: string | undefined;

  constructor(message: string, status: number, detail?: string) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.detail = detail;
  }

  /** True when retrying might plausibly succeed. Drives whether we offer a retry. */
  get isRetryable(): boolean {
    return this.status === 0 || this.status >= 500;
  }
}

interface RequestOptions {
  signal?: AbortSignal | undefined;
  body?: unknown;
  method?: "GET" | "POST";
}

/** FastAPI returns `{detail: string}` for HTTPException and a list for 422. */
async function extractDetail(response: Response): Promise<string | undefined> {
  try {
    const body: unknown = await response.json();
    if (typeof body === "object" && body !== null && "detail" in body) {
      const { detail } = body;
      if (typeof detail === "string") return detail;
      if (Array.isArray(detail)) return detail.map((item) => JSON.stringify(item)).join("; ");
    }
  } catch {
    // A non-JSON error body tells us nothing extra; fall through to the status text.
  }
  return undefined;
}

async function request<T>(path: string, options: RequestOptions = {}): Promise<T> {
  const { signal, body, method = "GET" } = options;

  // Built up rather than declared inline: under exactOptionalPropertyTypes, an
  // explicit `undefined` is not the same as an absent property, and RequestInit
  // accepts the latter only.
  const init: RequestInit = { method };
  if (signal !== undefined) init.signal = signal;
  if (body !== undefined) {
    init.headers = { "Content-Type": "application/json" };
    init.body = JSON.stringify(body);
  }

  let response: Response;
  try {
    response = await fetch(path, init);
  } catch (cause) {
    // An aborted request is a caller decision, not a failure - let it propagate so
    // callers can ignore it rather than rendering an error for their own cleanup.
    if (cause instanceof DOMException && cause.name === "AbortError") throw cause;
    throw new ApiError("Cannot reach the API. Is the backend running?", 0);
  }

  if (!response.ok) {
    const detail = await extractDetail(response);
    throw new ApiError(
      detail ?? `Request failed with status ${response.status}`,
      response.status,
      detail,
    );
  }

  return (await response.json()) as T;
}

/**
 * Queue a pipeline run.
 *
 * Returns as soon as the run is accepted - the response is a QUEUED run, never a
 * finished one. The caller polls for the rest.
 */
export function triggerRun(
  body: TriggerRunRequest = {},
  signal?: AbortSignal,
): Promise<Run> {
  return request<Run>("/api/v1/runs", { method: "POST", body, signal });
}

export function getRun(runId: string, signal?: AbortSignal): Promise<Run> {
  return request<Run>(`/api/v1/runs/${encodeURIComponent(runId)}`, { signal });
}

export function listRuns(
  { limit = 20, offset = 0 }: { limit?: number; offset?: number } = {},
  signal?: AbortSignal,
): Promise<RunListResponse> {
  return request<RunListResponse>(`/api/v1/runs?limit=${limit}&offset=${offset}`, { signal });
}

export function listRecords(
  runId: string,
  { limit = 50, offset = 0 }: { limit?: number; offset?: number } = {},
  signal?: AbortSignal,
): Promise<RecordListResponse> {
  const query = `limit=${limit}&offset=${offset}`;
  return request<RecordListResponse>(
    `/api/v1/runs/${encodeURIComponent(runId)}/records?${query}`,
    { signal },
  );
}
