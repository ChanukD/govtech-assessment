import { describe, expect, it } from "vitest";

import {
  formatBounds,
  formatDiameter,
  formatDuration,
  formatElapsed,
  formatExtent,
  formatMetres,
  formatRelative,
  formatTimestamp,
  shortId,
} from "@/lib/format";

describe("formatMetres", () => {
  it("rounds and appends a unit", () => {
    expect(formatMetres(1397.856)).toBe("1,398 m");
  });
});

describe("formatDiameter", () => {
  it("renders a dash for a missing value rather than 'null'", () => {
    expect(formatDiameter(null)).toBe("—");
  });
});

describe("formatTimestamp", () => {
  it("parses the source file's space-separated format", () => {
    expect(formatTimestamp("2026-08-12 17:35:06.403504")).not.toBe(
      "2026-08-12 17:35:06.403504",
    );
  });

  it("returns the original string when it is not a date", () => {
    expect(formatTimestamp("not-a-date")).toBe("not-a-date");
  });

  it("renders a dash for null", () => {
    expect(formatTimestamp(null)).toBe("—");
  });
});

describe("formatDuration", () => {
  it("uses milliseconds below a second", () => {
    expect(
      formatDuration("2026-01-01T00:00:00.000Z", "2026-01-01T00:00:00.400Z"),
    ).toBe("400 ms");
  });

  it("uses seconds below a minute", () => {
    expect(formatDuration("2026-01-01T00:00:00Z", "2026-01-01T00:00:02Z")).toBe("2.0 s");
  });

  it("uses minutes and seconds above a minute", () => {
    expect(formatDuration("2026-01-01T00:00:00Z", "2026-01-01T00:01:30Z")).toBe("1m 30s");
  });

  it("renders a dash when a run has not finished", () => {
    expect(formatDuration("2026-01-01T00:00:00Z", null)).toBe("—");
  });
});

describe("shortId", () => {
  it("truncates a uuid to its first block", () => {
    expect(shortId("bfa6839f-2fc5-4511-a69d-593cd1f306fc")).toBe("bfa6839f");
  });
});

describe("formatRelative", () => {
  const now = new Date("2026-01-01T12:00:00Z").getTime();

  it("says 'just now' within ten seconds", () => {
    expect(formatRelative("2026-01-01T11:59:55Z", now)).toBe("just now");
  });

  it("counts seconds under a minute", () => {
    expect(formatRelative("2026-01-01T11:59:30Z", now)).toBe("30s ago");
  });

  it("counts minutes under an hour", () => {
    expect(formatRelative("2026-01-01T11:45:00Z", now)).toBe("15m ago");
  });

  it("counts hours under a day", () => {
    expect(formatRelative("2026-01-01T09:00:00Z", now)).toBe("3h ago");
  });

  it("falls back to an absolute date past a day", () => {
    expect(formatRelative("2025-12-25T09:00:00Z", now)).toMatch(/2025/);
  });

  it("does not produce a negative age for clock skew", () => {
    expect(formatRelative("2026-01-01T12:00:30Z", now)).toBe("just now");
  });
});

describe("formatElapsed", () => {
  it("shows tenths of a second under a minute", () => {
    expect(formatElapsed(2400)).toBe("2.4s");
  });

  it("switches to minutes and seconds above a minute", () => {
    expect(formatElapsed(95_000)).toBe("1m 35s");
  });
});

describe("formatExtent", () => {
  it("reports width by height rather than raw corners", () => {
    expect(
      formatExtent({ min_x: 32450, min_y: 21780, max_x: 33720, max_y: 22910 }),
    ).toBe("1,270 × 1,130 m");
  });
});

describe("formatBounds", () => {
  it("labels the axes so the numbers are interpretable", () => {
    expect(
      formatBounds({ min_x: 32450, min_y: 21780, max_x: 33720, max_y: 22910 }),
    ).toBe("32,450–33,720 E, 21,780–22,910 N");
  });
});
