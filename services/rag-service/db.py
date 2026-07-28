"""Database layer for the RAG Pipeline Service.

Manages asyncpg connection pool to Aurora PostgreSQL with pgvector,
provides DDL setup and cosine similarity search.
"""

import os
from dataclasses import dataclass
from uuid import UUID

import asyncpg


@dataclass
class Document:
    """Represents a retrieved document chunk with similarity score."""

    doc_id: UUID
    title: str
    url: str | None
    content: str
    score: float


# Connection pool singleton
_pool: asyncpg.Pool | None = None


async def get_pool() -> asyncpg.Pool:
    """Get or create the asyncpg connection pool."""
    global _pool
    if _pool is None:
        _pool = await asyncpg.create_pool(
            host=os.environ.get("PGHOST", "localhost"),
            port=int(os.environ.get("PGPORT", "5432")),
            user=os.environ.get("PGUSER", "rag_service"),
            password=os.environ.get("PGPASSWORD", ""),
            database=os.environ.get("PGDATABASE", "ragdb"),
            min_size=2,
            max_size=10,
        )
    return _pool


async def close_pool() -> None:
    """Close the connection pool."""
    global _pool
    if _pool is not None:
        await _pool.close()
        _pool = None


async def create_documents_table() -> None:
    """Create the documents table and HNSW index if they do not exist."""
    pool = await get_pool()
    async with pool.acquire() as conn:
        await conn.execute("CREATE EXTENSION IF NOT EXISTS vector;")
        await conn.execute("""
            CREATE TABLE IF NOT EXISTS documents (
                id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                title       TEXT NOT NULL,
                url         TEXT,
                chunk_index INT  NOT NULL,
                content     TEXT NOT NULL,
                embedding   VECTOR(1024) NOT NULL,
                metadata    JSONB,
                created_at  TIMESTAMPTZ DEFAULT NOW()
            );
        """)
        await conn.execute("""
            CREATE INDEX IF NOT EXISTS documents_embedding_hnsw_idx
            ON documents USING hnsw (embedding vector_cosine_ops)
            WITH (m = 16, ef_construction = 64);
        """)


async def cosine_search(
    embedding: list[float], top_k: int = 5, min_score: float = 0.65
) -> list[Document]:
    """Perform cosine similarity search against the documents table.

    Args:
        embedding: Query embedding vector (1024 dimensions).
        top_k: Maximum number of results to return.
        min_score: Minimum cosine similarity threshold (0-1).

    Returns:
        List of Document objects sorted by descending similarity score.
    """
    pool = await get_pool()
    # pgvector cosine distance operator <=> returns distance (1 - similarity),
    # so similarity = 1 - distance.
    query = """
        SELECT
            id,
            title,
            url,
            content,
            1 - (embedding <=> $1::vector) AS score
        FROM documents
        WHERE 1 - (embedding <=> $1::vector) >= $2
        ORDER BY embedding <=> $1::vector
        LIMIT $3;
    """
    embedding_str = "[" + ",".join(str(v) for v in embedding) + "]"
    async with pool.acquire() as conn:
        rows = await conn.fetch(query, embedding_str, min_score, top_k)

    return [
        Document(
            doc_id=row["id"],
            title=row["title"],
            url=row["url"],
            content=row["content"],
            score=float(row["score"]),
        )
        for row in rows
    ]
