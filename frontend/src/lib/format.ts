/** Presentation helpers. Pure functions, so they are trivially testable. */

const NUMBER_FORMAT = new Intl.NumberFormat();

export function formatNumber(value: number): string {
  return NUMBER_FORMAT.format(value);
}

export function formatMetres(value: number): string {
  return `${NUMBER_FORMAT.format(Math.round(value))} m`;
}

export function formatDiameter(value: number | null): string {
  return value === null ? "—" : NUMBER_FORMAT.format(value);
}

/**
 * The backend emits ISO-8601 for run fields, and the source file's own
 * "YYYY-MM-DD HH:MM:SS.ffffff" for event timestamps. Accept both, and return the
 * raw string rather than "Invalid Date" if it is neither.
 */
export function formatTimestamp(value: string | null): string {
  if (value === null) return "—";

  const parsed = new Date(value.includes("T") ? value : value.replace(" ", "T"));
  if (Number.isNaN(parsed.getTime())) return value;

  return parsed.toLocaleString(undefined, {
    dateStyle: "medium",
    timeStyle: "medium",
  });
}

/** Elapsed time between two timestamps, for showing how long a run took. */
export function formatDuration(start: string | null, end: string | null): string {
  if (start === null || end === null) return "—";

  const from = new Date(start).getTime();
  const to = new Date(end).getTime();
  if (Number.isNaN(from) || Number.isNaN(to)) return "—";

  const seconds = (to - from) / 1000;
  if (seconds < 1) return `${Math.round(seconds * 1000)} ms`;
  if (seconds < 60) return `${seconds.toFixed(1)} s`;
  return `${Math.floor(seconds / 60)}m ${Math.round(seconds % 60)}s`;
}

/** Run ids are UUIDs - too long to show in full in a list. */
export function shortId(runId: string): string {
  return runId.slice(0, 8);
}

/**
 * "just now" / "4m ago", falling back to an absolute date past a day.
 *
 * `now` is a parameter rather than read inside so the function stays pure and the
 * tests do not have to freeze the clock.
 */
export function formatRelative(value: string | null, now: number = Date.now()): string {
  if (value === null) return "—";

  const then = new Date(value.includes("T") ? value : value.replace(" ", "T")).getTime();
  if (Number.isNaN(then)) return value;

  const seconds = Math.round((now - then) / 1000);
  if (seconds < 0) return "just now";
  if (seconds < 10) return "just now";
  if (seconds < 60) return `${seconds}s ago`;

  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m ago`;

  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;

  return formatTimestamp(value);
}

/** A live duration in milliseconds, for a run that is still going. */
export function formatElapsed(milliseconds: number): string {
  const seconds = milliseconds / 1000;
  if (seconds < 60) return `${seconds.toFixed(1)}s`;
  return `${Math.floor(seconds / 60)}m ${Math.round(seconds % 60)}s`;
}

/**
 * The bounding box as its extent rather than four raw coordinates.
 *
 * How wide and tall the feature is answers a question; the corner coordinates on
 * their own mostly do not, and take four columns to show.
 */
export function formatExtent(bbox: {
  min_x: number;
  min_y: number;
  max_x: number;
  max_y: number;
}): string {
  const width = Math.round(bbox.max_x - bbox.min_x);
  const height = Math.round(bbox.max_y - bbox.min_y);
  return `${NUMBER_FORMAT.format(width)} × ${NUMBER_FORMAT.format(height)} m`;
}

/** The full corner coordinates, for a tooltip where the detail is wanted. */
export function formatBounds(bbox: {
  min_x: number;
  min_y: number;
  max_x: number;
  max_y: number;
}): string {
  const x = `${NUMBER_FORMAT.format(bbox.min_x)}–${NUMBER_FORMAT.format(bbox.max_x)} E`;
  const y = `${NUMBER_FORMAT.format(bbox.min_y)}–${NUMBER_FORMAT.format(bbox.max_y)} N`;
  return `${x}, ${y}`;
}
