"""Server-side staff activity audit (login, password reset)."""

import uuid
from datetime import datetime, timezone

from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Membership, User
from app.models.user_session import StaffActivityLog


async def log_staff_activity(
    db: AsyncSession,
    *,
    business_id: uuid.UUID,
    user: User,
    action_type: str,
    details: dict | None = None,
) -> None:
    display = user.name or user.username
    db.add(
        StaffActivityLog(
            business_id=business_id,
            user_id=user.id,
            user_name=display,
            action_type=action_type,
            details=details,
        )
    )


async def log_staff_login_if_applicable(
    db: AsyncSession,
    user: User,
    membership: Membership | None,
) -> None:
    if not membership or membership.role not in ("staff", "manager"):
        return
    await log_staff_activity(
        db,
        business_id=membership.business_id,
        user=user,
        action_type="LOGIN",
        details={"at": datetime.now(timezone.utc).isoformat()},
    )


async def log_password_reset(
    db: AsyncSession,
    *,
    business_id: uuid.UUID,
    actor: User,
    target: User,
) -> None:
    await log_staff_activity(
        db,
        business_id=business_id,
        user=actor,
        action_type="PASSWORD_RESET",
        details={
            "target_user_id": str(target.id),
            "target_name": target.name or target.username,
        },
    )
