import { useState, useCallback, useRef } from 'react';
import ChatWindow, { Message, capMessages } from './components/ChatWindow';
import InputBar from './components/InputBar';
import ErrorBanner from './components/ErrorBanner';
import LoadingIndicator from './components/LoadingIndicator';
import { streamChat } from './lib/sseClient';

/**
 * Main application component.
 * Wires ChatWindow, InputBar, ErrorBanner, LoadingIndicator, and sseClient together.
 * Manages messages, loading, and error state.
 */
export default function App() {
  const [messages, setMessages] = useState<Message[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [restoredText, setRestoredText] = useState<string | undefined>(undefined);
  const lastMessageRef = useRef<string>('');
  const abortRef = useRef<AbortController | null>(null);

  const sendMessage = useCallback((text: string) => {
    // Clear error state
    setError(null);
    setRestoredText(undefined);
    setLoading(true);
    lastMessageRef.current = text;

    // Append user message
    setMessages((prev) => capMessages([...prev, { role: 'user', content: text }]));

    // Append empty assistant message placeholder
    setMessages((prev) =>
      capMessages([...prev, { role: 'assistant', content: '' }])
    );

    const controller = streamChat(
      text,
      // onToken: append delta to last assistant message
      (delta) => {
        setMessages((prev) => {
          const updated = [...prev];
          const last = updated[updated.length - 1];
          if (last && last.role === 'assistant') {
            updated[updated.length - 1] = {
              ...last,
              content: last.content + delta,
            };
          }
          return updated;
        });
      },
      // onDone: clear loading
      () => {
        setLoading(false);
        abortRef.current = null;
      },
      // onError: set error state, restore input text, remove empty assistant message
      (err) => {
        setLoading(false);
        setError(err.message || 'An error occurred');
        setRestoredText(lastMessageRef.current);
        // Remove the empty assistant placeholder if no content was received
        setMessages((prev) => {
          const last = prev[prev.length - 1];
          if (last && last.role === 'assistant' && last.content === '') {
            return prev.slice(0, -1);
          }
          return prev;
        });
        abortRef.current = null;
      }
    );

    abortRef.current = controller;
  }, []);

  const handleRetry = useCallback(() => {
    if (lastMessageRef.current) {
      sendMessage(lastMessageRef.current);
    }
  }, [sendMessage]);

  return (
    <div
      style={{
        display: 'flex',
        flexDirection: 'column',
        height: '100vh',
        maxWidth: '800px',
        margin: '0 auto',
        backgroundColor: 'var(--bg-primary)',
        boxShadow: '0 0 20px rgba(0,0,0,0.1)',
      }}
    >
      <header
        style={{
          padding: '0.75rem 1rem',
          borderBottom: '1px solid var(--border-color)',
          fontWeight: 600,
          fontSize: '1.1rem',
          backgroundColor: 'var(--bg-primary)',
        }}
      >
        GLM Chat
      </header>

      <ErrorBanner error={error} onRetry={handleRetry} />

      <ChatWindow messages={messages} />

      {loading && <LoadingIndicator />}

      <InputBar
        onSubmit={sendMessage}
        loading={loading}
        restoredText={restoredText}
      />
    </div>
  );
}
