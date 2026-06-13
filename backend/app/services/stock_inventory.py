import uuid
from collections import defaultdict
from datetime import datetime, timezone
from decimal import Decimal
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import CatalogItem, User
from app.models.stock_adjustment import StockAdjustmentLog
from app.models.stock_movement import StockMovement
from app.services.unit_normalization import (
    catalog_stock_unit,
    fetch_catalog_items_map,
    line_qty_in_stock_unit,
)


def stock_status(current: Decimal | None, reorder: Decimal | None) -> str:
    cur = Decimal(current or 0)
    ro = Decimal(reorder or 0)
    if cur <= 0:
        return "out"
    if ro <= 0 and Decimal("0") < cur < Decimal("1"):
        return "low"
    if ro > 0:
        if cur <= ro * Decimal("0.5"):
            return "critical"
        if cur <= ro:
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


async def committed_purchase_delivered_qty_map(
    db: AsyncSession,
    business_id: uuid.UUID,
    item_ids: list[uuid.UUID],
) -> dict[uuid.UUID, Decimal]:
    """Sum qty from stock_committed purchase lines (stock unit), for legacy DBs without movements."""
    if not item_ids:
        return {}
    from app.models.trade_purchase import TradePurchase, TradePurchaseLine

    r = await db.execute(
        select(TradePurchaseLine, CatalogItem)
        .join(TradePurchase, TradePurchaseLine.trade_purchase_id == TradePurchase.id)
        .join(CatalogItem, TradePurchaseLine.catalog_item_id == CatalogItem.id)
        .where(
            TradePurchase.business_id == business_id,
            TradePurchase.status.notin_(("cancelled", "deleted")),
            TradePurchase.delivery_status == "stock_committed",
            TradePurchaseLine.catalog_item_id.in_(item_ids),
            CatalogItem.business_id == business_id,
            CatalogItem.deleted_at.is_(None),
        )
    )
    totals: dict[uuid.UUID, Decimal] = defaultdict(lambda: Decimal(0))
    for line, cat_item in r.all():
        cid = line.catalog_item_id
        if cid is None:
            continue
        qty = line_qty_for_stock_commit(line, cat_item)
        if qty > 0:
            totals[cid] += qty
    return dict(totals)


async def movement_delivered_qty_map(
    db: AsyncSession,
    business_id: uuid.UUID,
    item_ids: list[uuid.UUID],
) -> dict[uuid.UUID, Decimal]:
    """Lifetime qty added via committed PO deliveries (movements + legacy committed lines)."""
    movement = await movement_qty_map_by_kind(
        db,
        business_id,
        item_ids,
        kinds=("delivery_receive",),
    )
    committed = await committed_purchase_delivered_qty_map(db, business_id, item_ids)
    out: dict[uuid.UUID, Decimal] = {}
    for cid in set(movement) | set(committed):
        m = movement.get(cid, Decimal(0))
        c = committed.get(cid, Decimal(0))
        out[cid] = m if m >= c else c
    return out


async def movement_qty_map_by_kind(
    db: AsyncSession,
    business_id: uuid.UUID,
    item_ids: list[uuid.UUID],
    *,
    kinds: tuple[str, ...],
) -> dict[uuid.UUID, Decimal]:
    if not item_ids or not kinds:
        return {}
    r = await db.execute(
        select(
            StockMovement.item_id,
            func.coalesce(func.sum(StockMovement.delta_qty), 0),
        )
        .where(
            StockMovement.business_id == business_id,
            StockMovement.item_id.in_(item_ids),
            StockMovement.movement_kind.in_(kinds),
        )
        .group_by(StockMovement.item_id)
    )
    return {row[0]: Decimal(row[1] or 0) for row in r.all()}


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


def line_qty_for_stock_commit(line: Any, item: CatalogItem) -> Decimal:
    """Qty to add on delivery commit — uses staff [received_qty] when set."""
    recv = getattr(line, "received_qty", None)
    if recv is not None:
        recv_d = Decimal(str(recv))
        if recv_d <= 0:
            return Decimal(0)
        ordered_d = Decimal(getattr(line, "qty", 0) or 0)
        snap = getattr(line, "qty_in_stock_unit", None)
        if snap is not None and ordered_d > 0:
            from decimal import ROUND_HALF_UP

            snap_d = Decimal(str(snap))
            if snap_d > 0:
                return (snap_d * recv_d / ordered_d).quantize(
                    Decimal("0.001"), rounding=ROUND_HALF_UP
                )
        class _RecvLine:
            pass

        proxy = _RecvLine()
        proxy.qty = recv_d
        for attr in (
            "unit",
            "item_name",
            "kg_per_unit",
            "weight_per_unit",
            "total_weight",
            "qty_in_stock_unit",
        ):
            setattr(proxy, attr, getattr(line, attr, None))
        return line_qty_in_stock_unit(proxy, item)
    return line_qty_in_stock_unit(line, item)


