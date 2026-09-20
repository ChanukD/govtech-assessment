/**
 * Loads a run's output, one page at a time. `enabled` holds off until the run is
 * terminal - fetching earlier is a request whose answer is already known.
 */

import { useCallback, useEffect, useState } from "react";

import { ApiError, listRecords } from "@/api/client";
import type { PipelineRecord } from "@/api/types";

export const RECORDS_PAGE_SIZE = 25;

interface UseRunRecordsResult {
  records: PipelineRecord[];
  total: number;
  offset: number;
  isLoading: boolean;
  error: ApiError | null;
  setOffset: (offset: number) => void;
}

export function useRunRecords(
  runId: string | null,
  enabled: boolean,
): UseRunRecordsResult {
  const [records, setRecords] = useState<PipelineRecord[]>([]);
  const [total, setTotal] = useState(0);
  const [offset, setOffsetState] = useState(0);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<ApiError | null>(null);

  // Paging is per run.
  useEffect(() => {
    setOffsetState(0);
    setRecords([]);
    setTotal(0);
  }, [runId]);

  const setOffset = useCallback((next: number) => {
    setOffsetState(Math.max(0, next));
  }, []);

  useEffect(() => {
    if (runId === null || !enabled) return;

    const controller = new AbortController();

    const load = async (): Promise<void> => {
      setIsLoading(true);
      try {
        const response = await listRecords(
          runId,
          { limit: RECORDS_PAGE_SIZE, offset },
          controller.signal,
        );
        if (controller.signal.aborted) return;

        setRecords(response.records);
        setTotal(response.page.total);
        setError(null);
      } catch (cause) {
        if (controller.signal.aborted) return;
        if (cause instanceof ApiError) setError(cause);
        else throw cause;
      } finally {
        if (!controller.signal.aborted) setIsLoading(false);
      }
    };

    void load();
    return () => {
      controller.abort();
    };
  }, [runId, enabled, offset]);

  return { records, total, offset, isLoading, error, setOffset };
}
