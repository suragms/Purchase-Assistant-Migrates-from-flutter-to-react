"""Central in-app notification writer with dedupe and realtime invalidation."""

from __future__ import annotations

import logging
import uuid
from datetime import datetime, timezone
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.exc import IntegrityError

from app.models import Membership
from app.models.notification import AppNotification
from app.services.realtime_events import publish_business_event

logger = logging.getLogger(__name__)

PRIORITY_CRITICAL = "critical"
PRIORITY_HIGH = "high"
PRIORITY_MEDIUM = "medium"
PRIORITY_INFO = "info"

CATEGORY_WAREHOUSE = "warehouse"
CATEGORY_PURCHASE = "purchase"
CATEGORY_STAFF = "staff"
CATEGORY_SYSTEM = "system"

_OWNER_ROLES = frozenset({"owner", "admin", "manager"})


def publish_notification_changed(business_id: uuid.UUID) -> None:
    publish_business_event(
        business_id,
        "notification.changed",
        {"at": datetime.now(timezone.utc).isoformat()},
    )


async def recipient_user_ids_for_business(
    db: AsyncSession,
    business_id: uuid.UUID,
    *,
    owner_only: bool = False,
    target_roles: list[str] | None = None,
) -> list[uuid.UUID]:
    q = select(Membership.user_id, Membership.role).where(
        Membership.business_id == business_id
    )
    rows = (await db.execute(q)).all()
    if target_roles:
        allowed = {r.strip().lower() for r in target_roles if r and r.strip()}
        return [uid for uid, role in rows if (role or "").lower() in allowed]
    if owner_only:
        return [uid for uid, role in rows if (role or "").lower() in _OWNER_ROLES]
    return [uid for uid, _ in rows]


async def emit_notification(
    db: AsyncSession,
    *,
    business_id: uuid.UUID,
    user_ids: list[uuid.UUID] | None = None,
    kind: str,
    title: str,
    body: str | None = None,
    priority: str = PRIORITY_MEDIUM,
    category: str = CATEGORY_SYSTEM,
    dedupe_key: str | None = None,
    action_route: str | None = None,
    triggered_by_user_id: uuid.UUID | None = None,
    related_item_id: uuid.UUID | None = None,
    related_purchase_id: uuid.UUID | None = None,
    related_supplier_id: uuid.UUID | None = None,
    payload: dict[str, Any] | None = None,
    metadata: dict[str, Any] | None = None,
    owner_only: bool = False,
    target_roles: list[str] | None = None,
) -> int:
    """Insert notification rows for each target user. Returns count inserted."""
    merged_payload = dict(payload or {})
    if target_roles:
        merged_payload["target_roles"] = [r.strip().lower() for r in target_roles if r]
    targets = user_ids
    if not targets:
        targets = await recipient_user_ids_for_business(
            db,
            business_id,
            owner_only=owner_only,
            target_roles=target_roles,
        )
    if not targets:
        return 0

    inserted = 0
    for uid in targets:
        if dedupe_key:
            ex = await db.execute(
                select(AppNotification.id).where(
                    AppNotification.business_id == business_id,
                    AppNotification.user_id == uid,
                    AppNotification.dedupe_key == dedupe_key,
                ).limit(1)
            )
            if ex.scalar_one_or_none() is not None:
                continue
        try:
            async with db.begin_nested():
                db.add(
                    AppNotification(
                        id=uuid.uuid4(),
                        business_id=business_id,
                        user_id=uid,
                        kind=kind.strip()[:64],
                        title=title.strip()[:500],
                        body=(body or "")[:4000] if body else None,
                        priority=priority[:16],
                        category=category[:32],
                        action_route=action_route[:256] if action_route else None,
                        triggered_by_user_id=triggered_by_user_id,
                        related_item_id=related_item_id,
                        related_purchase_id=related_purchase_id,
                        related_supplier_id=related_supplier_id,
                        payload=merged_payload if merged_payload else None,
                        alert_metadata=metadata,
                        dedupe_key=dedupe_key[:220] if dedupe_key else None,
                    )
                )
                await db.flush()
                inserted += 1
        except IntegrityError:
            logger.warning(
                "notification skipped due to integrity race | business_id=%s user_id=%s dedupe=%s",
                business_id,
                uid,
                dedupe_key,
            )
            continue

    if inserted:
        try:
            publish_notification_changed(business_id)
        except Exception as e:
            logger.warning("publish_notification_changed failed: %s", e)
    return inserted
