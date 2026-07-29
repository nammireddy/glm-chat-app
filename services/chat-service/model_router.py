"""Model Router — routes chat requests via LiteLLM's complexity router.

LiteLLM handles the intelligent routing internally using its built-in
complexity scorer. The chat-service just needs to call the smart-router
model alias and LiteLLM will classify the request and pick the right backend.

Users can also explicitly select a model via the request body.
"""

import logging
import os

logger = logging.getLogger(__name__)

LITELLM_URL = os.getenv("LITELLM_URL", "http://litellm-proxy:4000")
LITELLM_API_KEY = os.getenv("LITELLM_API_KEY", "sk-glmchat-litellm-internal")

# Model configurations
MODELS = {
    "smart-router": {
        "name": "smart-router",
        "url": LITELLM_URL,
        "description": "Auto-routes to the best model based on request complexity",
        "max_tokens": 2048,
        "api_key": LITELLM_API_KEY,
    },
    "glm-4": {
        "name": "glm-4",
        "url": LITELLM_URL,
        "description": "Fast general chat, Chinese language support (GLM-4-9B)",
        "max_tokens": 1024,
        "api_key": LITELLM_API_KEY,
    },
    "qwen3": {
        "name": "qwen2.5-14b",
        "url": LITELLM_URL,
        "description": "Complex reasoning, coding, math, analysis (Qwen2.5-14B)",
        "max_tokens": 2048,
        "api_key": LITELLM_API_KEY,
    },
}

DEFAULT_MODEL = os.getenv("DEFAULT_MODEL", "smart-router")


def select_model(message: str, explicit_model: str | None = None) -> dict:
    """Select which model to route to.

    If the user explicitly selects a model, use it directly.
    Otherwise, use the smart-router which delegates routing to LiteLLM's
    complexity scorer (keyword matching + heuristic scoring).

    Args:
        message: The user's chat message.
        explicit_model: Optional explicit model selection from the request.

    Returns:
        Model configuration dict with name, url, description, max_tokens, api_key.
    """
    if explicit_model:
        model_key = explicit_model.lower().strip()
        if model_key in MODELS:
            logger.info(f"Explicit model selection: {model_key}")
            return MODELS[model_key]
        # Try partial matching
        for key in MODELS:
            if key in model_key or model_key in key:
                logger.info(f"Partial model match: {model_key} -> {key}")
                return MODELS[key]

    # Default: use smart-router (LiteLLM handles complexity-based routing)
    logger.info(f"Using {DEFAULT_MODEL} (LiteLLM auto-routing)")
    return MODELS[DEFAULT_MODEL]


def get_available_models() -> list[dict]:
    """Return list of available models for the /models endpoint."""
    return [
        {
            "id": key,
            "name": config["name"],
            "description": config["description"],
        }
        for key, config in MODELS.items()
    ]
