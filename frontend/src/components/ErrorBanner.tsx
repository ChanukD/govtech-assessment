import type { ApiError } from "@/api/client";

interface ErrorBannerProps {
  error: ApiError;
  onRetry?: (() => void) | undefined;
}

export function ErrorBanner({ error, onRetry }: ErrorBannerProps) {
  return (
    <div className="banner banner--error" role="alert">
      <div className="banner__body">
        <strong>Something went wrong</strong>
        <p>{error.message}</p>
      </div>
      {onRetry && error.isRetryable && (
        <button type="button" className="button button--ghost" onClick={onRetry}>
          Retry
        </button>
      )}
    </div>
  );
}
