"""Async HTTP client for the RAG Pipeline service.

Calls POST /retrieve with query, top_k=5, min_score=0.65.
Times out after 5 seconds and returns empty document list on failure.
"""

import logging
import os
from typing import Any

import httpx

logger = logging.getLogger(__name__)

RAG_SERVICE_URL = os.getenv("RAG_SERVICE_URL", "http://rag-service:8002")
RAG_TIMEOUT = 5.0  # seconds
DEFAULT_TOP_K = 5
DEFAULT_MIN_SCORE = 0.65


async def retrieve_documents(query: str) -> dict[str, Any]:
    """Call the RAG pipeline to retrieve relevant documents.

    Args:
        query: The user's query string.

    Returns:
        Dict with 'documents' (list) and 'grounding' (str).
        On timeout or error, returns empty documents with grounding="none".
    """
    try:
        async with httpx.AsyncClient(timeout=RAG_TIMEOUT) as client:
            response = await client.post(
                f"{RAG_SERVICE_URL}/retrieve",
                json={
                    "query": query,
                    "top_k": DEFAULT_TOP_K,
                    "min_score": DEFAULT_MIN_SCORE,
                },
            )
            response.raise_for_status()
            return response.json()

    except httpx.TimeoutException:
        logger.warning(
            "RAG pipeline timeout, proceeding without context",
            extra={"timeout_seconds": RAG_TIMEOUT},
        )
        return {"documents": [], "grounding": "none"}

    except Exception as e:
        logger.warning(
            "RAG pipeline unavailable, proceeding without context",
            extra={"error_type": type(e).__name__, "error": str(e)},
        )
        return {"documents": [], "grounding": "none"}
