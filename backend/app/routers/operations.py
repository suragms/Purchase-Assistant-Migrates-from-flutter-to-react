"""Daily usage logging and staff checklist (StockEase operations)."""

from __future__ import annotations

import re
import uuid
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal
from typing import Annotated, Literal

from fastapi import APIRouter, Body, Depends, HTTPException, status
from sqlalchemy import delete, func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps import get_current_user, require_membership, require_permission
from app.models import (
    CatalogItem,
    CategoryType,
    DailyUsageLog,
    ItemCategory,
    Membership,
    StaffChecklistCompletion,
    StaffChecklistTemplate,
    TradePurchase,
    TradePurchaseLine,
    User,
)
from app.models.stock_adjustment import StockAdjustmentLog
from app.schemas.operations import (
    ChecklistCompleteIn,
    ChecklistSummaryOut,
    ChecklistTaskOut,
    ChecklistTemplateItemIn,
    ChecklistTemplateOut,
    ChecklistTemplatesPutIn,
    ChecklistTodayOut,
    DailySnapshotOut,
    UsageLineIn,
    UsageLineOut,
    UsageSubmitIn,
    UsageSummaryOut,
    UsageTodayOut,
)
from app.services.staff_audit import log_staff_activity
from app.services.stock_inventory import catalog_stock_qty
from app.services.unit_normalization import line_qty_in_stock_unit

router = APIRouter(prefix="/v1/businesses/{business_id}/operations", tags=["operations"])

ChecklistSlot = Literal["morning", "midday", "evening"]

_DEFAULT_TEMPLATES: list[tuple[str, str, str, int]] = [
    ("morning", "open_check", "Opening stock check", 1),
    ("morning", "fridge_temp", "Fridge / cold storage check", 2),
    ("midday", "restock", "Midday restock check", 1),
    ("midday", "barcode_scan", "Scan new deliveries", 2),
    ("evening", "usage_log", "Log today's usage", 1),
    ("evening", "closing_stock", "Closing stock verification", 2),
]


def _slug_task_key(label: str, fallback: str = "task") -> str:
    s = re.sub(r"[^a-z0-9]+", "_", label.lower()).strip("_")
    return (s[:48] if s else fallback)


async def _ensure_default_templates(db: AsyncSession, business_id: uuid.UUID) -> None:
    """Seed six default tasks for this business only (not blocked by global rows)."""
    r = await db.execute(
        select(func.count())
        .select_from(StaffChecklistTemplate)
        .where(StaffChecklistTemplate.business_id == business_id)
    )
    if (r.scalar_one() or 0) > 0:
        return
    for slot, key, label, order in _DEFAULT_TEMPLATES:
        db.add(
            StaffChecklistTemplate(
                business_id=business_id,
                slot=slot,
                task_key=key,
                label=label,
                sort_order=order,
            )
        )
    await db.flush()


async def _templates_for_business(
    db: AsyncSession, business_id: uuid.UUID
) -> list[StaffChecklistTemplate]:
    await _ensure_default_templates(db, business_id)
    tr = await db.execute(
        select(StaffChecklistTemplate)
        .where(StaffChecklistTemplate.business_id == business_id)
        .order_by(StaffChecklistTemplate.slot, StaffChecklistTemplate.sort_order)
    )
    rows = list(tr.scalars().all())
    if rows:
        return rows
    tr2 = await db.execute(
        select(StaffChecklistTemplate)
        .where(StaffChecklistTemplate.business_id.is_(None))
        .order_by(StaffChecklistTemplate.slot, StaffChecklistTemplate.sort_order)
    )
    return list(tr2.scalars().all())


