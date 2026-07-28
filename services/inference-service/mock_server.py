"""
Mock Inference Service — returns canned SSE responses for local development.

This replaces the real vLLM inference service which requires a GPU.
Simulates the OpenAI-compatible /v1/chat/completions streaming endpoint.

Usage:
    uvicorn mock_server:app --host 0.0.0.0 --port 8000
"""

import asyncio
import json
import time
import uuid

from fastapi import FastAPI, Request
from fastapi.responses import StreamingResponse, JSONResponse

app = FastAPI(title="GLM Inference Mock", version="0.1.0")

# Canned responses for local testing
CANNED_RESPONSES = [
    "Based on the provided context, I can help you with that question. The GLM-4 model is designed to handle a variety of natural language tasks including summarization, question answering, and general conversation.",
    "According to the documents in my knowledge base, this topic relates to machine learning deployment patterns. The key considerations are resource allocation, scaling strategies, and monitoring.",
    "I'd be happy to explain that concept. In the context of large language models, inference refers to the process of generating predictions or outputs from a trained model given new input data.",
]

_response_index = 0


def get_next_response() -> str:
    """Cycle through canned responses."""
    global _response_index
    response = CANNED_RESPONSES[_response_index % len(CANNED_RESPONSES)]
    _response_index += 1
    return response


async def generate_sse_stream(response_text: str, model: str):
    """Simulate streaming token-by-token SSE output like vLLM."""
    completion_id = f"chatcmpl-{uuid.uuid4().hex[:12]}"
    words = response_text.split()
    prompt_tokens = 120  # simulated
    completion_tokens = 0

    for i, word in enumerate(words):
        token = word + (" " if i < len(words) - 1 else "")
        completion_tokens += 1

        chunk = {
            "id": completion_id,
            "object": "chat.completion.chunk",
            "created": int(time.time()),
            "model": model,
            "choices": [
                {
                    "index": 0,
                    "delta": {"content": token},
                    "finish_reason": None,
                }
            ],
            "usage": None,
        }
        yield f"data: {json.dumps(chunk)}\n\n"
        # Simulate generation latency (~30 tokens/sec)
        await asyncio.sleep(0.03)

    # Final chunk with finish_reason and usage
    final_chunk = {
        "id": completion_id,
        "object": "chat.completion.chunk",
        "created": int(time.time()),
        "model": model,
        "choices": [
            {
                "index": 0,
                "delta": {},
                "finish_reason": "stop",
            }
        ],
        "usage": {
            "prompt_tokens": prompt_tokens,
            "completion_tokens": completion_tokens,
            "total_tokens": prompt_tokens + completion_tokens,
        },
    }
    yield f"data: {json.dumps(final_chunk)}\n\n"
    yield "data: [DONE]\n\n"


@app.post("/v1/chat/completions")
async def chat_completions(request: Request):
    """OpenAI-compatible chat completions endpoint (mock)."""
    body = await request.json()
    model = body.get("model", "glm-4-9b-chat")
    stream = body.get("stream", False)
    temperature = body.get("temperature", 0.7)
    max_tokens = body.get("max_tokens", 1024)

    # Validate parameters
    if temperature < 0.0 or temperature > 2.0:
        return JSONResponse(
            status_code=400,
            content={"error": {"message": f"temperature must be between 0.0 and 2.0, got {temperature}", "type": "invalid_request_error"}},
        )
    if max_tokens < 1 or max_tokens > 8192:
        return JSONResponse(
            status_code=400,
            content={"error": {"message": f"max_tokens must be between 1 and 8192, got {max_tokens}", "type": "invalid_request_error"}},
        )

    response_text = get_next_response()

    if stream:
        return StreamingResponse(
            generate_sse_stream(response_text, model),
            media_type="text/event-stream",
            headers={
                "Cache-Control": "no-cache",
                "Connection": "keep-alive",
                "X-Accel-Buffering": "no",
            },
        )

    # Non-streaming response
    completion_id = f"chatcmpl-{uuid.uuid4().hex[:12]}"
    return JSONResponse(
        content={
            "id": completion_id,
            "object": "chat.completion",
            "created": int(time.time()),
            "model": model,
            "choices": [
                {
                    "index": 0,
                    "message": {"role": "assistant", "content": response_text},
                    "finish_reason": "stop",
                }
            ],
            "usage": {
                "prompt_tokens": 120,
                "completion_tokens": len(response_text.split()),
                "total_tokens": 120 + len(response_text.split()),
            },
        }
    )


@app.get("/health")
async def health():
    """Health check endpoint."""
    return {"status": "ok", "model": "glm-4-9b-chat-mock"}


@app.get("/v1/models")
async def list_models():
    """List available models (mock)."""
    return {
        "object": "list",
        "data": [
            {
                "id": "glm-4-9b-chat",
                "object": "model",
                "owned_by": "mock",
            }
        ],
    }
