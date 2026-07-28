"""RAG Pipeline Service — FastAPI application.

Provides the /retrieve endpoint that embeds a query, performs cosine
similarity search against pgvector, and returns ranked documents with
a grounding assessment.
"""

import os
from contextlib import asynccontextmanager
from uuid import UUID

import httpx
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

from db import close_pool, cosine_search, create_documents_table, get_pool

EMBEDDING_SERVICE_URL = os.environ.get(
    "EMBEDDING_SERVICE_URL", "http://embedding-service:8001"
)


# --- Request / Response Models ---


class RetrieveRequest(BaseModel):
    """Request body for POST /retrieve."""

    query: str
    top_k: int = Field(default=5, ge=1, le=50)
    min_score: float = Field(default=0.65, ge=0.0, le=1.0)


class DocumentResult(BaseModel):
    """A single retrieved document in the response."""

    doc_id: UUID
    title: str
    url: str | None
    content: str
    score: float


class RetrieveResponse(BaseModel):
    """Response body for POST /retrieve."""

    documents: list[DocumentResult]
    grounding: str  # "full" | "partial" | "none"


# --- Application Lifecycle ---


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Manage startup/shutdown: create table and connection pool."""
    await create_documents_table()
    yield
    await close_pool()


app = FastAPI(title="RAG Pipeline Service", lifespan=lifespan)


# --- Endpoints ---


@app.get("/health")
async def health():
    """Health check endpoint for liveness probes."""
    return {"status": "ok"}


@app.post("/retrieve", response_model=RetrieveResponse)
async def retrieve(request: RetrieveRequest):
    """Retrieve relevant documents for a query.

    1. Embed the query via the Embedding Service.
    2. Perform cosine similarity search against pgvector.
    3. Compute grounding level based on returned scores.
    """
    # Step 1: Get query embedding from Embedding Service
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            embed_response = await client.post(
                f"{EMBEDDING_SERVICE_URL}/embed",
                json={"text": request.query},
            )
            embed_response.raise_for_status()
            embedding = embed_response.json()["embedding"]
    except httpx.HTTPStatusError as e:
        raise HTTPException(
            status_code=502,
            detail=f"Embedding Service returned error: {e.response.status_code}",
        )
    except (httpx.RequestError, KeyError) as e:
        raise HTTPException(
            status_code=502,
            detail=f"Failed to reach Embedding Service: {str(e)}",
        )

    # Step 2: Cosine similarity search
    docs = await cosine_search(
        embedding=embedding,
        top_k=request.top_k,
        min_score=request.min_score,
    )

    # Step 3: Compute grounding field
    if not docs:
        grounding = "none"
    elif all(doc.score >= request.min_score for doc in docs):
        grounding = "full"
    else:
        grounding = "partial"

    # Build response
    document_results = [
        DocumentResult(
            doc_id=doc.doc_id,
            title=doc.title,
            url=doc.url,
            content=doc.content,
            score=round(doc.score, 4),
        )
        for doc in docs
    ]

    return RetrieveResponse(documents=document_results, grounding=grounding)
