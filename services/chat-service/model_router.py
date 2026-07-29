"""Model Router — routes chat requests to the appropriate LLM.

Routing logic:
- GLM-4-9B: General chat, Chinese language, lightweight queries
- Qwen3-27B: Complex reasoning, coding, math, analysis, long-form answers

The user can also explicitly select a model via the request body.
"""

import logging
import os
import re

logger = logging.getLogger(__name__)

# Model configurations
MODELS = {
    "glm-4": {
        "name": "THUDM/glm-4-9b-chat",
        "url": os.getenv("INFERENCE_SERVICE_URL", "http://inference-service:8000"),
        "description": "Fast general chat, Chinese language support",
        "max_tokens": 1024,
    },
    "qwen3": {
        "name": "Qwen/Qwen2.5-14B-Instruct-AWQ",
        "url": os.getenv("QWEN3_SERVICE_URL", "http://qwen3-service:8000"),
        "description": "Complex reasoning, coding, math, analysis (Qwen2.5-14B)",
        "max_tokens": 2048,
    },
}

DEFAULT_MODEL = os.getenv("DEFAULT_MODEL", "glm-4")

# Keywords/patterns that suggest routing to Qwen3 (the stronger model)
COMPLEX_PATTERNS = [
    # Coding
    r"\b(code|program|function|class|algorithm|debug|refactor|implement)\b",
    r"\b(python|javascript|typescript|java|rust|go|sql|html|css)\b",
    r"\b(api|endpoint|database|query|schema|migration)\b",
    # Math & reasoning
    r"\b(calculate|solve|prove|equation|formula|derivative|integral)\b",
    r"\b(math|statistics|probability|linear algebra)\b",
    # Analysis & complex tasks
    r"\b(analyze|compare|contrast|evaluate|critique|review)\b",
    r"\b(explain in detail|step by step|thoroughly|comprehensive)\b",
    r"\b(architecture|design pattern|system design|tradeoff)\b",
    # Long-form
    r"\b(essay|article|report|summary|outline|plan)\b",
    r"\b(write me a|create a detailed|give me a complete)\b",
]

# Keywords that suggest sticking with GLM-4 (lighter model)
SIMPLE_PATTERNS = [
    r"\b(hello|hi|hey|thanks|thank you|bye|goodbye)\b",
    r"\b(what is|who is|when was|where is|how old)\b",
    r"\b(translate|翻译|中文|chinese)\b",
]


def select_model(message: str, explicit_model: str | None = None) -> dict:
    """Select which model to route to based on the message content.

    Args:
        message: The user's chat message.
        explicit_model: Optional explicit model selection from the request.

    Returns:
        Model configuration dict with name, url, description, max_tokens.
    """
    # If user explicitly selected a model, use it
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

    # Check if message matches complex patterns (route to Qwen3)
    message_lower = message.lower()

    # Check for simple/greeting patterns first
    for pattern in SIMPLE_PATTERNS:
        if re.search(pattern, message_lower):
            # Short simple messages stay on GLM-4
            if len(message) < 100:
                logger.info("Routed to glm-4 (simple query)")
                return MODELS["glm-4"]

    # Check for complex patterns
    complex_score = 0
    for pattern in COMPLEX_PATTERNS:
        if re.search(pattern, message_lower):
            complex_score += 1

    # Route to Qwen3 if message is complex (2+ pattern matches or long message)
    if complex_score >= 2 or (complex_score >= 1 and len(message) > 200):
        logger.info(f"Routed to qwen3 (complexity score: {complex_score})")
        return MODELS["qwen3"]

    # Default model
    logger.info(f"Routed to {DEFAULT_MODEL} (default)")
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
