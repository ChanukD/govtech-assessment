/**
 * Polls a run until it reaches a terminal status, then stops.
 *
 * Polling costs a request per interval per viewer and bounds status latency by that
 * interval; server-sent events are the production answer. Requests are abortable so a
 * stale response cannot land on newer state.
 */

import { useCallback, useEffect, useRef, useState } from "react";

import { ApiError, getRun } from "@/api/client";
import { isTerminal, type Run } from "@/api/types";

const DEFAULT_INTERVAL_MS = 1000;

interface UseRunPollingResult {
  run: Run | null;
  error: ApiError | null;
  /** True while a non-terminal run is being watched. */
  isPolling: boolean;
  refresh: () => void;
}

export function useRunPolling(
  runId: string | null,
  intervalMs: number = DEFAULT_INTERVAL_MS,
): UseRunPollingResult {
  const [run, setRun] = useState<Run | null>(null);
  const [error, setError] = useState<ApiError | null>(null);

  // Bumping this re-runs the effect, so refresh reuses the same fetch logic.
  const [refreshToken, setRefreshToken] = useState(0);

  const refresh = useCallback(() => {
    setRefreshToken((token) => token + 1);
  }, []);

  // A ref, so the loop reads the latest status without restarting on every tick.
  const statusRef = useRef<Run["status"] | null>(null);
  statusRef.current = run?.status ?? null;

  useEffect(() => {
    if (runId === null) {
      setRun(null);
      setError(null);
      return;
    }

    // Drop the previous run rather than showing its status under the new id.
    setRun(null);
    setError(null);
    statusRef.current = null;

    const controller = new AbortController();
    let timer: ReturnType<typeof setTimeout> | undefined;
    let cancelled = false;

    const poll = async (): Promise<void> => {
      try {
        const next = await getRun(runId, controller.signal);
        if (cancelled) return;

        setRun(next);
        setError(null);
        statusRef.current = next.status;

        if (isTerminal(next.status)) return;
      } catch (cause) {
        if (cancelled || controller.signal.aborted) return;
        if (cause instanceof ApiError) {
          setError(cause);
          // A 404 will not fix itself; anything else might be a restart.
          if (cause.status === 404) return;
        } else {
          throw cause;
        }
      }

      timer = setTimeout(() => void poll(), intervalMs);
    };

    void poll();

    return () => {
      cancelled = true;
      controller.abort();
      if (timer !== undefined) clearTimeout(timer);
    };
  }, [runId, intervalMs, refreshToken]);

  return {
    run,
    error,
    isPolling: run !== null && !isTerminal(run.status),
    refresh,
  };
}