async def _qty_by_catalog_item(
    db: AsyncSession,
    business_id: uuid.UUID,
    lines: list,
) -> dict[uuid.UUID, Decimal]:
    """Sum normalized line qty per catalog_item_id (stock unit)."""
    totals, _ = await _qty_by_catalog_item_with_skips(db, business_id, lines)
    return totals


async def _qty_by_catalog_item_with_skips(
    db: AsyncSession,
    business_id: uuid.UUID,
    lines: list,
) -> tuple[dict[uuid.UUID, Decimal], list[dict[str, Any]]]:
    totals: dict[uuid.UUID, Decimal] = defaultdict(lambda: Decimal(0))
    skipped: list[dict[str, Any]] = []
    item_ids: set[uuid.UUID] = set()
    for li in lines:
        cid = getattr(li, "catalog_item_id", None)
        if cid is not None:
            item_ids.add(uuid.UUID(str(cid)))
    items = await fetch_catalog_items_map(db, business_id, item_ids)
    for li in lines:
        cid = getattr(li, "catalog_item_id", None)
        if cid is None:
            continue
        cid_u = uuid.UUID(str(cid))
        item = items.get(cid_u)
        if not item:
            continue
        raw_qty = Decimal(getattr(li, "received_qty", None) or getattr(li, "qty", 0) or 0)
        qty = line_qty_for_stock_commit(li, item)
        if raw_qty > 0 and qty <= 0:
            skipped.append(
                {
                    "catalog_item_id": cid_u,
                    "name": item.name,
                    "unit": catalog_stock_unit(item),
                    "line_unit": getattr(li, "unit", None),
                    "needs_unit_setup": True,
                    "old_qty": catalog_stock_qty(item),
                    "new_qty": catalog_stock_qty(item),
                    "delta": Decimal(0),
                }
            )
            continue
        if qty <= 0:
            continue
        totals[cid_u] += qty
    return dict(totals), skipped


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


async def purchase_delivery_stock_already_applied(
    db: AsyncSession,
    business_id: uuid.UUID,
    purchase_id: uuid.UUID,
) -> bool:
    """True if stock was already incremented for this purchase (idempotent delivery).

    Checks stock_movements first; falls back to legacy adjustment_log rows.
    """
    marker = f"trade_purchase:{purchase_id}"
    r2 = await db.execute(
        select(func.count())
        .select_from(StockMovement)
        .where(
            StockMovement.business_id == business_id,
            StockMovement.idempotency_key.like(f"{marker}:%"),
        )
    )
    if int(r2.scalar_one() or 0) > 0:
        return True
    from app.models.trade_purchase import TradePurchase

    tp_r = await db.execute(
        select(TradePurchase.human_id).where(
            TradePurchase.id == purchase_id,
            TradePurchase.business_id == business_id,
        )
    )
    human = tp_r.scalar_one_or_none()
    if not human:
        return False
    label = str(human).strip()
    r3 = await db.execute(
        select(func.count())
        .select_from(StockAdjustmentLog)
        .where(
            StockAdjustmentLog.business_id == business_id,
            StockAdjustmentLog.adjustment_type == "purchase",
            StockAdjustmentLog.reason.ilike(f"%{label}%"),
        )
    )
    return int(r3.scalar_one() or 0) > 0


async def apply_confirmed_purchase_stock(
    db: AsyncSession,
    business_id: uuid.UUID,
    user_id: uuid.UUID,
    lines: list,
    *,
    purchase_human_id: str | None = None,
    purchase_id: uuid.UUID | None = None,
    actor: User | None = None,
) -> list[dict]:
    """Increment catalog stock when a purchase delivery is committed."""
    if purchase_id is None or actor is None:
        raise ValueError("purchase_id and actor are required for delivery commit")

    if await purchase_delivery_stock_already_applied(db, business_id, purchase_id):
        return []

    by_item, skipped = await _qty_by_catalog_item_with_skips(db, business_id, lines)
    if not by_item and not skipped:
        return list(skipped)

    label = purchase_human_id or str(purchase_id)
    reason = f"Purchase received ({label})".strip()

    from app.services.stock_movement_service import apply_stock_movement_with_retry

    updates: list[dict] = list(skipped)
    for cid, delta in by_item.items():
        if delta <= 0:
            continue
        idem = f"trade_purchase:{purchase_id}:{cid}"
        result = await apply_stock_movement_with_retry(
            db,
            business_id=business_id,
            item_id=cid,
            user=actor,
            movement_kind="delivery_receive",
            mode="delta",
            qty=delta,
            reason=reason,
            source_type="trade_purchase",
            source_id=purchase_id,
            idempotency_key=idem,
            metadata={"purchase_id": str(purchase_id), "human_id": label},
        )
        item = result.item
        unit = item.stock_unit or item.default_unit or item.selling_unit
        if result.duplicate:
            continue
        if delta > 0:
            item.last_purchase_at = datetime.now(timezone.utc)
        updates.append(
            {
                "catalog_item_id": item.id,
                "name": item.name,
                "unit": unit,
                "old_qty": result.movement.qty_before,
                "new_qty": result.movement.qty_after,
                "delta": delta,
                "needs_unit_setup": False,
            }
        )
    return updates


