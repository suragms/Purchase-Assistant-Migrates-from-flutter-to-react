import uuid
from collections import defaultdict
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


def _qty_by_catalog_item(lines: list) -> dict[uuid.UUID, Decimal]:
    """Sum line qty per catalog_item_id (ORM lines or pydantic line bodies)."""
    totals: dict[uuid.UUID, Decimal] = defaultdict(lambda: Decimal(0))
    for li in lines:
        cid = getattr(li, "catalog_item_id", None)
        if cid is None:
            continue
        qty = Decimal(getattr(li, "qty", 0) or 0)
        if qty <= 0:
            continue
        totals[uuid.UUID(str(cid))] += qty
    return dict(totals)


async def _apply_catalog_stock_deltas(
    db: AsyncSession,
    business_id: uuid.UUID,
    user_id: uuid.UUID,
    deltas: dict[uuid.UUID, Decimal],
    *,
    reason: str,
    adjustment_type: str = "purchase",
    touch_last_purchase_at: bool = False,
) -> list[dict]:
    """Apply signed qty deltas; rejects if on-hand would go negative."""
    if not deltas:
        return []
    ur = await db.execute(select(User).where(User.id == user_id))
    user = ur.scalar_one_or_none()
    display = (user.name or user.username or user.email) if user else "System"
    updates: list[dict] = []
    for cid, delta in deltas.items():
        if delta == 0:
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
        new_qty = old_qty + delta
        if new_qty < 0:
            raise ValueError(
                f"Stock cannot be negative for {item.name or item.id} "
                f"(on hand {old_qty}, adjustment {delta})"
            )
        unit = item.stock_unit or item.default_unit or item.selling_unit
        db.add(
            StockAdjustmentLog(
                business_id=business_id,
                item_id=item.id,
                old_qty=old_qty,
                new_qty=new_qty,
                adjustment_type=adjustment_type,
                reason=reason,
                updated_by=user_id,
                updated_by_name=display,
            )
        )
        item.current_stock = new_qty
        item.last_stock_updated_at = datetime.now(timezone.utc)
        item.last_stock_updated_by = display
        if touch_last_purchase_at and delta > 0:
            item.last_purchase_at = datetime.now(timezone.utc)
        updates.append(
            {
                "catalog_item_id": item.id,
                "name": item.name,
                "unit": unit,
                "old_qty": old_qty,
                "new_qty": new_qty,
                "delta": delta,
            }
        )
    return updates


async def apply_confirmed_purchase_stock(
    db: AsyncSession,
    business_id: uuid.UUID,
    user_id: uuid.UUID,
    lines: list,
    *,
    purchase_human_id: str | None = None,
) -> list[dict]:
    """Increment catalog stock when a purchase is confirmed; return per-line updates for API."""
    reason = f"Purchase received{f' ({purchase_human_id})' if purchase_human_id else ''}"
    return await _apply_catalog_stock_deltas(
        db,
        business_id,
        user_id,
        _qty_by_catalog_item(lines),
        reason=reason,
        adjustment_type="purchase",
        touch_last_purchase_at=True,
    )


async def revert_confirmed_purchase_stock(
    db: AsyncSession,
    business_id: uuid.UUID,
    user_id: uuid.UUID,
    lines: list,
    *,
    purchase_human_id: str | None = None,
) -> list[dict]:
    """Decrement stock for a previously confirmed purchase (cancel/delete/unconfirm)."""
    by_item = _qty_by_catalog_item(lines)
    if not by_item:
        return []
    deltas = {cid: -qty for cid, qty in by_item.items()}
    reason = f"Purchase reversed{f' ({purchase_human_id})' if purchase_human_id else ''}"
    return await _apply_catalog_stock_deltas(
        db,
        business_id,
        user_id,
        deltas,
        reason=reason,
        adjustment_type="purchase_reversal",
        touch_last_purchase_at=False,
    )


async def sync_confirmed_purchase_stock_diff(
    db: AsyncSession,
    business_id: uuid.UUID,
    user_id: uuid.UUID,
    old_lines: list,
    new_lines: list,
    *,
    purchase_human_id: str | None = None,
) -> list[dict]:
    """Apply qty delta when editing an already-confirmed purchase."""
    old_map = _qty_by_catalog_item(old_lines)
    new_map = _qty_by_catalog_item(new_lines)
    all_ids = set(old_map) | set(new_map)
    deltas: dict[uuid.UUID, Decimal] = {}
    for cid in all_ids:
        delta = new_map.get(cid, Decimal(0)) - old_map.get(cid, Decimal(0))
        if delta != 0:
            deltas[cid] = delta
    if not deltas:
        return []
    reason = f"Purchase adjusted{f' ({purchase_human_id})' if purchase_human_id else ''}"
    return await _apply_catalog_stock_deltas(
        db,
        business_id,
        user_id,
        deltas,
        reason=reason,
        adjustment_type="purchase_adjustment",
        touch_last_purchase_at=any(d > 0 for d in deltas.values()),
    )
