"""Notify owners when physical stock count diverges from post-purchase expectation."""

from __future__ import annotations

import uuid
from datetime import datetime, timezone
from decimal import Decimal

from sqlalchemy import desc, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import CatalogItem
from app.models.stock_adjustment import StockAdjustmentLog
from app.services.notification_emitter import (
    CATEGORY_STAFF,
    CATEGORY_WAREHOUSE,
    PRIORITY_CRITICAL,
    PRIORITY_HIGH,
    emit_notification,
)

_VARIANCE_MIN_UNITS = Decimal("2")
_VARIANCE_MIN_RATIO = Decimal("0.02")


async def _last_purchase_expected_qty(
    db: AsyncSession, business_id: uuid.UUID, item_id: uuid.UUID
) -> Decimal | None:
    r = await db.execute(
        select(StockAdjustmentLog.new_qty)
        .where(
            StockAdjustmentLog.business_id == business_id,
            StockAdjustmentLog.item_id == item_id,
            StockAdjustmentLog.adjustment_type == "purchase",
        )
        .order_by(desc(StockAdjustmentLog.updated_at))
        .limit(1)
    )
    row = r.scalar_one_or_none()
    return Decimal(row) if row is not None else None


def _is_material_variance(expected: Decimal, found: Decimal) -> bool:
    delta = abs(found - expected)
    if delta < _VARIANCE_MIN_UNITS:
        if expected > 0 and (delta / expected) >= _VARIANCE_MIN_RATIO:
            return True
        return False
    return True


async def maybe_notify_stock_variance(
    db: AsyncSession,
    *,
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    adjustment_type: str,
    new_qty: Decimal,
    triggered_by_user_id: uuid.UUID | None = None,
) -> tuple[Decimal | None, Decimal | None]:
    """If verification/correction diverges from last purchase qty, queue notifications."""
    if adjustment_type not in ("verification", "correction", "manual"):
        return None, None
    expected = await _last_purchase_expected_qty(db, business_id, item_id)
    if expected is None:
        return None, None
    if not _is_material_variance(expected, new_qty):
        return None, None

    delta = new_qty - expected
    ir = await db.execute(
        select(CatalogItem).where(
            CatalogItem.id == item_id,
            CatalogItem.business_id == business_id,
        )
    )
    item = ir.scalar_one_or_none()
    if not item:
        return None, None

    unit = item.stock_unit or item.default_unit or ""
    day = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    await emit_notification(
        db,
        business_id=business_id,
        kind="stock_variance",
        title="Stock mismatch detected",
        body=(
            f"{item.name}: expected {_fmt(expected)} {unit}, "
            f"found {_fmt(new_qty)} {unit} ({_fmt(delta)} diff)"
        ),
        priority=PRIORITY_CRITICAL,
        category=CATEGORY_WAREHOUSE,
        dedupe_key=f"stock_variance:{item_id}:{day}",
        action_route=f"/catalog/item/{item_id}",
        triggered_by_user_id=triggered_by_user_id,
        related_item_id=item_id,
        payload={
            "item_id": str(item_id),
            "item_name": item.name,
            "expected_qty": float(expected),
            "found_qty": float(new_qty),
            "variance_delta": float(delta),
            "unit": unit,
        },
        owner_only=False,
    )
    return expected, delta


def _fmt(v: Decimal) -> str:
    if v == v.to_integral_value():
        return str(int(v))
    return f"{v:.2f}"


async def maybe_notify_staff_system_stock_edit(
    db: AsyncSession,
    *,
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    item_name: str,
    unit: str,
    old_qty: Decimal,
    new_qty: Decimal,
    actor_user_id: uuid.UUID,
    actor_display: str,
    actor_role: str,
) -> None:
    """Alert owners when floor staff change ledger system stock."""
    role = (actor_role or "").strip().lower()
    if role in ("owner", "admin", "manager", "super_admin"):
        return
    if abs(new_qty - old_qty) < Decimal("0.001"):
        return
    day = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    u = (unit or "").strip()
    await emit_notification(
        db,
        business_id=business_id,
        kind="staff_system_stock_edit",
        title="Staff updated system stock",
        body=(
            f"{actor_display} set {item_name} "
            f"from {_fmt(old_qty)} to {_fmt(new_qty)}"
            f"{f' {u}' if u else ''}"
        ),
        priority=PRIORITY_HIGH,
        category=CATEGORY_STAFF,
        dedupe_key=f"staff_system_stock:{item_id}:{actor_user_id}:{day}",
        action_route=f"/catalog/item/{item_id}",
        triggered_by_user_id=actor_user_id,
        related_item_id=item_id,
        owner_only=True,
        payload={
            "item_id": str(item_id),
            "item_name": item_name,
            "old_qty": float(old_qty),
            "new_qty": float(new_qty),
            "unit": u,
            "from_user_name": actor_display,
        },
    )
