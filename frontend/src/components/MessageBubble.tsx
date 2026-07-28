import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import DOMPurify from 'dompurify';

interface MessageBubbleProps {
  role: 'user' | 'assistant';
  content: string;
}

/**
 * Renders a single message bubble.
 * Uses react-markdown with remark-gfm for bold, italic, code blocks, lists.
 * Sanitises HTML via DOMPurify.
 */
export default function MessageBubble({ role, content }: MessageBubbleProps) {
  const sanitisedContent = DOMPurify.sanitize(content);

  const isUser = role === 'user';

  return (
    <div
      className={`message-bubble message-bubble--${role}`}
      style={{
        alignSelf: isUser ? 'flex-end' : 'flex-start',
        maxWidth: '75%',
        padding: '0.75rem 1rem',
        borderRadius: '1rem',
        backgroundColor: isUser
          ? 'var(--bg-user-bubble)'
          : 'var(--bg-assistant-bubble)',
        color: isUser
          ? 'var(--text-user-bubble)'
          : 'var(--text-assistant-bubble)',
        wordBreak: 'break-word',
        lineHeight: 1.5,
      }}
      role="article"
      aria-label={`${role} message`}
    >
      <ReactMarkdown
        remarkPlugins={[remarkGfm]}
        components={{
          // Render code blocks with pre/code styling
          code({ className, children, ...props }) {
            const isBlock = className?.includes('language-');
            if (isBlock) {
              return (
                <pre
                  style={{
                    backgroundColor: 'rgba(0,0,0,0.1)',
                    padding: '0.5rem',
                    borderRadius: '0.25rem',
                    overflowX: 'auto',
                    margin: '0.5rem 0',
                  }}
                >
                  <code className={className} {...props}>
                    {children}
                  </code>
                </pre>
              );
            }
            return (
              <code
                style={{
                  backgroundColor: 'rgba(0,0,0,0.1)',
                  padding: '0.1rem 0.3rem',
                  borderRadius: '0.2rem',
                }}
                {...props}
              >
                {children}
              </code>
            );
          },
        }}
      >
        {sanitisedContent}
      </ReactMarkdown>
    </div>
  );
}
