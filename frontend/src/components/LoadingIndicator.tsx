/**
 * Animated spinner shown while a response is in progress.
 */
export default function LoadingIndicator() {
  return (
    <div
      className="loading-indicator"
      role="status"
      aria-label="Loading response"
      style={{
        display: 'flex',
        alignItems: 'center',
        gap: '0.5rem',
        padding: '0.5rem 1rem',
        color: 'var(--text-secondary)',
        fontSize: '0.85rem',
      }}
    >
      <div
        style={{
          width: '16px',
          height: '16px',
          border: '2px solid var(--border-color)',
          borderTop: '2px solid var(--bg-user-bubble)',
          borderRadius: '50%',
          animation: 'spin 0.8s linear infinite',
        }}
      />
      <span>Generating response…</span>
      <style>{`
        @keyframes spin {
          from { transform: rotate(0deg); }
          to { transform: rotate(360deg); }
        }
      `}</style>
    </div>
  );
}
