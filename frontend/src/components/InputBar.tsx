import { useState, useRef, useEffect, FormEvent, ChangeEvent, KeyboardEvent } from 'react';

interface InputBarProps {
  onSubmit: (message: string) => void;
  loading: boolean;
  restoredText?: string;
}

const MAX_LENGTH = 4096;

/**
 * Textarea input with:
 * - maxLength of 4096 characters
 * - Live character count (N / 4096)
 * - Disabled while loading
 * - Prevents empty/whitespace-only submission with inline validation
 * - Restores user's submitted text on error
 */
export default function InputBar({ onSubmit, loading, restoredText }: InputBarProps) {
  const [text, setText] = useState('');
  const [validationError, setValidationError] = useState('');
  const textareaRef = useRef<HTMLTextAreaElement>(null);

  // Restore text on error
  useEffect(() => {
    if (restoredText !== undefined && restoredText !== '') {
      setText(restoredText);
    }
  }, [restoredText]);

  // Focus textarea when not loading
  useEffect(() => {
    if (!loading) {
      textareaRef.current?.focus();
    }
  }, [loading]);

  const handleSubmit = (e: FormEvent) => {
    e.preventDefault();
    const trimmed = text.trim();
    if (!trimmed) {
      setValidationError('Message cannot be empty');
      return;
    }
    setValidationError('');
    onSubmit(trimmed);
    setText('');
  };

  const handleChange = (e: ChangeEvent<HTMLTextAreaElement>) => {
    setText(e.target.value);
    if (validationError && e.target.value.trim()) {
      setValidationError('');
    }
  };

  const handleKeyDown = (e: KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      handleSubmit(e as unknown as FormEvent);
    }
  };

  return (
    <form
      onSubmit={handleSubmit}
      style={{
        display: 'flex',
        flexDirection: 'column',
        gap: '0.25rem',
        padding: '0.75rem 1rem',
        borderTop: '1px solid var(--border-color)',
        backgroundColor: 'var(--bg-primary)',
      }}
    >
      <div style={{ display: 'flex', gap: '0.5rem', alignItems: 'flex-end' }}>
        <textarea
          ref={textareaRef}
          value={text}
          onChange={handleChange}
          onKeyDown={handleKeyDown}
          maxLength={MAX_LENGTH}
          disabled={loading}
          placeholder="Type your message..."
          aria-label="Message input"
          aria-invalid={!!validationError}
          aria-describedby={validationError ? 'input-error' : undefined}
          rows={2}
          style={{
            flex: 1,
            resize: 'none',
            padding: '0.5rem 0.75rem',
            borderRadius: '0.5rem',
            border: `1px solid ${validationError ? 'var(--error-text)' : 'var(--border-color)'}`,
            backgroundColor: 'var(--bg-secondary)',
            color: 'var(--text-primary)',
            fontFamily: 'inherit',
            fontSize: '0.9rem',
            lineHeight: 1.4,
            outline: 'none',
          }}
        />
        <button
          type="submit"
          disabled={loading}
          aria-label="Send message"
          style={{
            padding: '0.5rem 1.25rem',
            borderRadius: '0.5rem',
            border: 'none',
            backgroundColor: loading ? 'var(--border-color)' : 'var(--bg-user-bubble)',
            color: 'var(--text-user-bubble)',
            cursor: loading ? 'not-allowed' : 'pointer',
            fontWeight: 600,
            fontSize: '0.9rem',
          }}
        >
          Send
        </button>
      </div>
      <div
        style={{
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center',
          fontSize: '0.75rem',
          color: 'var(--text-secondary)',
          minHeight: '1.25rem',
        }}
      >
        {validationError ? (
          <span id="input-error" role="alert" style={{ color: 'var(--error-text)' }}>
            {validationError}
          </span>
        ) : (
          <span />
        )}
        <span aria-live="polite">
          {text.length} / {MAX_LENGTH}
        </span>
      </div>
    </form>
  );
}
