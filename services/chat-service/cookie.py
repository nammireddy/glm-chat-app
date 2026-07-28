"""Session cookie helper.

Issues and reads session_id as an HttpOnly; Secure; SameSite=Strict cookie.
Generates a new UUID v4 when no cookie is present.
"""

import uuid

from fastapi import Request, Response

COOKIE_NAME = "session_id"
COOKIE_MAX_AGE = 86400  # 24 hours, matches Redis TTL


def get_session_id(request: Request) -> str:
    """Read session_id from cookie or generate a new UUID v4."""
    session_id = request.cookies.get(COOKIE_NAME)
    if not session_id:
        session_id = str(uuid.uuid4())
    return session_id


def set_session_cookie(response: Response, session_id: str) -> None:
    """Set the session_id cookie with security attributes.

    Attributes: HttpOnly, Secure, SameSite=Strict.
    """
    response.set_cookie(
        key=COOKIE_NAME,
        value=session_id,
        max_age=COOKIE_MAX_AGE,
        httponly=True,
        secure=True,
        samesite="strict",
    )
