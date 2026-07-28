"""Prompt builder for the Chat Service.

Assembles the final prompt list:
1. System prompt
2. Retrieved document chunks as a role:user context block
3. Last 20 turns of conversation history
4. Current user message
"""

from typing import Any

SYSTEM_PROMPT = (
    "You are a helpful assistant. Answer only from the provided context. "
    "If the context does not contain enough information to answer, "
    "say so clearly."
)

MAX_HISTORY_TURNS = 20


def build_prompt(
    documents: list[dict[str, Any]],
    history: list[dict[str, str]],
    user_message: str,
) -> list[dict[str, str]]:
    """Assemble the prompt messages for the inference service.

    Args:
        documents: Retrieved RAG documents (each with 'content', 'title', etc.)
        history: Conversation history as list of {role, content} dicts.
        user_message: The current user message.

    Returns:
        List of message dicts ready for the inference service.
    """
    messages: list[dict[str, str]] = []

    # 1. System prompt
    messages.append({"role": "system", "content": SYSTEM_PROMPT})

    # 2. Retrieved document chunks as context
    if documents:
        context_parts = []
        for i, doc in enumerate(documents, 1):
            title = doc.get("title", f"Document {i}")
            content = doc.get("content", "")
            context_parts.append(f"[{i}] {title}:\n{content}")

        context_block = "Context:\n" + "\n\n".join(context_parts)
        messages.append({"role": "user", "content": context_block})

    # 3. Last 20 turns of conversation history
    recent_history = history[-MAX_HISTORY_TURNS:]
    for turn in recent_history:
        messages.append({"role": turn["role"], "content": turn["content"]})

    # 4. Current user message
    messages.append({"role": "user", "content": user_message})

    return messages
