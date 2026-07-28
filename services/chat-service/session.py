"""Session management with Redis backend.

Provides async session load/save with stateless fallback on Redis unavailability.
"""

import hashlib
import json
import logging
import os
from datetime import datetime, timezone
from typing import Any

import redis.asyncio as aioredis

logger = logging.getLogger(__name__)

REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379")
SESSION_TTL = 86400  # 24 hours
SESSION_MAX_ENTRIES = 100


class Turn:
    """A single conversation turn."""

    def __init__(self, role: str, content: str, ts: str | None = None):
        self.role = role
        self.content = content
        self.ts = ts or datetime.now(timezone.utc).isoformat()

    def to_dict(self) -> dict[str, Any]:
        return {"role": self.role, "content": self.content, "ts": self.ts}

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "Turn":
        return cls(role=data["role"], content=data["content"], ts=data.get("ts"))

    def __eq__(self, other: object) -> bool:
        if not isinstance(other, Turn):
            return NotImplemented
        return self.role == other.role and self.content == other.content

    def __repr__(self) -> str:
        return f"Turn(role={self.role!r}, content={self.content[:30]!r})"


def hash_session_id(session_id: str) -> str:
    """Hash session_id with SHA-256 for safe logging."""
    return f"sha256:{hashlib.sha256(session_id.encode()).hexdigest()}"


def _get_redis_key(session_id: str) -> str:
    """Build the Redis key for a session."""
    return f"session:{session_id}"


async def _get_redis_client() -> aioredis.Redis:
    """Create and return an async Redis client."""
    return aioredis.from_url(REDIS_URL, decode_responses=True)


async def load_session(session_id: str) -> list[Turn]:
    """Load session history from Redis.

    Returns an empty list if Redis is unavailable (stateless fallback).
    """
    try:
        client = await _get_redis_client()
        key = _get_redis_key(session_id)
        raw_turns = await client.lrange(key, 0, -1)
        await client.aclose()

        turns = []
        for raw in raw_turns:
            data = json.loads(raw)
            turns.append(Turn.from_dict(data))

        logger.info(
            "Session loaded",
            extra={
                "session_id_hash": hash_session_id(session_id),
                "turn_count": len(turns),
            },
        )
        return turns

    except Exception as e:
        logger.warning(
            "Redis unavailable, returning empty session (stateless fallback)",
            extra={
                "session_id_hash": hash_session_id(session_id),
                "error_type": type(e).__name__,
            },
        )
        return []


async def save_session(session_id: str, turns: list[Turn]) -> None:
    """Save session turns to Redis using RPUSH + LTRIM.

    Caps stored entries at SESSION_MAX_ENTRIES (100) and sets TTL to 86400s.
    Returns silently on Redis unavailability (stateless fallback).
    """
    try:
        client = await _get_redis_client()
        key = _get_redis_key(session_id)

        # Serialize each turn and RPUSH
        pipeline = client.pipeline()
        for turn in turns:
            pipeline.rpush(key, json.dumps(turn.to_dict()))

        # Trim to keep only the last SESSION_MAX_ENTRIES
        pipeline.ltrim(key, -SESSION_MAX_ENTRIES, -1)
        # Set TTL
        pipeline.expire(key, SESSION_TTL)

        await pipeline.execute()
        await client.aclose()

        logger.info(
            "Session saved",
            extra={
                "session_id_hash": hash_session_id(session_id),
                "turn_count": len(turns),
            },
        )

    except Exception as e:
        logger.warning(
            "Redis unavailable, session not saved (stateless fallback)",
            extra={
                "session_id_hash": hash_session_id(session_id),
                "error_type": type(e).__name__,
            },
        )
