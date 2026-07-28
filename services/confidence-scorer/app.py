"""Confidence Scorer Service.

Scores (query, answer) pairs using a cross-encoder model and returns a
confidence score in [0, 1] along with a threshold check.
"""

from contextlib import asynccontextmanager

import numpy as np
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from sentence_transformers import CrossEncoder

model: CrossEncoder | None = None


def sigmoid(x: float) -> float:
    """Compute the sigmoid function."""
    return float(1.0 / (1.0 + np.exp(-x)))


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Load the cross-encoder model at startup."""
    global model
    model = CrossEncoder("cross-encoder/ms-marco-MiniLM-L-6-v2")
    yield


app = FastAPI(title="Confidence Scorer", lifespan=lifespan)

CONFIDENCE_THRESHOLD = 0.7


class ScoreRequest(BaseModel):
    query: str
    answer: str


class ScoreResponse(BaseModel):
    score: float
    threshold_met: bool


@app.post("/score", response_model=ScoreResponse)
async def score(request: ScoreRequest) -> ScoreResponse:
    """Score the relevance of an answer to a query.

    Computes a cross-encoder logit for the (query, answer) pair,
    applies sigmoid normalization to produce a score in [0, 1],
    and checks whether the score meets the confidence threshold.
    """
    if model is None:
        raise HTTPException(status_code=503, detail="Model not loaded")

    logit = model.predict([(request.query, request.answer)])[0]
    score_value = sigmoid(float(logit))
    threshold_met = score_value >= CONFIDENCE_THRESHOLD

    return ScoreResponse(score=score_value, threshold_met=threshold_met)


@app.get("/health")
async def health():
    """Health check endpoint for liveness probes."""
    return {"status": "healthy"}
