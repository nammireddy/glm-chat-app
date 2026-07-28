"""
vLLM Proxy — FastAPI validation layer in front of the vLLM inference server.

Listens on port 8080, validates incoming /v1/chat/completions requests, and
forwards valid requests to the upstream vLLM server running on localhost:8000.
"""

from __future__ import annotations

import os
from typing import Any, List, Optional

import httpx
from fastapi import FastAPI, Request, Response
from fastapi.responses import JSONResponse, StreamingResponse
from pydantic import BaseModel, field_validator

from timeout_middleware import TimeoutMiddleware

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

VLLM_UPSTREAM = os.getenv("VLLM_UPSTREAM", "http://localhost:8000")

# ---------------------------------------------------------------------------
# Request validation model
# ---------------------------------------------------------------------------

# The set of allowed top-level fields in the request body.
ALLOWED_FIELDS = {"model", "messages", "stream", "temperature", "top_p", "max_tokens", "system_prompt"}


class ChatCompletionRequest(BaseModel):
    """Pydantic model for validated chat completion requests."""

    model: str
    messages: List[dict]
    stream: Optional[bool] = False
    temperature: Optional[float] = None
    top_p: Optional[float] = None
    max_tokens: Optional[int] = None
    system_prompt: Optional[str] = None

    @field_validator("temperature")
    @classmethod
    def validate_temperature(cls, v: Optional[float]) -> Optional[float]:
        if v is not None and (v < 0.0 or v > 2.0):
            raise ValueError("temperature must be between 0.0 and 2.0")
        return v

    @field_validator("top_p")
    @classmethod
    def validate_top_p(cls, v: Optional[float]) -> Optional[float]:
        if v is not None and (v < 0.0 or v > 1.0):
            raise ValueError("top_p must be between 0.0 and 1.0")
        return v

    @field_validator("max_tokens")
    @classmethod
    def validate_max_tokens(cls, v: Optional[int]) -> Optional[int]:
        if v is not None and (v < 1 or v > 8192):
            raise ValueError("max_tokens must be between 1 and 8192")
        return v


# ---------------------------------------------------------------------------
# FastAPI application
# ---------------------------------------------------------------------------

app = FastAPI(title="vLLM Proxy", version="1.0.0")

# Add timeout middleware (60-second request timeout → HTTP 504)
app.add_middleware(TimeoutMiddleware, timeout_seconds=60)


@app.get("/health")
async def health() -> dict:
    """Liveness probe."""
    return {"status": "ok"}


@app.get("/ready")
async def ready() -> Response:
    """Readiness probe — checks upstream vLLM is reachable."""
    try:
        async with httpx.AsyncClient() as client:
            resp = await client.get(f"{VLLM_UPSTREAM}/health", timeout=5.0)
            if resp.status_code == 200:
                return JSONResponse({"status": "ready"}, status_code=200)
            return JSONResponse(
                {"status": "not ready", "upstream_status": resp.status_code},
                status_code=503,
            )
    except httpx.RequestError:
        return JSONResponse({"status": "not ready", "detail": "upstream unreachable"}, status_code=503)


@app.post("/v1/chat/completions")
async def chat_completions(request: Request) -> Response:
    """
    Validate the incoming request and forward to the upstream vLLM server.

    Returns HTTP 400 if:
    - Any unrecognised top-level parameter is present
    - temperature, top_p, or max_tokens are outside valid ranges
    """
    # Parse raw JSON body
    try:
        body: dict[str, Any] = await request.json()
    except Exception:
        return JSONResponse({"error": "Invalid JSON body"}, status_code=400)

    # Check for unrecognised top-level parameters
    for key in body:
        if key not in ALLOWED_FIELDS:
            return JSONResponse(
                {"error": f"Unrecognised parameter: {key}"},
                status_code=400,
            )

    # Validate known parameters with Pydantic
    try:
        validated = ChatCompletionRequest(**body)
    except Exception as e:
        # Extract a human-readable message from the validation error
        error_msg = str(e)
        # Pydantic v2 ValidationError provides a nice message
        if hasattr(e, "errors"):
            errors = e.errors()  # type: ignore[attr-defined]
            if errors:
                error_msg = errors[0].get("msg", str(e))
        return JSONResponse({"error": error_msg}, status_code=400)

    # Build the payload to forward (only include fields that were provided)
    forward_payload = body.copy()

    # Forward to upstream vLLM
    is_stream = validated.stream

    try:
        async with httpx.AsyncClient() as client:
            if is_stream:
                # Stream the response back to the caller
                upstream_request = client.build_request(
                    "POST",
                    f"{VLLM_UPSTREAM}/v1/chat/completions",
                    json=forward_payload,
                    headers={"Content-Type": "application/json"},
                )
                upstream_response = await client.send(upstream_request, stream=True)

                async def stream_generator():
                    try:
                        async for chunk in upstream_response.aiter_bytes():
                            yield chunk
                    finally:
                        await upstream_response.aclose()

                return StreamingResponse(
                    stream_generator(),
                    status_code=upstream_response.status_code,
                    media_type="text/event-stream",
                    headers={
                        "Cache-Control": "no-cache",
                        "Connection": "keep-alive",
                    },
                )
            else:
                # Non-streaming: forward and return the full response
                resp = await client.post(
                    f"{VLLM_UPSTREAM}/v1/chat/completions",
                    json=forward_payload,
                    headers={"Content-Type": "application/json"},
                    timeout=60.0,
                )
                return Response(
                    content=resp.content,
                    status_code=resp.status_code,
                    media_type=resp.headers.get("content-type", "application/json"),
                )
    except httpx.TimeoutException:
        return JSONResponse({"error": "Upstream request timed out"}, status_code=504)
    except httpx.RequestError as e:
        return JSONResponse(
            {"error": f"Upstream connection error: {str(e)}"},
            status_code=502,
        )


# ---------------------------------------------------------------------------
# Entrypoint
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8080)
