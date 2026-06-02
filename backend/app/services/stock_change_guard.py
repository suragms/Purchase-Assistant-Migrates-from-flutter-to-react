"""Block routine stock writes while a warehouse audit is open."""

from __future__ import annotations

import uuid

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.membership import Membership
from app.models.stock_audit import StockAudit

_OPEN_AUDIT_STATUSES = ("draft", "pending_review")

_AUDIT_MOVEMENT_KINDS = frozenset(
    {
        "physical_count",
        "correction",
    }
)

_AUDIT_SOURCE_TYPES = frozenset({"stock_audit", "audit_session"})
_PRIVILEGED_AUDIT_BYPASS_ROLES = frozenset({"owner", "admin", "manager", "super_admin"})


async def business_has_open_stock_audit(
    db: AsyncSession,
    business_id: uuid.UUID,
) -> bool:
    r = await db.execute(
        select(StockAudit.id)
        .where(
            StockAudit.business_id == business_id,
            StockAudit.status.in_(_OPEN_AUDIT_STATUSES),
        )
        .limit(1)
    )
    return r.scalar_one_or_none() is not None


async def assert_stock_changes_allowed(
    db: AsyncSession,
    *,
    business_id: uuid.UUID,
    movement_kind: str,
    source_type: str | None,
    actor_user_id: uuid.UUID | None = None,
) -> None:
    if not await business_has_open_stock_audit(db, business_id):
        return
    if actor_user_id is not None:
        membership = await db.execute(
            select(Membership.role).where(
                Membership.business_id == business_id,
                Membership.user_id == actor_user_id,
            )
        )
        role = (membership.scalar_one_or_none() or "").strip().lower()
        if role in _PRIVILEGED_AUDIT_BYPASS_ROLES:
            return
    kind = (movement_kind or "").strip().lower()
    src = (source_type or "").strip().lower()
    if kind in _AUDIT_MOVEMENT_KINDS or src in _AUDIT_SOURCE_TYPES:
        return
    raise ValueError(
        "A stock audit is in progress. Finish or submit the audit before other stock changes."
    )
