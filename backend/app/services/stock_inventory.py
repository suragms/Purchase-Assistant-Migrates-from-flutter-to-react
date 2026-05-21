import uuid
from datetime import datetime, timezone
from decimal import Decimal

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import CatalogItem, User
from app.models.stock_adjustment import StockAdjustmentLog


def stock_status(current: Decimal | None, reorder: Decimal | None) -> str:
    cur = Decimal(current or 0)
    ro = Decimal(reorder or 0)
    if cur <= 0:
        return "out"
    if ro > 0:
        if cur <= ro * Decimal("0.5"):
            return "critical"
        if cur < ro:
            return "low"
    return "healthy"


def catalog_stock_qty(item: CatalogItem) -> Decimal:
    return Decimal(item.current_stock or 0)


def catalog_reorder(item: CatalogItem) -> Decimal:
    return Decimal(item.reorder_level or 0)


def catalog_landing_rate(item: CatalogItem) -> Decimal:
    """Valuation rate for on-hand stock: landing cost only (never selling)."""
    for raw in (item.default_landing_cost, item.last_purchase_price):
        if raw is not None:
            rate = Decimal(raw)
            if rate > 0:
                return rate
    return Decimal(0)


def catalog_unit_key(item: CatalogItem) -> str:
    """Bucket on-hand qty into bags | boxes | tins | kg for dashboard totals."""
    unit = (
        (item.stock_unit or item.default_unit or item.selling_unit or "") or ""
    ).strip().lower()
    if "bag" in unit:
        return "bags"
    if "box" in unit:
        return "boxes"
    if "tin" in unit:
        return "tins"
    return "kg"


async def compute_inventory_summary(
    db: AsyncSession,
    business_id: uuid.UUID,
) -> dict[str, float | int]:
    """
    Point-in-time warehouse totals: sum(current_stock * landing rate) and unit buckets.
    Items without a landing rate still count toward unit buckets but not total_value_inr.
    """
    r = await db.execute(
        select(CatalogItem).where(
            CatalogItem.business_id == business_id,
            CatalogItem.deleted_at.is_(None),
        )
    )
    items = list(r.scalars().all())
    bags = boxes = tins = kg = Decimal(0)
    total_value = Decimal(0)
    for item in items:
        qty = catalog_stock_qty(item)
        if qty <= 0:
            continue
        bucket = catalog_unit_key(item)
        if bucket == "bags":
            bags += qty
        elif bucket == "boxes":
            boxes += qty
        elif bucket == "tins":
            tins += qty
        else:
            kg += qty
        rate = catalog_landing_rate(item)
        if rate > 0:
            total_value += qty * rate
    return {
        "total_value_inr": float(total_value),
        "bags": float(bags),
        "boxes": float(boxes),
        "tins": float(tins),
        "kg": float(kg),
        "item_count": len(items),
    }


async def apply_confirmed_purchase_stock(
    db: AsyncSession,
    business_id: uuid.UUID,
    user_id: uuid.UUID,
    lines: list,
    *,
    purchase_human_id: str | None = None,
) -> list[dict]:
    """Increment catalog stock when a purchase is confirmed; return per-line updates for API."""
    ur = await db.execute(select(User).where(User.id == user_id))
    user = ur.scalar_one_or_none()
    display = (user.name or user.username or user.email) if user else "System"
    reason = f"Purchase received{f' ({purchase_human_id})' if purchase_human_id else ''}"
    updates: list[dict] = []

    for li in lines:
        cid = getattr(li, "catalog_item_id", None)
        if cid is None:
            continue
        qty = Decimal(getattr(li, "qty", 0) or 0)
        if qty <= 0:
            continue
        r = await db.execute(
            select(CatalogItem).where(
                CatalogItem.id == cid,
                CatalogItem.business_id == business_id,
                CatalogItem.deleted_at.is_(None),
            )
        )
        item = r.scalar_one_or_none()
        if not item:
            continue
        old_qty = catalog_stock_qty(item)
        new_qty = old_qty + qty
        unit = item.stock_unit or item.default_unit or item.selling_unit
        db.add(
            StockAdjustmentLog(
                business_id=business_id,
                item_id=item.id,
                old_qty=old_qty,
                new_qty=new_qty,
                adjustment_type="purchase",
                reason=reason,
                updated_by=user_id,
                updated_by_name=display,
            )
        )
        item.current_stock = new_qty
        item.last_stock_updated_at = datetime.now(timezone.utc)
        item.last_stock_updated_by = display
        updates.append(
            {
                "catalog_item_id": item.id,
                "name": item.name,
                "unit": unit,
                "old_qty": old_qty,
                "new_qty": new_qty,
                "delta": qty,
            }
        )
    return updates
