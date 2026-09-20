/**
 * A ticking elapsed time, for a run that is still in flight.
 *
 * Without this the duration sits at "—" for the whole run and then jumps to a final
 * number, which reads as nothing happening. The ticker stops as soon as `active`
 * goes false, so a finished run costs no timers.
 */

import { useEffect, useState } from "react";

const TICK_MS = 500;

export function useElapsed(since: string | null, active: boolean): number | null {
  const [now, setNow] = useState(() => Date.now());

  useEffect(() => {
    if (!active) return;

    // Re-read immediately so switching to an in-flight run does not show a stale
    // value until the first tick lands.
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