async def revert_confirmed_purchase_stock(
    db: AsyncSession,
    business_id: uuid.UUID,
    user_id: uuid.UUID,
    lines: list,
    *,
    purchase_human_id: str | None = None,
    purchase_id: uuid.UUID | None = None,
    actor: User | None = None,
) -> list[dict]:
    """Decrement stock for a previously delivered purchase via movement ledger."""
    if purchase_id is None:
        raise ValueError("purchase_id is required for stock reversal")
    if actor is None:
        ur = await db.execute(select(User).where(User.id == user_id))
        actor = ur.scalar_one_or_none()
    if actor is None:
        raise ValueError("actor user not found for stock reversal")

    by_item = await _qty_by_catalog_item(db, business_id, lines)
    if not by_item:
        return []

    from app.services.stock_movement_service import apply_stock_movement_with_retry

    label = purchase_human_id or str(purchase_id)
    reason = f"Purchase reversed ({label})".strip()
    updates: list[dict] = []
    for cid, qty in by_item.items():
        if qty <= 0:
            continue
        idem = f"revert:trade_purchase:{purchase_id}:{cid}"
        result = await apply_stock_movement_with_retry(
            db,
            business_id=business_id,
            item_id=cid,
            user=actor,
            movement_kind="delivery_revoke",
            mode="delta",
            qty=-qty,
            reason=reason,
            source_type="trade_purchase",
            source_id=purchase_id,
            idempotency_key=idem,
            metadata={"purchase_id": str(purchase_id), "human_id": label},
        )
        if result.duplicate:
            continue
        item = result.item
        unit = item.stock_unit or item.default_unit or item.selling_unit
        updates.append(
            {
                "catalog_item_id": item.id,
                "name": item.name,
                "unit": unit,
                "old_qty": result.movement.qty_before,
                "new_qty": result.movement.qty_after,
                "delta": -qty,
            }
        )
    return updates


async def sync_confirmed_purchase_stock_diff(
    db: AsyncSession,
    business_id: uuid.UUID,
    user_id: uuid.UUID,
    old_lines: list,
    new_lines: list,
    *,
    purchase_human_id: str | None = None,
    purchase_id: uuid.UUID | None = None,
    actor: User | None = None,
) -> list[dict]:
    """Apply qty delta when editing a stock-committed purchase.

    Uses ``line_qty_for_stock_commit`` (staff ``received_qty`` when set) per line.
    """
    old_map = await _qty_by_catalog_item(db, business_id, old_lines)
    new_map = await _qty_by_catalog_item(db, business_id, new_lines)
    all_ids = set(old_map) | set(new_map)
    deltas: dict[uuid.UUID, Decimal] = {}
    for cid in all_ids:
        delta = new_map.get(cid, Decimal(0)) - old_map.get(cid, Decimal(0))
        if delta != 0:
            deltas[cid] = delta
    if not deltas:
        return []
    if purchase_id is None:
        raise ValueError("purchase_id is required for committed purchase sync")
    if actor is None:
        ur = await db.execute(select(User).where(User.id == user_id))
        actor = ur.scalar_one_or_none()
    if actor is None:
        raise ValueError("actor user not found for purchase sync")

    from app.services.stock_movement_service import apply_stock_movement_with_retry

    label = purchase_human_id or str(purchase_id)
    reason = f"Purchase adjusted ({label})"
    updates: list[dict] = []
    for cid, delta in deltas.items():
        idem = f"adjust:trade_purchase:{purchase_id}:{cid}:{delta}"
        result = await apply_stock_movement_with_retry(
            db,
            business_id=business_id,
            item_id=cid,
            user=actor,
            movement_kind="delivery_adjustment",
            mode="delta",
            qty=delta,
            reason=reason,
            source_type="trade_purchase",
            source_id=purchase_id,
            idempotency_key=idem,
            metadata={"purchase_id": str(purchase_id), "human_id": label},
        )
        if result.duplicate:
            continue
        item = result.item
        if delta > 0:
            item.last_purchase_at = datetime.now(timezone.utc)
        unit = item.stock_unit or item.default_unit or item.selling_unit
        updates.append(
            {
                "catalog_item_id": item.id,
                "name": item.name,
                "unit": unit,
                "old_qty": result.movement.qty_before,
                "new_qty": result.movement.qty_after,
                "delta": delta,
            }
        )
    return updates
