"""Embedding Service — FastAPI application.

Loads the BAAI/bge-m3 model via sentence-transformers and exposes a POST /embed
endpoint that returns a 1024-dimensional embedding vector for a given text input.
"""

from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field
from prometheus_fastapi_instrumentator import Instrumentator
from sentence_transformers import SentenceTransformer

model: SentenceTransformer | None = None


class EmbedRequest(BaseModel):
    text: str = Field(..., min_length=1, description="Text to embed")


class EmbedResponse(BaseModel):
    embedding: list[float] = Field(..., description="1024-dimensional embedding vector")


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Load the embedding model on startup."""
    global model
    model = SentenceTransformer("BAAI/bge-m3")
    yield
    model = None


app = FastAPI(title="Embedding Service", lifespan=lifespan)

# Prometheus metrics instrumentation
Instrumentator().instrument(app).expose(app, endpoint="/metrics")


@app.get("/health", status_code=200)
async def health():
    """Liveness/readiness probe."""
    return {"status": "ok"}


@app.post("/embed", response_model=EmbedResponse)
async def embed(request: EmbedRequest):
    """Generate an embedding for the provided text."""
    if model is None:
        raise HTTPException(status_code=503, detail="Model not loaded")

    embedding = model.encode(request.text, normalize_embeddings=True)
    embedding_list = embedding.tolist()

    if len(embedding_list) != 1024:
        raise HTTPException(
            status_code=500,
            detail=f"Unexpected embedding dimension: {len(embedding_list)}, expected 1024",
        )

    return EmbedResponse(embedding=embedding_list)