async def _purchased_today_map(
    db: AsyncSession, business_id: uuid.UUID, item_ids: list[uuid.UUID], today: date
) -> dict[uuid.UUID, Decimal]:
    if not item_ids:
        return {}
    r = await db.execute(
        select(TradePurchaseLine, CatalogItem)
        .join(TradePurchase, TradePurchaseLine.trade_purchase_id == TradePurchase.id)
        .join(CatalogItem, TradePurchaseLine.catalog_item_id == CatalogItem.id)
        .where(
            TradePurchase.business_id == business_id,
            TradePurchase.purchase_date == today,
            TradePurchase.status.notin_(("cancelled", "deleted")),
            TradePurchase.is_delivered.is_(True),
            TradePurchaseLine.catalog_item_id.in_(item_ids),
            CatalogItem.business_id == business_id,
            CatalogItem.deleted_at.is_(None),
        )
    )
    totals: dict[uuid.UUID, Decimal] = {}
    for line, item in r.all():
        totals[item.id] = totals.get(item.id, Decimal("0")) + line_qty_in_stock_unit(line, item)
    return totals


@router.get("/checklist/today", response_model=ChecklistTodayOut)
async def checklist_today(
    business_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
    _m: Annotated[Membership, Depends(require_membership)],
):
    today = date.today()
    templates = await _templates_for_business(db, business_id)
    cr = await db.execute(
        select(StaffChecklistCompletion).where(
            StaffChecklistCompletion.business_id == business_id,
            StaffChecklistCompletion.user_id == user.id,
            StaffChecklistCompletion.checklist_date == today,
        )
    )
    done = {(c.slot, c.task_key): c for c in cr.scalars().all()}
    tasks: list[ChecklistTaskOut] = []
    for t in templates:
        c = done.get((t.slot, t.task_key))
        tasks.append(
            ChecklistTaskOut(
                slot=t.slot,
                task_key=t.task_key,
                label=t.label,
                completed=c is not None,
                completed_at=c.completed_at if c else None,
                notes=c.notes if c else None,
            )
        )
    pct = (sum(1 for x in tasks if x.completed) / len(tasks) * 100) if tasks else 0.0
    return ChecklistTodayOut(
        checklist_date=today, tasks=tasks, completion_pct=round(pct, 1)
    )


