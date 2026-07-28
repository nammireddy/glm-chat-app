"""Prompt builder for the Chat Service.

Assembles the final prompt list:
1. System prompt
2. Retrieved document chunks as a role:user context block
3. Last 20 turns of conversation history
4. Current user message
"""

from typing import Any

SYSTEM_PROMPT_WITH_CONTEXT = (
    "You are a helpful assistant. Answer using the provided context when available. "
    "If the context contains relevant information, prioritize it in your answer "
    "and cite the source."
)

SYSTEM_PROMPT_NO_CONTEXT = (
    "You are a helpful assistant. No specific context documents were found for this query. "
    "Answer from your general knowledge. Be helpful, accurate, and concise. "
    "If you're unsure about something, say so."
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

    # 1. System prompt — different depending on whether we have RAG context
    if documents:
        messages.append({"role": "system", "content": SYSTEM_PROMPT_WITH_CONTEXT})
    else:
        messages.append({"role": "system", "content": SYSTEM_PROMPT_NO_CONTEXT})

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
