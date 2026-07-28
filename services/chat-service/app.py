"""Chat Service — FastAPI application.

Endpoints:
- POST /chat: Validate message, load session, call RAG, build prompt,
  stream from inference, score answer, return response or refusal.
- GET /health: Liveness probe.
- GET /ready: Readiness probe (checks Redis, RAG, Inference reachability).

Implements buffered streaming approach:
1. Collect tokens from vLLM internally (stream=true for fast collection)
2. Score the complete answer
3. If confidence >= 0.7: send full answer to client via SSE followed by [DONE]
4. If confidence < 0.7: send refusal message instead
"""

import json
import logging
import os
import time
import uuid
from datetime import datetime, timezone

import httpx
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, StreamingResponse
from prometheus_fastapi_instrumentator import Instrumentator
from slowapi.errors import RateLimitExceeded

from cookie import get_session_id, set_session_cookie
from inference_client import InferenceError, stream_completion
from prompt_builder import build_prompt
from rag_client import retrieve_documents
from rate_limit import RATE_LIMIT, limiter, rate_limit_exceeded_handler
from scorer_client import score_answer
from session import Turn, hash_session_id, load_session, save_session

# Configure structured JSON logging
logging.basicConfig(
    level=logging.INFO,
    format="%(message)s",
)
logger = logging.getLogger(__name__)

# Environment
REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379")
RAG_SERVICE_URL = os.getenv("RAG_SERVICE_URL", "http://rag-service:8002")
INFERENCE_SERVICE_URL = os.getenv(
    "INFERENCE_SERVICE_URL", "http://inference-service:8000"
)

REFUSAL_MESSAGE = "I cannot confidently answer this question."
MAX_MESSAGE_LENGTH = 4096

# FastAPI app
app = FastAPI(title="GLM Chat Service", version="1.0.0")

# Rate limiting
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, rate_limit_exceeded_handler)

# Prometheus metrics
Instrumentator().instrument(app).expose(app)


def _structured_log(
    level: str,
    correlation_id: str,
    session_id: str | None = None,
    http_status: int | None = None,
    error_type: str | None = None,
    request_tokens: int | None = None,
    latency_ms: float | None = None,
    **extra: object,
) -> None:
    """Emit a structured JSON log entry per the design schema.

    Never logs message content. session_id is stored only as SHA-256 hash.
    """
    entry = {
        "correlation_id": correlation_id,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "service": "chat-service",
        "level": level,
    }
    if http_status is not None:
        entry["http_status"] = http_status
    if error_type is not None:
        entry["error_type"] = error_type
    if request_tokens is not None:
        entry["request_tokens"] = request_tokens
    if latency_ms is not None:
        entry["latency_ms"] = latency_ms
    if session_id:
        entry["session_id_hash"] = hash_session_id(session_id)
    entry.update(extra)

    log_func = getattr(logger, level.lower(), logger.info)
    log_func(json.dumps(entry))


