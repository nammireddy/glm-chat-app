"""Rate limiting integration using slowapi.

Token-bucket rate limiter: 60 requests per 60 seconds, keyed on source IP.
Returns HTTP 429 with Retry-After header when exceeded.
"""

from fastapi import Request
from fastapi.responses import JSONResponse
from slowapi import Limiter
from slowapi.errors import RateLimitExceeded
from slowapi.util import get_remote_address

# Create limiter keyed on client IP
limiter = Limiter(key_func=get_remote_address)

# Rate limit string: 60 requests per 60 seconds
RATE_LIMIT = "60/minute"


def rate_limit_exceeded_handler(request: Request, exc: RateLimitExceeded) -> JSONResponse:
    """Custom handler for rate limit exceeded errors.

    Returns HTTP 429 with Retry-After header.
    """
    retry_after = exc.detail.split("per")[1].strip() if "per" in exc.detail else "60"
    return JSONResponse(
        status_code=429,
        content={
            "error": "rate_limit_exceeded",
            "message": "Too many requests. Please try again later.",
            "retry_after": 60,
        },
        headers={"Retry-After": "60"},
    )
