"""Resolve login identifier (username, phone, or email) to a User row."""

import re

from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import User


def _phone_digits(phone: str) -> str:
    return re.sub(r"\D", "", phone)


async def _match_user_by_phone_digits(db: AsyncSession, digits: str) -> User | None:
    staff_email = f"{digits}@staff.harisree.local"
    r = await db.execute(select(User).where(User.email == staff_email))
    user = r.scalar_one_or_none()
    if user:
        return user

    bind = db.get_bind()
    dialect = bind.dialect.name if bind is not None else "postgresql"
    if dialect == "postgresql":
        from sqlalchemy import func

        r = await db.execute(
            select(User).where(
                func.regexp_replace(User.phone, r"\D", "", "g") == digits
            )
        )
        return r.scalar_one_or_none()

    r = await db.execute(select(User).where(User.phone.isnot(None)))
    for candidate in r.scalars().all():
        if candidate.phone and _phone_digits(candidate.phone) == digits:
            return candidate
    return None


async def resolve_user_by_login_identifier(
    db: AsyncSession, identifier: str
) -> User | None:
    """
    Match warehouse login: username (exact), phone (digits), then email.
    Staff synthetic emails: {digits}@staff.harisree.local
    """
    raw = (identifier or "").strip()
    if not raw:
        return None

    lowered = raw.lower()
    username_candidate = lowered.replace(" ", "_")
    if re.match(r"^[a-z0-9_]{3,64}$", username_candidate):
        r = await db.execute(select(User).where(User.username == username_candidate))
        user = r.scalar_one_or_none()
        if user:
            return user

    digits = _phone_digits(raw)
    if len(digits) >= 6:
        user = await _match_user_by_phone_digits(db, digits)
        if user:
            return user

    if "@" in lowered:
        r = await db.execute(select(User).where(User.email == lowered))
        return r.scalar_one_or_none()

    return None
