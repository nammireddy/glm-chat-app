"""Async HTTP client for the Confidence Scorer service.

Calls POST /score and returns (score, threshold_met).
Returns (score=0.0, threshold_met=False) when the scorer is unreachable
(circuit breaker open).
"""

import logging
import os
from dataclasses import dataclass

import httpx

logger = logging.getLogger(__name__)

SCORER_SERVICE_URL = os.getenv("SCORER_SERVICE_URL", "http://confidence-scorer:8003")
SCORER_TIMEOUT = 5.0  # seconds


@dataclass
class ScoreResult:
    """Result from the confidence scorer."""

    score: float
    threshold_met: bool


async def score_answer(query: str, answer: str) -> ScoreResult:
    """Score the generated answer against the original query.

    Args:
        query: The user's original question.
        answer: The generated answer to score.

    Returns:
        ScoreResult with score and threshold_met.
        On scorer unavailability, returns score=0.0, threshold_met=False.
    """
    try:
        async with httpx.AsyncClient(timeout=SCORER_TIMEOUT) as client:
            response = await client.post(
                f"{SCORER_SERVICE_URL}/score",
                json={"query": query, "answer": answer},
            )
            response.raise_for_status()
            data = response.json()
            return ScoreResult(
                score=data["score"],
                threshold_met=data["threshold_met"],
            )

    except Exception as e:
        logger.warning(
            "Confidence scorer unavailable (circuit breaker open), "
            "defaulting to score=0.0",
            extra={"error_type": type(e).__name__, "error": str(e)},
        )
        return ScoreResult(score=0.0, threshold_met=False)
