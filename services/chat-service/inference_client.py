"""Async HTTP client for the Inference Service (vLLM).

Calls POST /v1/chat/completions with stream=true.
Implements 3-retry exponential backoff (1s, 2s, 4s) on 5xx errors
(excluding 501, 505). Total retry budget ≤ 10s.
Raises after exhaustion.
"""

import asyncio
import logging
import os
import time
from typing import Any

import httpx

logger = logging.getLogger(__name__)

INFERENCE_SERVICE_URL = os.getenv(
    "INFERENCE_SERVICE_URL", "http://inference-service:8000"
)
INFERENCE_TIMEOUT = 60.0  # seconds per request
MAX_RETRIES = 3
BACKOFF_DELAYS = [1.0, 2.0, 4.0]  # exponential backoff
TOTAL_RETRY_BUDGET = 10.0  # seconds
NON_RETRYABLE_5XX = {501, 505}


class InferenceError(Exception):
    """Raised when inference service is unreachable after retries."""

    def __init__(self, status_code: int | None = None, message: str = ""):
        self.status_code = status_code
        self.message = message
        super().__init__(f"Inference failed: status={status_code}, {message}")


async def stream_completion(
    messages: list[dict[str, Any]],
    model_config: dict[str, Any] | None = None,
) -> list[str]:
    """Stream chat completion from vLLM and return collected tokens.

    Sends the request with stream=true, collects all tokens from the SSE stream,
    and returns them as a list of content strings.

    Args:
        messages: The assembled prompt messages list.
        model_config: Optional model configuration from the router.
            Keys: name (model name), url (service URL), max_tokens.

    Returns:
        List of token strings from the streamed response.

    Raises:
        InferenceError: After all retries are exhausted or on non-retryable errors.
    """
    if model_config:
        model_name = model_config["name"]
        service_url = model_config["url"]
        max_tokens = model_config.get("max_tokens", 1024)
        api_key = model_config.get("api_key", "")
    else:
        model_name = os.getenv("INFERENCE_MODEL_NAME", "THUDM/glm-4-9b-chat")
        service_url = INFERENCE_SERVICE_URL
        max_tokens = 1024
        api_key = ""

    payload = {
        "model": model_name,
        "messages": messages,
        "temperature": 0.7,
        "top_p": 0.9,
        "max_tokens": max_tokens,
        "stream": True,
    }

    headers = {"Content-Type": "application/json"}
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"

    budget_start = time.monotonic()

    for attempt in range(MAX_RETRIES + 1):
        elapsed = time.monotonic() - budget_start
        if attempt > 0 and elapsed >= TOTAL_RETRY_BUDGET:
            logger.error(
                "Inference retry budget exhausted",
                extra={"elapsed": elapsed, "attempts": attempt},
            )
            raise InferenceError(
                message=f"Retry budget exhausted after {elapsed:.1f}s"
            )

        try:
            async with httpx.AsyncClient(timeout=INFERENCE_TIMEOUT) as client:
                async with client.stream(
                    "POST",
                    f"{service_url}/v1/chat/completions",
                    json=payload,
                    headers=headers,
                ) as response:
                    if response.status_code >= 500:
                        if response.status_code in NON_RETRYABLE_5XX:
                            raise InferenceError(
                                status_code=response.status_code,
                                message=f"Non-retryable server error {response.status_code}",
                            )

                        if attempt < MAX_RETRIES:
                            delay = BACKOFF_DELAYS[attempt]
                            remaining_budget = TOTAL_RETRY_BUDGET - (
                                time.monotonic() - budget_start
                            )
                            if delay > remaining_budget:
                                raise InferenceError(
                                    status_code=response.status_code,
                                    message="Retry budget would be exceeded",
                                )
                            logger.warning(
                                "Inference 5xx, retrying",
                                extra={
                                    "status_code": response.status_code,
                                    "attempt": attempt + 1,
                                    "delay": delay,
                                },
                            )
                            await asyncio.sleep(delay)
                            continue
                        else:
                            raise InferenceError(
                                status_code=response.status_code,
                                message=f"Max retries exhausted with status {response.status_code}",
                            )

                    if response.status_code >= 400:
                        body = await response.aread()
                        raise InferenceError(
                            status_code=response.status_code,
                            message=f"Client error: {body.decode()[:200]}",
                        )

                    # Successful response — collect streamed tokens
                    tokens: list[str] = []
                    async for line in response.aiter_lines():
                        if not line.startswith("data: "):
                            continue
                        data = line[6:]  # strip "data: " prefix
                        if data.strip() == "[DONE]":
                            break
                        try:
                            import json

                            chunk = json.loads(data)
                            choices = chunk.get("choices", [])
                            if choices:
                                delta = choices[0].get("delta", {})
                                content = delta.get("content", "")
                                if content:
                                    tokens.append(content)
                        except (ValueError, KeyError):
                            continue

                    return tokens

        except httpx.TimeoutException:
            if attempt < MAX_RETRIES:
                delay = BACKOFF_DELAYS[attempt]
                remaining_budget = TOTAL_RETRY_BUDGET - (
                    time.monotonic() - budget_start
                )
                if delay > remaining_budget:
                    raise InferenceError(message="Timeout, retry budget exceeded")
                logger.warning(
                    "Inference timeout, retrying",
                    extra={"attempt": attempt + 1, "delay": delay},
                )
                await asyncio.sleep(delay)
                continue
            raise InferenceError(message="Inference timeout after all retries")

        except InferenceError:
            raise

        except Exception as e:
            logger.error(
                "Unexpected inference error",
                extra={"error_type": type(e).__name__, "error": str(e)},
            )
            raise InferenceError(message=f"Unexpected error: {e}")

    raise InferenceError(message="Exhausted all retry attempts")
