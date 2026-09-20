import { afterEach, describe, expect, it, vi } from "vitest";

import { ApiError, getRun, listRecords, triggerRun } from "@/api/client";

function mockFetch(response: Partial<Response> & { json?: () => Promise<unknown> }) {
  const fetchMock = vi.fn().mockResolvedValue({
    ok: true,
    status: 200,
    json: () => Promise.resolve({}),
    ...response,
  });
  vi.stubGlobal("fetch", fetchMock);
  return fetchMock;
}

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("triggerRun", () => {
  it("POSTs JSON to the runs endpoint", async () => {
    const fetchMock = mockFetch({ json: () => Promise.resolve({ run_id: "abc", status: "QUEUED" }) });

    await triggerRun();

    expect(fetchMock).toHaveBeenCalledWith(
      "/api/v1/runs",
      expect.objectContaining({
        method: "POST",
        headers: { "Content-Type": "application/json" },
      }),
    );
  });

  it("uses a relative path so the request is same-origin", async () => {
    const fetchMock = mockFetch({});
    await triggerRun();
    const [url] = fetchMock.mock.calls[0] as [string];
    expect(url.startsWith("/")).toBe(true);
  });
});

describe("error handling", () => {
  it("surfaces FastAPI's detail message", async () => {
    mockFetch({
      ok: false,
      status: 404,
      json: () => Promise.resolve({ detail: "run nope not found" }),
    });

    await expect(getRun("nope")).rejects.toThrow("run nope not found");
  });

  it("flattens 422 validation detail arrays", async () => {
    mockFetch({
      ok: false,
      status: 422,
      json: () => Promise.resolve({ detail: [{ loc: ["query", "limit"], msg: "too small" }] }),
    });

    await expect(listRecords("abc")).rejects.toThrow(/too small/);
  });

  it("reports a network failure as status 0", async () => {
    vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new TypeError("Failed to fetch")));

    const error = await getRun("abc").catch((cause: unknown) => cause);

    expect(error).toBeInstanceOf(ApiError);
    expect((error as ApiError).status).toBe(0);
    expect((error as ApiError).isRetryable).toBe(true);
  });

  it("does not offer a retry for client errors", async () => {
    mockFetch({ ok: false, status: 404, json: () => Promise.resolve({ detail: "gone" }) });

    const error = (await getRun("abc").catch((cause: unknown) => cause)) as ApiError;

    expect(error.isRetryable).toBe(false);
  });

  it("lets aborts propagate rather than reporting them as failures", async () => {
    const abortError = new DOMException("aborted", "AbortError");
    vi.stubGlobal("fetch", vi.fn().mockRejectedValue(abortError));

    await expect(getRun("abc")).rejects.toBe(abortError);
  });
});

describe("listRecords", () => {
  it("passes pagination through as query parameters", async () => {
    const fetchMock = mockFetch({ json: () => Promise.resolve({ records: [] }) });

    await listRecords("run-1", { limit: 10, offset: 20 });

    const [url] = fetchMock.mock.calls[0] as [string];
    expect(url).toBe("/api/v1/runs/run-1/records?limit=10&offset=20");
  });

  it("encodes ids so a hostile id cannot escape the path", async () => {
    const fetchMock = mockFetch({ json: () => Promise.resolve({ records: [] }) });

    await listRecords("a/../b");

    const [url] = fetchMock.mock.calls[0] as [string];
    expect(url).toContain("a%2F..%2Fb");
  });
});