@router.post("/checklist/{slot}/complete", status_code=status.HTTP_204_NO_CONTENT)
async def checklist_complete(
    business_id: uuid.UUID,
    slot: ChecklistSlot,
    body: ChecklistCompleteIn,
    db: Annotated[AsyncSession, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
    _m: Annotated[Membership, Depends(require_membership)],
):
    today = date.today()
    existing = await db.execute(
        select(StaffChecklistCompletion).where(
            StaffChecklistCompletion.business_id == business_id,
            StaffChecklistCompletion.user_id == user.id,
            StaffChecklistCompletion.checklist_date == today,
            StaffChecklistCompletion.slot == slot,
            StaffChecklistCompletion.task_key == body.task_key,
        )
    )
    if existing.scalar_one_or_none():
        return
    db.add(
        StaffChecklistCompletion(
            business_id=business_id,
            user_id=user.id,
            checklist_date=today,
            slot=slot,
            task_key=body.task_key,
            notes=body.notes,
        )
    )
    try:
        await log_staff_activity(
            db,
            business_id=business_id,
            user=user,
            action_type="CHECKLIST_COMPLETE",
            details={"slot": slot, "task_key": body.task_key},
        )
        await db.commit()
    except IntegrityError:
        await db.rollback()
        return


@router.get("/usage/today", response_model=UsageTodayOut)
async def usage_today(
    business_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
):
    today = date.today()
    ir = await db.execute(
        select(CatalogItem)
        .where(
            CatalogItem.business_id == business_id,
            CatalogItem.deleted_at.is_(None),
            CatalogItem.current_stock.isnot(None),
            CatalogItem.current_stock > 0,
        )
        .order_by(CatalogItem.name)
    )
    items = list(ir.scalars().all())
    item_ids = [i.id for i in items]
    purchased = await _purchased_today_map(db, business_id, item_ids, today)
    logs: dict[uuid.UUID, DailyUsageLog] = {}
    if item_ids:
        lr = await db.execute(
            select(DailyUsageLog).where(
                DailyUsageLog.business_id == business_id,
                DailyUsageLog.usage_date == today,
                DailyUsageLog.item_id.in_(item_ids),
            )
        )
        logs = {log.item_id: log for log in lr.scalars().all()}
    lines: list[UsageLineOut] = []
    missing = 0
    for item in items:
        cur = catalog_stock_qty(item)
        p = purchased.get(item.id, Decimal("0"))
        log = logs.get(item.id)
        if log:
            lines.append(
                UsageLineOut(
                    item_id=item.id,
                    item_name=item.name,
                    item_code=item.item_code,
                    unit=item.stock_unit or item.default_unit,
                    opening_qty=log.opening_qty,
                    purchased_qty=log.purchased_qty,
                    used_qty=log.used_qty,
                    closing_qty=log.closing_qty,
                    logged=True,
                )
            )
        else:
            opening = cur - p
            if opening < 0:
                opening = Decimal("0")
            lines.append(
                UsageLineOut(
                    item_id=item.id,
                    item_name=item.name,
                    item_code=item.item_code,
                    unit=item.stock_unit or item.default_unit,
                    opening_qty=opening,
                    purchased_qty=p,
                    used_qty=Decimal("0"),
                    closing_qty=opening + p,
                    logged=False,
                )
            )
            missing += 1
    return UsageTodayOut(usage_date=today, lines=lines, missing_count=missing)


@router.post("/usage/today", response_model=UsageSummaryOut)
async def usage_submit(
    business_id: uuid.UUID,
    body: UsageSubmitIn,
    db: Annotated[AsyncSession, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
    _m: Annotated[Membership, Depends(require_permission("stock_edit"))],
):
    del _m
    today = date.today()
    display = user.name or user.username or user.email
    total_used = Decimal("0")
    logged = 0
    for line in body.lines:
        r = await db.execute(
            select(CatalogItem).where(
                CatalogItem.id == line.item_id,
                CatalogItem.business_id == business_id,
                CatalogItem.deleted_at.is_(None),
            )
        )
        item = r.scalar_one_or_none()
        if not item:
            raise HTTPException(status_code=404, detail="Item not found")
        purchased_map = await _purchased_today_map(db, business_id, [item.id], today)
        p = purchased_map.get(item.id, Decimal("0"))
        cur = catalog_stock_qty(item)
        opening = cur - p
        if opening < 0:
            opening = Decimal("0")
        max_use = opening + p
        if line.used_qty > max_use:
            raise HTTPException(
                status_code=400,
                detail=f"Used qty exceeds available for {item.name}",
            )
        closing = opening + p - line.used_qty
        ex = await db.execute(
            select(DailyUsageLog).where(
                DailyUsageLog.business_id == business_id,
                DailyUsageLog.item_id == item.id,
                DailyUsageLog.usage_date == today,
            )
        )
        log = ex.scalar_one_or_none()
        if log:
            log.used_qty = line.used_qty
            log.closing_qty = closing
            log.opening_qty = opening
            log.purchased_qty = p
            log.notes = line.notes
        else:
            db.add(
                DailyUsageLog(
                    business_id=business_id,
                    item_id=item.id,
                    usage_date=today,
                    opening_qty=opening,
                    purchased_qty=p,
                    used_qty=line.used_qty,
                    closing_qty=closing,
                    logged_by_user_id=user.id,
                    notes=line.notes,
                )
            )
        old_qty = cur
        if closing != old_qty:
            db.add(
                StockAdjustmentLog(
                    business_id=business_id,
                    item_id=item.id,
                    old_qty=old_qty,
                    new_qty=closing,
                    adjustment_type="manual",
                    reason="Daily usage log",
                    updated_by=user.id,
                    updated_by_name=display,
                )
            )
            item.current_stock = closing
            item.last_stock_updated_at = datetime.now(timezone.utc)
            item.last_stock_updated_by = display
        total_used += line.used_qty
        logged += 1
    await log_staff_activity(
        db,
        business_id=business_id,
        user=user,
        action_type="USAGE_LOG",
        details={"items": logged, "date": today.isoformat()},
    )
    await db.commit()
    ir = await db.execute(
        select(func.count())
        .select_from(CatalogItem)
        .where(
            CatalogItem.business_id == business_id,
            CatalogItem.deleted_at.is_(None),
            CatalogItem.current_stock > 0,
        )
    )
    active = int(ir.scalar_one() or 0)
    return UsageSummaryOut(
        usage_date=today,
        items_logged=logged,
        items_missing=max(0, active - logged),
        total_used_qty=total_used,
    )


@router.get("/checklist/templates", response_model=list[ChecklistTemplateOut])
async def list_checklist_templates(
    business_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
):
    del _m
    templates = await _templates_for_business(db, business_id)
    return [
        ChecklistTemplateOut(
            id=t.id,
            slot=t.slot,
            task_key=t.task_key,
            label=t.label,
            sort_order=t.sort_order,
        )
        for t in templates
    ]


@router.put("/checklist/templates", response_model=list[ChecklistTemplateOut])
async def replace_checklist_templates(
    business_id: uuid.UUID,
    body: Annotated[ChecklistTemplatesPutIn, Body()],
    db: Annotated[AsyncSession, Depends(get_db)],
    membership: Annotated[Membership, Depends(require_membership)],
):
    """Owner/manager: replace daily task list (morning / midday / evening)."""
    if membership.role not in ("owner", "admin", "manager"):
        raise HTTPException(
            status.HTTP_403_FORBIDDEN,
            detail="Owner, admin, or manager required to edit tasks",
        )
    seen_keys: set[tuple[str, str]] = set()
    rows: list[StaffChecklistTemplate] = []
    for i, item in enumerate(body.tasks):
        slot = item.slot
        key = (item.task_key or "").strip() or _slug_task_key(item.label, f"task_{i + 1}")
        pair = (slot, key)
        if pair in seen_keys:
            key = f"{key}_{i + 1}"[:64]
            pair = (slot, key)
        seen_keys.add(pair)
        rows.append(
            StaffChecklistTemplate(
                business_id=business_id,
                slot=slot,
                task_key=key,
                label=item.label.strip(),
                sort_order=item.sort_order if item.sort_order else i + 1,
            )
        )
    await db.execute(
        delete(StaffChecklistTemplate).where(
            StaffChecklistTemplate.business_id == business_id
        )
    )
    for row in rows:
        db.add(row)
    await db.commit()
    for row in rows:
        await db.refresh(row)
    return [
        ChecklistTemplateOut(
            id=t.id,
            slot=t.slot,
            task_key=t.task_key,
            label=t.label,
            sort_order=t.sort_order,
        )
        for t in rows
    ]


@router.get("/checklist/summary", response_model=ChecklistSummaryOut)
async def checklist_summary(
    business_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
):
    """Business-wide checklist completion for today (all staff tasks)."""
    today = date.today()
    templates = await _templates_for_business(db, business_id)
    total = len(templates)
    cr = await db.execute(
        select(func.count(func.distinct(StaffChecklistCompletion.task_key))).where(
            StaffChecklistCompletion.business_id == business_id,
            StaffChecklistCompletion.checklist_date == today,
        )
    )
    done = int(cr.scalar_one() or 0)
    pct = (done / total * 100) if total else 0.0
    return ChecklistSummaryOut(
        checklist_date=today,
        completion_pct=round(pct, 1),
        tasks_total=total,
        tasks_completed=done,
    )


@router.post("/snapshots/materialize")
async def materialize_daily_snapshots(
    business_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
    _m: Annotated[Membership, Depends(require_membership)],
    snapshot_date: str | None = None,
):
    """Ensure daily_usage_logs rows exist for active items (opening from prior close)."""
    try:
        ud = date.fromisoformat((snapshot_date or date.today().isoformat())[:10])
    except ValueError:
        ud = date.today()
    prior = ud - timedelta(days=1)
    ir = await db.execute(
        select(CatalogItem).where(
            CatalogItem.business_id == business_id,
            CatalogItem.deleted_at.is_(None),
            CatalogItem.current_stock > 0,
        )
    )
    items = list(ir.scalars().all())
    created = 0
    for item in items:
        ex = await db.execute(
            select(DailyUsageLog).where(
                DailyUsageLog.business_id == business_id,
                DailyUsageLog.item_id == item.id,
                DailyUsageLog.usage_date == ud,
            )
        )
        if ex.scalar_one_or_none():
            continue
        prior_r = await db.execute(
            select(DailyUsageLog).where(
                DailyUsageLog.business_id == business_id,
                DailyUsageLog.item_id == item.id,
                DailyUsageLog.usage_date == prior,
            )
        )
        prior_log = prior_r.scalar_one_or_none()
        cur = catalog_stock_qty(item)
        purchased_map = await _purchased_today_map(db, business_id, [item.id], ud)
        p = purchased_map.get(item.id, Decimal("0"))
        opening = prior_log.closing_qty if prior_log else (cur - p)
        if opening < 0:
            opening = Decimal("0")
        closing = opening + p
        db.add(
            DailyUsageLog(
                business_id=business_id,
                item_id=item.id,
                usage_date=ud,
                opening_qty=opening,
                purchased_qty=p,
                used_qty=Decimal("0"),
                closing_qty=closing,
                logged_by_user_id=user.id,
            )
        )
        created += 1
    await db.commit()
    return {"usage_date": ud.isoformat(), "rows_created": created}


@router.get("/snapshots", response_model=list[DailySnapshotOut])
async def list_daily_snapshots(
    business_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
    from_date: str | None = None,
    to_date: str | None = None,
    item_id: uuid.UUID | None = None,
):
    today = date.today()
    try:
        fd = date.fromisoformat((from_date or today.isoformat())[:10])
        td = date.fromisoformat((to_date or today.isoformat())[:10])
    except ValueError:
        fd = td = today
    stmt = (
        select(DailyUsageLog, CatalogItem.name)
        .join(CatalogItem, DailyUsageLog.item_id == CatalogItem.id)
        .where(
            DailyUsageLog.business_id == business_id,
            DailyUsageLog.usage_date >= fd,
            DailyUsageLog.usage_date <= td,
        )
        .order_by(DailyUsageLog.usage_date.desc(), CatalogItem.name)
    )
    if item_id is not None:
        stmt = stmt.where(DailyUsageLog.item_id == item_id)
    r = await db.execute(stmt.limit(500))
    return [
        DailySnapshotOut(
            item_id=log.item_id,
            item_name=nm,
            usage_date=log.usage_date,
            opening_qty=log.opening_qty,
            purchased_qty=log.purchased_qty,
            used_qty=log.used_qty,
            closing_qty=log.closing_qty,
        )
        for log, nm in r.all()
    ]


@router.get("/usage/summary", response_model=UsageSummaryOut)
async def usage_summary(
    business_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
    usage_date: str | None = None,
):
    try:
        ud = date.fromisoformat((usage_date or date.today().isoformat())[:10])
    except ValueError:
        ud = date.today()
    lr = await db.execute(
        select(func.count(DailyUsageLog.id), func.coalesce(func.sum(DailyUsageLog.used_qty), 0)).where(
            DailyUsageLog.business_id == business_id,
            DailyUsageLog.usage_date == ud,
        )
    )
    row = lr.one()
    logged = int(row[0] or 0)
    ir = await db.execute(
        select(func.count())
        .select_from(CatalogItem)
        .where(
            CatalogItem.business_id == business_id,
            CatalogItem.deleted_at.is_(None),
            CatalogItem.current_stock > 0,
        )
    )
    active = int(ir.scalar_one() or 0)
    return UsageSummaryOut(
        usage_date=ud,
        items_logged=logged,
        items_missing=max(0, active - logged),
        total_used_qty=Decimal(row[1] or 0),
    )


@router.get("/reports/summary")
async def operational_reports_summary(
    business_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
    stale_days: int = 30,
):
    """Dead / fast / slow stock and supplier frequency (operational, no financials)."""
    today = date.today()
    ir = await db.execute(
        select(CatalogItem, ItemCategory.name)
        .join(ItemCategory, CatalogItem.category_id == ItemCategory.id)
        .where(
            CatalogItem.business_id == business_id,
            CatalogItem.deleted_at.is_(None),
        )
    )
    rows = ir.all()
    item_ids = [item.id for item, _ in rows]
    usage_7d: dict[uuid.UUID, Decimal] = {}
    last_adj: dict[uuid.UUID, datetime] = {}
    if item_ids:
        from datetime import timedelta

        since = today - timedelta(days=7)
        ur = await db.execute(
            select(DailyUsageLog.item_id, func.coalesce(func.sum(DailyUsageLog.used_qty), 0))
            .where(
                DailyUsageLog.business_id == business_id,
                DailyUsageLog.usage_date >= since,
                DailyUsageLog.item_id.in_(item_ids),
            )
            .group_by(DailyUsageLog.item_id)
        )
        usage_7d = {row[0]: Decimal(row[1] or 0) for row in ur.all()}
        adj_r = await db.execute(
            select(
                StockAdjustmentLog.item_id,
                func.max(StockAdjustmentLog.updated_at),
            )
            .where(
                StockAdjustmentLog.business_id == business_id,
                StockAdjustmentLog.item_id.in_(item_ids),
            )
            .group_by(StockAdjustmentLog.item_id)
        )
        last_adj = {row[0]: row[1] for row in adj_r.all() if row[1] is not None}
    dead: list[dict] = []
    fast: list[dict] = []
    slow: list[dict] = []
    for item, cat_name in rows:
        cur = catalog_stock_qty(item)
        u = usage_7d.get(item.id, Decimal("0"))
        idle_days = _idle_days_for_item(item, last_adj.get(item.id), u)
        bucket, insight = _aging_bucket(idle_days, cur, u)
        entry = {
            "id": str(item.id),
            "name": item.name,
            "item_code": item.item_code,
            "category": cat_name,
            "unit": item.stock_unit or item.default_unit,
            "current_stock": float(cur),
            "used_7d": float(u),
            "last_movement_at": (
                last_adj[item.id].isoformat() if item.id in last_adj else None
            ),
            "idle_days": idle_days,
            "aging_bucket": bucket,
            "insight_key": insight,
        }
        if cur > 0 and u <= 0:
            days = _days_since_last_purchase_ops(item)
            if days is None or days >= stale_days:
                dead.append(entry)
        if u > 0:
            fast.append(entry)
        elif cur > 0:
            slow.append(entry)
    fast.sort(key=lambda x: x["used_7d"], reverse=True)
    slow.sort(key=lambda x: x["current_stock"], reverse=True)
    sr = await db.execute(
        select(TradePurchase.supplier_id, func.count())
        .where(
            TradePurchase.business_id == business_id,
            TradePurchase.status != "cancelled",
            TradePurchase.purchase_date >= today.replace(day=1),
        )
        .group_by(TradePurchase.supplier_id)
        .order_by(func.count().desc())
        .limit(20)
    )
    supplier_freq = [
        {"supplier_id": str(row[0]) if row[0] else None, "purchase_count": int(row[1] or 0)}
        for row in sr.all()
    ]
    return {
        "dead_stock": dead[:50],
        "fast_moving": fast[:30],
        "slow_moving": slow[:30],
        "supplier_frequency": supplier_freq,
    }


def _days_since_last_purchase_ops(item: CatalogItem) -> int | None:
    if not item.last_purchase_at:
        return None
    delta = datetime.now(timezone.utc) - item.last_purchase_at
    return max(0, delta.days)


def _idle_days_for_item(
    item: CatalogItem,
    last_adj_at: datetime | None,
    used_7d: Decimal,
) -> int:
    now = datetime.now(timezone.utc)
    candidates: list[datetime] = []
    if last_adj_at is not None:
        candidates.append(last_adj_at)
    if item.last_purchase_at is not None:
        candidates.append(item.last_purchase_at)
    if used_7d > 0:
        return 0
    if not candidates:
        return 999
    latest = max(candidates)
    if latest.tzinfo is None:
        latest = latest.replace(tzinfo=timezone.utc)
    return max(0, (now - latest).days)


def _aging_bucket(idle_days: int, current_stock: Decimal, used_7d: Decimal) -> tuple[str, str]:
    if current_stock <= 0:
        return "out", "out_of_stock"
    if used_7d > 0 and idle_days <= 7:
        return "healthy", "active"
    if idle_days >= 60:
        return "60d", "dead_stock_risk"
    if idle_days >= 30:
        return "30d", "high_stock_low_usage"
    if idle_days >= 15:
        return "15d", "slowing"
    if idle_days >= 7:
        return "7d", "slowing"
    return "healthy", "active"
