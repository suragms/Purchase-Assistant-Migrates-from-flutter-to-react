import uuid
from datetime import datetime, timezone
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import delete, func, or_, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps import get_current_user, require_membership
from app.models import User
from app.models.notification import AppNotification
from app.schemas.notification import (
    ClientNotificationEventIn,
    NotificationBulkActionOut,
    NotificationOut,
    NotificationReadPatch,
    NotificationSummaryOut,
    UnreadCountOut,
)
from app.services.notification_emitter import (
    CATEGORY_SYSTEM,
    PRIORITY_CRITICAL,
    emit_notification,
    publish_notification_changed,
)

router = APIRouter(prefix="/v1/businesses/{business_id}/notifications", tags=["notifications"])


def _user_filters(business_id: uuid.UUID, user_id: uuid.UUID):
    return [
        AppNotification.business_id == business_id,
        AppNotification.user_id == user_id,
    ]


@router.get("", response_model=list[NotificationOut])
async def list_notifications(
    business_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
    _m: Annotated[object, Depends(require_membership)],
    page: int = Query(1, ge=1),
    per_page: int = Query(30, ge=1, le=100),
    kind: str | None = Query(default=None, max_length=64),
    category: str | None = Query(default=None, max_length=32),
    priority: str | None = Query(default=None, max_length=16),
    unread_only: bool = Query(default=False),
    q: str | None = Query(default=None, max_length=120),
):
    del _m
    off = (page - 1) * per_page
    filters = _user_filters(business_id, user.id)
    if kind:
        filters.append(AppNotification.kind == kind.strip())
    if category:
        filters.append(AppNotification.category == category.strip())
    if priority:
        filters.append(AppNotification.priority == priority.strip())
    if unread_only:
        filters.append(AppNotification.read_at.is_(None))
    if q and q.strip():
        term = f"%{q.strip()}%"
        filters.append(
            or_(
                AppNotification.title.ilike(term),
                AppNotification.body.ilike(term),
            )
        )
    r = await db.execute(
        select(AppNotification, User.name)
        .outerjoin(User, AppNotification.triggered_by_user_id == User.id)
        .where(*filters)
        .order_by(AppNotification.created_at.desc())
        .offset(off)
        .limit(per_page)
    )
    out: list[NotificationOut] = []
    for row, actor_name in r.all():
        base = NotificationOut.model_validate(row)
        out.append(
            base.model_copy(
                update={
                    "triggered_by_name": (actor_name or "").strip() or None,
                }
            )
        )
    return out


@router.get("/summary", response_model=NotificationSummaryOut)
async def notifications_summary(
    business_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
    _m: Annotated[object, Depends(require_membership)],
):
    del _m
    base = _user_filters(business_id, user.id) + [AppNotification.read_at.is_(None)]
    r = await db.execute(
        select(func.count()).select_from(AppNotification).where(*base)
    )
    unread = int(r.scalar_one() or 0)
    by_cat: dict[str, int] = {}
    by_pri: dict[str, int] = {}
    if unread:
        cr = await db.execute(
            select(AppNotification.category, func.count())
            .where(*base)
            .group_by(AppNotification.category)
        )
        by_cat = {str(cat): int(n) for cat, n in cr.all()}
        pr = await db.execute(
            select(AppNotification.priority, func.count())
            .where(*base)
            .group_by(AppNotification.priority)
        )
        by_pri = {str(p): int(n) for p, n in pr.all()}
    return NotificationSummaryOut(unread=unread, by_category=by_cat, by_priority=by_pri)


@router.get("/unread-count", response_model=UnreadCountOut)
async def unread_count(
    business_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
    _m: Annotated[object, Depends(require_membership)],
):
    del _m
    r = await db.execute(
        select(func.count())
        .select_from(AppNotification)
        .where(
            *_user_filters(business_id, user.id),
            AppNotification.read_at.is_(None),
        )
    )
    return UnreadCountOut(unread=int(r.scalar_one() or 0))


@router.post("/mark-all-read", response_model=NotificationBulkActionOut)
async def mark_all_read(
    business_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
    _m: Annotated[object, Depends(require_membership)],
    kind: str | None = Query(default=None, max_length=64),
):
    del _m
    filters = _user_filters(business_id, user.id) + [AppNotification.read_at.is_(None)]
    if kind:
        filters.append(AppNotification.kind == kind.strip())
    res = await db.execute(
        update(AppNotification)
        .where(*filters)
        .values(read_at=datetime.now(timezone.utc))
    )
    await db.commit()
    publish_notification_changed(business_id)
    return NotificationBulkActionOut(updated=int(res.rowcount or 0))


@router.delete("/clear-all", response_model=NotificationBulkActionOut)
async def clear_all(
    business_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
    _m: Annotated[object, Depends(require_membership)],
    kind: str | None = Query(default=None, max_length=64),
):
    del _m
    filters = _user_filters(business_id, user.id)
    if kind:
        filters.append(AppNotification.kind == kind.strip())
    res = await db.execute(delete(AppNotification).where(*filters))
    await db.commit()
    publish_notification_changed(business_id)
    return NotificationBulkActionOut(updated=int(res.rowcount or 0))


@router.post("/client-event", response_model=NotificationBulkActionOut)
async def client_notification_event(
    business_id: uuid.UUID,
    body: ClientNotificationEventIn,
    db: Annotated[AsyncSession, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
    _m: Annotated[object, Depends(require_membership)],
):
    """Sanitized client-side failures (PDF export, sync) — one row for current user."""
    del _m
    kind = body.kind.strip()
    if kind not in ("export_failed", "sync_failed", "print_failed"):
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="Unsupported event kind")
    inserted = await emit_notification(
        db,
        business_id=business_id,
        user_ids=[user.id],
        kind=kind,
        title=body.title.strip()[:500],
        body=(body.body or "Please try again.")[:4000],
        priority=body.priority if body.priority in ("critical", "high", "medium", "info") else PRIORITY_CRITICAL,
        category=body.category if body.category else CATEGORY_SYSTEM,
        dedupe_key=body.dedupe_key,
        action_route=body.action_route,
        triggered_by_user_id=user.id,
        related_item_id=body.related_item_id,
        related_purchase_id=body.related_purchase_id,
        payload={"source": "client"},
    )
    if inserted:
        await db.commit()
    return NotificationBulkActionOut(updated=inserted)


@router.patch("/{notification_id}", response_model=NotificationOut)
async def patch_notification(
    business_id: uuid.UUID,
    notification_id: uuid.UUID,
    body: NotificationReadPatch,
    db: Annotated[AsyncSession, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
    _m: Annotated[object, Depends(require_membership)],
):
    del _m
    r = await db.execute(
        select(AppNotification).where(
            AppNotification.id == notification_id,
            AppNotification.business_id == business_id,
            AppNotification.user_id == user.id,
        )
    )
    row = r.scalar_one_or_none()
    if not row:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Notification not found")
    if body.read:
        row.read_at = datetime.now(timezone.utc)
    else:
        row.read_at = None
    await db.commit()
    await db.refresh(row)
    publish_notification_changed(business_id)
    return NotificationOut.model_validate(row)
