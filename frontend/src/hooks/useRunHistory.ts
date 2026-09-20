/** Loads the run history, refreshed on demand. */

import { useCallback, useEffect, useState } from "react";

import { ApiError, listRuns } from "@/api/client";
import type { Run } from "@/api/types";

const PAGE_SIZE = 20;

interface UseRunHistoryResult {
  runs: Run[];
  total: number;
  isLoading: boolean;
  error: ApiError | null;
  reload: () => void;
}

export function useRunHistory(): UseRunHistoryResult {
  const [runs, setRuns] = useState<Run[]>([]);
  const [total, setTotal] = useState(0);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<ApiError | null>(null);
  const [reloadToken, setReloadToken] = useState(0);

  const reload = useCallback(() => {
    setReloadToken((token) => token + 1);
  }, []);

  useEffect(() => {
    const controller = new AbortController();

    const load = async (): Promise<void> => {
      setIsLoading(true);
      try {
        const response = await listRuns({ limit: PAGE_SIZE }, controller.signal);
        if (controller.signal.aborted) return;

        setRuns(response.runs);
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
  }, [reloadToken]);

  return { runs, total, isLoading, error, reload };
}
