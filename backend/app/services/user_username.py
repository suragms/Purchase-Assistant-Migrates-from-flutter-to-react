"""Collision-safe username allocation for staff users."""

import re
import uuid

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import User


def _slug_from_name(name: str) -> str:
    s = name.strip().lower()
    s = re.sub(r"[^a-z0-9]+", "_", s)
    s = re.sub(r"_+", "_", s).strip("_")
    return (s[:48] or "staff")


async def allocate_username(
    db: AsyncSession,
    *,
    requested: str | None,
    phone_digits: str,
    full_name: str,
) -> str:
    if requested and requested.strip():
        candidate = requested.strip().lower().replace(" ", "_")[:64]
        if re.match(r"^[a-z0-9_]{3,64}$", candidate):
            ex = await db.execute(select(User.id).where(User.username == candidate))
            if not ex.first():
                return candidate
            raise ValueError("username_taken")

    base = f"staff_{phone_digits[-4:]}" if len(phone_digits) >= 4 else "staff"
    slug = _slug_from_name(full_name)
    if slug and slug != "staff":
        base = slug[:48]

    for attempt in range(12):
        suffix = "" if attempt == 0 else f"_{uuid.uuid4().hex[:4]}"
        candidate = f"{base}{suffix}"[:64]
        ex = await db.execute(select(User.id).where(User.username == candidate))
        if not ex.first():
            return candidate
    return f"staff_{uuid.uuid4().hex[:8]}"[:64]
