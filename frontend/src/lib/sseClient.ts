import { EventSourceParserStream } from 'eventsource-parser/stream';

/**
 * Opens a fetch SSE request to POST /chat, parses data: events,
 * and calls callbacks for each token, completion, or error.
 *
 * @param message - The user message to send
 * @param onToken - Called with each content delta token
 * @param onDone - Called when the stream completes ([DONE])
 * @param onError - Called on network error or 4xx/5xx response
 * @returns AbortController to allow cancellation
 */
export function streamChat(
  message: string,
  onToken: (delta: string) => void,
  onDone: () => void,
  onError: (err: Error) => void
): AbortController {
  const controller = new AbortController();

  (async () => {
    try {
      const response = await fetch('/chat', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Accept: 'text/event-stream',
        },
        body: JSON.stringify({ message }),
        signal: controller.signal,
        credentials: 'include', // session cookie
      });

      if (!response.ok) {
        const errorText = await response.text().catch(() => 'Unknown error');
        onError(new Error(`HTTP ${response.status}: ${errorText}`));
        return;
      }

      if (!response.body) {
        onError(new Error('Response body is null'));
        return;
      }

      const stream = response.body
        .pipeThrough(new TextDecoderStream())
        .pipeThrough(new EventSourceParserStream());

      const reader = stream.getReader();

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;

        const event = value;
        const data = event.data;

        if (data === '[DONE]') {
          onDone();
          return;
        }

        try {
          const parsed = JSON.parse(data);
          const delta = parsed?.choices?.[0]?.delta?.content;
          if (delta) {
            onToken(delta);
          }
        } catch {
          // Skip malformed JSON events
        }
      }

      // Stream ended without [DONE]
      onDone();
    } catch (err) {
      if ((err as Error).name === 'AbortError') return;
      onError(err instanceof Error ? err : new Error(String(err)));
    }
  })();

  return controller;
}