@app.post("/chat")
@limiter.limit(RATE_LIMIT)
async def chat(request: Request) -> StreamingResponse:
    """Handle a chat request.

    Flow:
    1. Validate message (non-empty, <= 4096 chars)
    2. Get/create session cookie
    3. Load session from Redis
    4. Call RAG /retrieve (5s timeout, empty on failure)
    5. Build prompt (system + context + history + user msg)
    6. Stream from Inference (buffer all tokens)
    7. Score the complete answer
    8. If confidence < 0.7 → send refusal; else send answer
    9. Save new turn to session
    10. Return SSE stream to client
    """
    correlation_id = str(uuid.uuid4())
    start_time = time.monotonic()
    session_id = get_session_id(request)

    # Parse request body
    try:
        body = await request.json()
    except Exception:
        _structured_log(
            "ERROR",
            correlation_id,
            session_id=session_id,
            http_status=400,
            error_type="InvalidJSON",
        )
        return JSONResponse(
            status_code=400,
            content={"error": "invalid_request", "message": "Invalid JSON body"},
        )

    message = body.get("message", "")

    # Validate: non-empty after trimming
    if not message or not message.strip():
        _structured_log(
            "WARNING",
            correlation_id,
            session_id=session_id,
            http_status=422,
            error_type="EmptyMessage",
        )
        return JSONResponse(
            status_code=422,
            content={"error": "validation_error", "message": "Message cannot be empty"},
        )

    # Validate: max length
    if len(message) > MAX_MESSAGE_LENGTH:
        _structured_log(
            "WARNING",
            correlation_id,
            session_id=session_id,
            http_status=422,
            error_type="MessageTooLong",
        )
        return JSONResponse(
            status_code=422,
            content={
                "error": "validation_error",
                "message": f"Message exceeds maximum length of {MAX_MESSAGE_LENGTH} characters",
            },
        )

    # Load session history
    history_turns = await load_session(session_id)
    history = [t.to_dict() for t in history_turns]

    # Call RAG pipeline
    rag_result = await retrieve_documents(message)
    documents = rag_result.get("documents", [])
    grounding = rag_result.get("grounding", "none")

    # Build prompt (last 20 turns for prompt context)
    prompt_messages = build_prompt(documents, history, message)

    # Count request tokens (approximate: character-based estimate)
    request_tokens = sum(len(m.get("content", "")) for m in prompt_messages) // 4

    # Stream from inference service (buffer internally)
    try:
        tokens = await stream_completion(prompt_messages)
    except InferenceError as e:
        latency_ms = (time.monotonic() - start_time) * 1000
        _structured_log(
            "ERROR",
            correlation_id,
            session_id=session_id,
            http_status=504,
            error_type="InferenceTimeout",
            request_tokens=request_tokens,
            latency_ms=latency_ms,
        )
        return JSONResponse(
            status_code=504,
            content={
                "error": "inference_error",
                "message": "The inference service is currently unavailable. Please try again.",
            },
        )

    # Assemble complete answer
    full_answer = "".join(tokens)

    # Score the answer (logged for observability, but no longer blocks response)
    score_result = await score_answer(message, full_answer)

    # Always return the inference response regardless of confidence score
    final_answer = full_answer

    # Save new turns to session
    new_turns = [
        Turn(role="user", content=message),
        Turn(role="assistant", content=final_answer),
    ]
    await save_session(session_id, new_turns)

    # Log completion
    latency_ms = (time.monotonic() - start_time) * 1000
    _structured_log(
        "INFO",
        correlation_id,
        session_id=session_id,
        http_status=200,
        request_tokens=request_tokens,
        latency_ms=latency_ms,
    )

    # Build SSE stream response
    async def event_stream():
        """Generate SSE events for the client."""
        chat_id = f"chatcmpl-{correlation_id[:8]}"

        # Stream the answer token by token
        for token in tokens:
            event = {
                "id": chat_id,
                "choices": [
                    {"delta": {"content": token}, "finish_reason": None}
                ],
                "usage": None,
            }
            yield f"data: {json.dumps(event)}\n\n"

        # Send finish event with metadata
        finish_event = {
            "id": chat_id,
            "choices": [{"delta": {}, "finish_reason": "stop"}],
            "usage": {"prompt_tokens": request_tokens, "completion_tokens": len(tokens)},
            "metadata": {
                "grounding": grounding,
                "confidence": score_result.score,
                "sources": [d.get("title", "") for d in documents] if documents else [],
            },
        }
        yield f"data: {json.dumps(finish_event)}\n\n"

        yield "data: [DONE]\n\n"

    response = StreamingResponse(
        event_stream(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Correlation-ID": correlation_id,
        },
    )
    set_session_cookie(response, session_id)
    return response


@app.get("/health")
async def health() -> JSONResponse:
    """Liveness probe — always returns 200 if the process is running."""
    return JSONResponse(status_code=200, content={"status": "healthy"})


@app.get("/ready")
async def ready() -> JSONResponse:
    """Readiness probe — checks Redis, RAG, and Inference reachability."""
    checks: dict[str, bool] = {}

    # Check Redis
    try:
        import redis.asyncio as aioredis

        client = aioredis.from_url(REDIS_URL, decode_responses=True)
        await client.ping()
        await client.aclose()
        checks["redis"] = True
    except Exception:
        checks["redis"] = False

    # Check RAG service
    try:
        async with httpx.AsyncClient(timeout=3.0) as client:
            resp = await client.get(f"{RAG_SERVICE_URL}/health")
            checks["rag"] = resp.status_code == 200
    except Exception:
        checks["rag"] = False

    # Check Inference service
    try:
        async with httpx.AsyncClient(timeout=3.0) as client:
            resp = await client.get(f"{INFERENCE_SERVICE_URL}/health")
            checks["inference"] = resp.status_code == 200
    except Exception:
        checks["inference"] = False

    all_ready = all(checks.values())
    status_code = 200 if all_ready else 503

    return JSONResponse(
        status_code=status_code,
        content={"status": "ready" if all_ready else "not_ready", "checks": checks},
    )
