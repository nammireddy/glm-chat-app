"""
Timeout Middleware — ASGI middleware that cancels requests exceeding a deadline.

Returns HTTP 504 (Gateway Timeout) if processing exceeds the configured timeout.
"""

from __future__ import annotations

import asyncio
from typing import Callable

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse, Response


class TimeoutMiddleware(BaseHTTPMiddleware):
    """
    ASGI middleware that enforces a per-request timeout.

    If the request handler does not complete within `timeout_seconds`,
    the request is cancelled and an HTTP 504 response is returned.
    """

    def __init__(self, app, timeout_seconds: float = 60.0) -> None:
        super().__init__(app)
        self.timeout_seconds = timeout_seconds

    async def dispatch(self, request: Request, call_next: Callable) -> Response:
        try:
            response = await asyncio.wait_for(
                call_next(request),
                timeout=self.timeout_seconds,
            )
            return response
        except asyncio.TimeoutError:
            return JSONResponse(
                {"error": "Request timed out"},
                status_code=504,
            )
