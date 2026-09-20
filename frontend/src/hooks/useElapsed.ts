/**
 * A ticking elapsed time for an in-flight run. Stops when `active` goes false, so a
 * finished run costs no timers.
 */

import { useEffect, useState } from "react";

const TICK_MS = 500;

export function useElapsed(since: string | null, active: boolean): number | null {
  const [now, setNow] = useState(() => Date.now());

  useEffect(() => {
    if (!active) return;

    // Re-read immediately so a freshly selected run is not stale until the first tick.
    setNow(Date.now());

    const timer = setInterval(() => {
      setNow(Date.now());
    }, TICK_MS);

    return () => {
      clearInterval(timer);
    };
  }, [active, since]);

  if (since === null) return null;

  const started = new Date(since.includes("T") ? since : since.replace(" ", "T")).getTime();
  if (Number.isNaN(started)) return null;

  return Math.max(0, now - started);
}
