"""Server-side staff activity audit."""

import logging
import uuid
from datetime import datetime, timezone
from typing import Any

from sqlalchemy.ext.asyncio import AsyncSession

logger = logging.getLogger(__name__)

from app.models import Membership, User
from app.models.user_session import StaffActivityLog


async def log_staff_activity(
    db: AsyncSession,
    *,
    business_id: uuid.UUID,
    user: User,
    action_type: str,
    item_id: uuid.UUID | None = None,
    item_name: str | None = None,
    details: dict | None = None,
    before_data: dict | None = None,
    after_data: dict | None = None,
) -> None:
    merged = dict(details or {})
    if before_data is not None:
        merged["before"] = before_data
    if after_data is not None:
        merged["after"] = after_data
    display = user.name or user.username
    db.add(
        StaffActivityLog(
            business_id=business_id,
            user_id=user.id,
            user_name=display,
            action_type=action_type,
            item_id=item_id,
            item_name=item_name,
            details=merged or None,
        )
    )


async def log_staff_activity_best_effort(
    db: AsyncSession,
    *,
    business_id: uuid.UUID,
    user: User,
    action_type: str,
    item_id: uuid.UUID | None = None,
    item_name: str | None = None,
    details: dict | None = None,
    before_data: dict | None = None,
    after_data: dict | None = None,
) -> None:
    """Write activity in a savepoint so CHECK/audit failures never roll back the main txn."""
    try:
        async with db.begin_nested():
            await log_staff_activity(
                db,
                business_id=business_id,
                user=user,
                action_type=action_type,
                item_id=item_id,
                item_name=item_name,
                details=details,
                before_data=before_data,
                after_data=after_data,
            )
            await db.flush()
    except Exception:
        logger.warning(
            "staff activity log skipped action_type=%s",
            action_type,
            exc_info=True,
        )


async def log_staff_login_if_applicable(
    db: AsyncSession,
    user: User,
    membership: Membership | None,
) -> None:
    if not membership or membership.role not in ("staff", "manager", "admin"):
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


async def log_user_lifecycle(
    db: AsyncSession,
    *,
    business_id: uuid.UUID,
    actor: User,
    target: User,
    action_type: str,
    before_data: dict[str, Any] | None = None,
    after_data: dict[str, Any] | None = None,
) -> None:
    await log_staff_activity(
        db,
        business_id=business_id,
        user=actor,
        action_type=action_type,
        details={
            "target_user_id": str(target.id),
            "target_name": target.name or target.email,
        },
        before_data=before_data,
        after_data=after_data,
    )
