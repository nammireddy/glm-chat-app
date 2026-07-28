interface ErrorBannerProps {
  error: string | null;
  onRetry: () => void;
}

/**
 * Displays an error message with a visible "Retry" button when the last request failed.
 * Clicking "Retry" re-submits the last message.
 */
export default function ErrorBanner({ error, onRetry }: ErrorBannerProps) {
  if (!error) return null;

  return (
    <div
      role="alert"
      style={{
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'space-between',
        padding: '0.5rem 1rem',
        backgroundColor: 'var(--error-bg)',
        borderBottom: '1px solid var(--error-border)',
        color: 'var(--error-text)',
        fontSize: '0.85rem',
      }}
    >
      <span>{error}</span>
      <button
        onClick={onRetry}
        aria-label="Retry last message"
        style={{
          padding: '0.3rem 0.75rem',
          borderRadius: '0.3rem',
          border: '1px solid var(--error-border)',
          backgroundColor: 'transparent',
          color: 'var(--error-text)',
          cursor: 'pointer',
          fontWeight: 600,
          fontSize: '0.8rem',
        }}
      >
        Retry
      </button>
    </div>
  );
}
