/**
 * Polls a single run until it reaches a terminal status.
 *
 * Polling is the deliberate choice here: it is trivial, needs no persistent
 * connection, and works through any proxy. What it costs is a request per interval
 * per viewer while a run is in flight, and a status latency bounded by that
 * interval. Server-sent events are the production answer; see the README.
 *
 * Two things this hook is careful about:
 *  - it stops the moment the run is SUCCEEDED or FAILED, rather than polling forever
 *  - every request is abortable, so unmounting or switching runs cannot land a stale
 *    response on top of newer state
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

  // Bumping this re-runs the effect, which is how a manual refresh is expressed
  // without duplicating the fetch logic outside the effect.
  const [refreshToken, setRefreshToken] = useState(0);

  const refresh = useCallback(() => {
    setRefreshToken((token) => token + 1);
  }, []);

  // Held in a ref so the polling loop can read the latest status without the effect
  // depending on `run` and therefore restarting on every tick.
  const statusRef = useRef<Run["status"] | null>(null);
  statusRef.current = run?.status ?? null;

  useEffect(() => {
    if (runId === null) {
      setRun(null);
      setError(null);
      return;
    }

    // A different run is being watched; drop the previous one immediately rather
    // than showing another run's status under the new id.
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
          // A 404 will not fix itself - the run does not exist. Anything else might
          // be the backend restarting, so keep polling.
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
