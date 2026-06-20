"""Read-only helpers for legacy data archived in migration 065."""

from __future__ import annotations

import uuid

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession


async def count_archived_entry_lines_for_variants(
    db: AsyncSession,
    variant_ids: list[uuid.UUID],
) -> int:
    if not variant_ids:
        return 0
    try:
        result = await db.execute(
            text(
                "SELECT count(*) FROM _archived_entry_line_items "
                "WHERE catalog_variant_id IN :vids"
            ),
            {"vids": tuple(str(v) for v in variant_ids)},
        )
        return int(result.scalar() or 0)
    except Exception:
        return 0


async def count_archived_entry_lines_for_variant(
    db: AsyncSession,
    variant_id: uuid.UUID,
) -> int:
    return await count_archived_entry_lines_for_variants(db, [variant_id])
