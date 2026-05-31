import uuid
from collections import defaultdict
from datetime import date, datetime, time, timedelta, timezone
from decimal import Decimal
from typing import Annotated, Literal

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import case, desc, func, literal, or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.database import get_db
from app.deps import get_current_user, require_membership, require_permission, require_role
from app.services.staff_audit import log_staff_activity
from app.services.notification_emitter import CATEGORY_STAFF
from app.services.stock_inventory import (
    compute_expected_system_qty,
    movement_delivered_qty_map,
    movement_quick_purchase_qty_map,
)
from app.models import (
    Broker,
    CatalogItem,
    CategoryType,
    DailyUsageLog,
    ItemCategory,
    Membership,
    StaffActivityLog,
    StaffChecklistCompletion,
    StaffChecklistTemplate,
    Supplier,
    TradePurchase,
    TradePurchaseLine,
    User,
)
from app.models.notification import AppNotification
from app.models.reorder_list import ReorderListEntry
from app.models.stock_adjustment import StockAdjustmentLog
from app.models.stock_physical_count import StockPhysicalCount
from app.models.staff_purchase_log import StaffPurchaseLog
from app.schemas.stock_audit import StockVerifyCountIn
from app.schemas.stock import (
    BarcodeBatchIn,
    BarcodeBatchOut,
    BarcodeLabelOut,
    BarcodeLookupOut,
    StockAdjustmentOut,
    StockVarianceOut,
    StockDetailOut,
    StockIntelligenceOut,
    StockListItemOut,
    StockListItemMinimalOut,
    StockListOut,
    StockListCompactOut,
    StockPatchIn,
    RecentPurchaseOut,
    ReorderListEntryOut,
    ReorderListOut,
    ReorderListPatchIn,
    InventorySummaryOut,
    OpeningStockIn,
    OpeningStockMissingOut,
    OpeningStockSetupOut,
    OpeningStockSetupItemOut,
    OpeningStockSetupSummaryOut,
    PhysicalStockCountIn,
    PhysicalStockCountOut,
    StockTotalsOut,
    StockAlertsSummaryOut,
    WarehouseAlertsSummaryOut,
    LowStockOpsSummaryOut,
    LowStockOpsItemOut,
    LowStockOpsOut,
    StaffPurchaseLogIn,
    StaffPurchaseLogOut,
    QuickPurchaseIn,
    QuickPurchaseOut,
    StockActivityEventOut,
    StockItemActivityOut,
    StockMovementOut,
    StockPhysicalUpdateIn,
    StockPhysicalUpdateOut,
)
from app.models.stock_movement import StockMovement
from app.services import trade_query as tq
from app.services.staff_view import should_redact_financials
from app.services.stock_inventory import (
    catalog_reorder,
    catalog_stock_qty,
    compute_inventory_summary,
    stock_status,
)
from app.services.low_stock_priority import compute_low_stock_priority
from app.services.low_stock_ops_enrichment import (
    derive_lifecycle_stage,
    item_is_disputed,
    open_dispute_item_ids,
    rejected_audit_item_ids,
    reorder_status_map,
)
from app.services.stock_movement_service import (
    StaleStockVersionError,
    apply_stock_movement,
)
from app.services.realtime_events import publish_business_event
from app.services.notification_emitter import publish_notification_changed
from app.services.stock_variance_notifications import (
    _last_purchase_expected_qty,
    maybe_notify_staff_system_stock_edit,
    maybe_notify_stock_variance,
)
from app.services.stock_tracking_profile import profile_from_catalog_item
from app.services.unit_normalization import (
    catalog_stock_unit,
    current_stock_kg as stock_qty_kg_equivalent,
    line_qty_in_stock_unit,
)

router = APIRouter(prefix="/v1/businesses/{business_id}/stock", tags=["stock"])

StatusFilter = Literal["all", "low", "critical", "out", "shortage"]
OpeningSetupStatus = Literal["pending", "completed", "all"]
SortBy = Literal["name", "stock_asc", "stock_desc", "recent"]


def _user_display(user: User) -> str:
    if user.name and user.name.strip():
        return user.name.strip()
    return user.username or user.email


async def _supplier_name(db: AsyncSession, item: CatalogItem) -> str | None:
    if item.last_supplier_id:
        r = await db.execute(select(Supplier.name).where(Supplier.id == item.last_supplier_id))
        n = r.scalar_one_or_none()
        if n:
            return n
    return None


def _days_since_last_purchase(item: CatalogItem) -> int | None:
    if not item.last_purchase_at:
        return None
    last_purchase_at = item.last_purchase_at
    if last_purchase_at.tzinfo is None:
        last_purchase_at = last_purchase_at.replace(tzinfo=timezone.utc)
    delta = datetime.now(timezone.utc) - last_purchase_at
    return max(0, delta.days)


def _needs_eviction(
    item: CatalogItem,
    *,
    is_perishable: bool,
    current: Decimal,
) -> bool:
    if not is_perishable or current <= 0:
        return False
    days = item.eviction_days
    if days is None or days <= 0:
        return False
    since = _days_since_last_purchase(item)
    if since is None:
        return False
    return since > days


async def _last_trade_meta_map(
    db: AsyncSession,
    items: list[CatalogItem],
) -> dict[uuid.UUID, tuple[str | None, bool | None]]:
    tp_ids = {i.last_trade_purchase_id for i in items if i.last_trade_purchase_id}
    if not tp_ids:
        return {}
    r = await db.execute(
        select(
            TradePurchase.id,
            TradePurchase.human_id,
            TradePurchase.delivery_status,
        ).where(
            TradePurchase.id.in_(tp_ids),
            TradePurchase.status.notin_(("deleted", "cancelled")),
        )
    )
    by_tp = {
        row[0]: (
            row[1],
            (row[2] or "").strip().lower() == "stock_committed",
        )
        for row in r.all()
    }
    out: dict[uuid.UUID, tuple[str | None, bool | None]] = {}
    for item in items:
        tid = item.last_trade_purchase_id
        if tid and tid in by_tp:
            hid, delivered = by_tp[tid]
            out[item.id] = (hid, delivered)
    return out


def _item_to_list_row(
    item: CatalogItem,
    category_name: str | None,
    subcategory_name: str | None,
    supplier_name: str | None,
    *,
    period_purchased_qty: Decimal | None = None,
    period_usage_qty: Decimal | None = None,
    period_variance_qty: Decimal | None = None,
    ledger_variance_qty: Decimal | None = None,
    current_stock_kg: Decimal | None = None,
    stock_unit: str | None = None,
    needs_verification: bool = False,
    purchased_today_qty: Decimal | None = None,
    usage_today_qty: Decimal | None = None,
    is_perishable: bool = False,
    last_purchase_human_id: str | None = None,
    last_purchase_delivered: bool | None = None,
    last_line_qty: Decimal | None = None,
    last_purchase_at: datetime | None = None,
    has_pending_order: bool = False,
    pending_order_days: int | None = None,
    pending_delivery_qty: Decimal | None = None,
    physical_stock_qty: Decimal | None = None,
    physical_stock_difference_qty: Decimal | None = None,
    physical_stock_counted_at: datetime | None = None,
    physical_stock_counted_by: str | None = None,
    total_delivered_qty: Decimal | None = None,
    total_quick_purchase_qty: Decimal | None = None,
    total_pending_delivery_qty: Decimal | None = None,
) -> StockListItemOut:
    cur = catalog_stock_qty(item)
    warehouse_diff: Decimal | None = None
    if period_purchased_qty is not None:
        # Canonical warehouse diff semantics:
        # positive => system stock exceeds period purchased quantity (excess),
        # negative => system stock below period purchased quantity (deficit).
        warehouse_diff = cur - period_purchased_qty
    ro = catalog_reorder(item)
    unit = stock_unit or item.stock_unit or item.default_unit or item.selling_unit
    kg_equiv = (
        current_stock_kg
        if current_stock_kg is not None
        else stock_qty_kg_equivalent(item, cur)
    )
    ledger_var = ledger_variance_qty if ledger_variance_qty is not None else period_variance_qty
    opening = Decimal(getattr(item, "opening_stock_qty", None) or 0)
    delivered_lifetime = Decimal(total_delivered_qty or 0)
    quick_lifetime = Decimal(total_quick_purchase_qty or 0)
    expected = compute_expected_system_qty(
        getattr(item, "opening_stock_qty", None),
        total_delivered_qty,
        total_quick_purchase_qty=total_quick_purchase_qty,
    )
    out_of_sync = (
        (opening > 0 or delivered_lifetime > 0 or quick_lifetime > 0)
        and abs(cur - expected) > Decimal("0.001")
    )
    return StockListItemOut(
        id=item.id,
        item_code=item.item_code,
        name=item.name,
        category_name=category_name,
        subcategory_name=subcategory_name,
        current_stock=cur,
        reorder_level=ro,
        unit=unit,
        stock_unit=unit,
        current_stock_kg=kg_equiv,
        rack_location=item.rack_location,
        supplier_name=supplier_name,
        stock_status=stock_status(cur, ro),
        last_stock_updated_at=item.last_stock_updated_at,
        last_stock_updated_by=item.last_stock_updated_by,
        period_purchased_qty=period_purchased_qty,
        period_usage_qty=period_usage_qty,
        period_variance_qty=ledger_var,
        ledger_variance_qty=ledger_var,
        needs_verification=needs_verification,
        purchased_today_qty=purchased_today_qty,
        usage_today_qty=usage_today_qty,
        days_since_last_purchase=_days_since_last_purchase(item),
        needs_eviction=_needs_eviction(item, is_perishable=is_perishable, current=cur),
        is_perishable=is_perishable,
        missing_barcode=not (getattr(item, "barcode", None) and str(item.barcode).strip()),
        missing_item_code=not (item.item_code and str(item.item_code).strip()),
        barcode=getattr(item, "barcode", None),
        last_purchase_human_id=last_purchase_human_id,
        last_purchase_delivered=last_purchase_delivered,
        last_line_qty=last_line_qty,
        last_purchase_at=last_purchase_at,
        has_pending_order=has_pending_order,
        pending_order_days=pending_order_days,
        pending_delivery_qty=pending_delivery_qty,
        physical_stock_qty=physical_stock_qty,
        physical_stock_difference_qty=physical_stock_difference_qty,
        physical_stock_counted_at=physical_stock_counted_at,
        physical_stock_counted_by=physical_stock_counted_by,
        warehouse_diff_qty=warehouse_diff,
        opening_stock_qty=getattr(item, "opening_stock_qty", None),
        opening_stock_set_at=getattr(item, "opening_stock_set_at", None),
        opening_stock_set_by=getattr(item, "opening_stock_set_by", None),
        opening_stock_locked=bool(getattr(item, "opening_stock_locked", False)),
        stock_version=int(getattr(item, "stock_version", 0) or 0),
        total_delivered_qty=total_delivered_qty,
        total_pending_delivery_qty=total_pending_delivery_qty,
        expected_system_qty=expected,
        system_stock_out_of_sync=out_of_sync,
        public_token=getattr(item, "public_token", None),
    )


async def _lifetime_purchase_qty_maps(
    db: AsyncSession,
    business_id: uuid.UUID,
    item_ids: list[uuid.UUID],
) -> tuple[dict[uuid.UUID, Decimal], dict[uuid.UUID, Decimal]]:
    """Lifetime delivered vs undelivered purchase line qty (stock unit). PLAN.MD V2 Task 7."""
    if not item_ids:
        return {}, {}
    r = await db.execute(
        select(TradePurchaseLine, CatalogItem, TradePurchase.is_delivered)
        .join(TradePurchase, TradePurchase.id == TradePurchaseLine.trade_purchase_id)
        .join(CatalogItem, TradePurchaseLine.catalog_item_id == CatalogItem.id)
        .where(
            TradePurchase.business_id == business_id,
            TradePurchase.status.notin_(("deleted", "cancelled")),
            TradePurchaseLine.catalog_item_id.in_(item_ids),
            CatalogItem.business_id == business_id,
            CatalogItem.deleted_at.is_(None),
        )
    )
    pending: dict[uuid.UUID, Decimal] = defaultdict(lambda: Decimal(0))
    for line, cat_item, is_delivered in r.all():
        cid = line.catalog_item_id
        if cid is None:
            continue
        qty = line_qty_in_stock_unit(line, cat_item)
        if qty <= 0:
            continue
        if is_delivered:
            continue
        pending[cid] += qty
    delivered = await movement_delivered_qty_map(db, business_id, item_ids)
    return delivered, dict(pending)


async def _pending_order_meta_map(
    db: AsyncSession,
    business_id: uuid.UUID,
    item_ids: list[uuid.UUID],
) -> dict[uuid.UUID, tuple[bool, int | None, Decimal | None]]:
    """Undelivered purchase lines per catalog item (truck icon + pending qty on stock UI)."""
    if not item_ids:
        return {}
    r = await db.execute(
        select(TradePurchaseLine, CatalogItem, TradePurchase.purchase_date)
        .join(TradePurchase, TradePurchase.id == TradePurchaseLine.trade_purchase_id)
        .join(CatalogItem, TradePurchaseLine.catalog_item_id == CatalogItem.id)
        .where(
            TradePurchase.business_id == business_id,
            TradePurchase.delivery_status.notin_(("stock_committed", "cancelled")),
            TradePurchase.status.notin_(("deleted", "cancelled")),
            TradePurchaseLine.catalog_item_id.in_(item_ids),
            CatalogItem.business_id == business_id,
            CatalogItem.deleted_at.is_(None),
        )
    )
    today = date.today()
    qty_by_item: dict[uuid.UUID, Decimal] = defaultdict(lambda: Decimal(0))
    oldest_by_item: dict[uuid.UUID, date] = {}
    for line, item, purchase_date in r.all():
        cid = line.catalog_item_id
        if cid is None:
            continue
        qty_by_item[cid] += line_qty_in_stock_unit(line, item)
        if purchase_date is not None:
            pd = purchase_date.date() if isinstance(purchase_date, datetime) else purchase_date
            prev = oldest_by_item.get(cid)
            if prev is None or pd < prev:
                oldest_by_item[cid] = pd
    out: dict[uuid.UUID, tuple[bool, int | None, Decimal | None]] = {}
    for cid, total_qty in qty_by_item.items():
        days: int | None = None
        oldest = oldest_by_item.get(cid)
        if oldest is not None:
            days = max(0, (today - oldest).days)
        qty_out = total_qty if total_qty > 0 else None
        out[cid] = (True, days, qty_out)
    return out


async def _latest_physical_count_map(
    db: AsyncSession,
    business_id: uuid.UUID,
    item_ids: list[uuid.UUID],
) -> dict[uuid.UUID, StockPhysicalCount]:
    if not item_ids:
        return {}
    r = await db.execute(
        select(StockPhysicalCount)
        .where(
            StockPhysicalCount.business_id == business_id,
            StockPhysicalCount.item_id.in_(item_ids),
        )
        .order_by(StockPhysicalCount.item_id, desc(StockPhysicalCount.counted_at))
    )
    out: dict[uuid.UUID, StockPhysicalCount] = {}
    for row in r.scalars().all():
        out.setdefault(row.item_id, row)
    return out


def _parse_period_dates(
    period_start: str | None, period_end: str | None
) -> tuple[date | None, date | None]:
    # Route handlers called directly (not via HTTP) may pass FastAPI Query() defaults.
    if not isinstance(period_start, str) or not isinstance(period_end, str):
        return None, None
    ps_raw = period_start.strip()
    pe_raw = period_end.strip()
    if not ps_raw or not pe_raw:
        return None, None
    try:
        ps = date.fromisoformat(ps_raw[:10])
        pe = date.fromisoformat(pe_raw[:10])
        return ps, pe
    except ValueError:
        return None, None


async def _today_purchased_map(
    db: AsyncSession,
    business_id: uuid.UUID,
    item_ids: list[uuid.UUID],
    today: date,
) -> dict[uuid.UUID, Decimal]:
    return await _period_purchased_map(db, business_id, item_ids, today, today)


async def _today_usage_map(
    db: AsyncSession,
    business_id: uuid.UUID,
    item_ids: list[uuid.UUID],
    today: date,
) -> dict[uuid.UUID, Decimal]:
    if not item_ids:
        return {}
    r = await db.execute(
        select(DailyUsageLog.item_id, DailyUsageLog.used_qty).where(
            DailyUsageLog.business_id == business_id,
            DailyUsageLog.usage_date == today,
            DailyUsageLog.item_id.in_(item_ids),
        )
    )
    return {row[0]: Decimal(row[1] or 0) for row in r.all()}


async def _period_purchased_map(
    db: AsyncSession,
    business_id: uuid.UUID,
    item_ids: list[uuid.UUID],
    period_start: date,
    period_end: date,
    *,
    delivered_only: bool = True,
) -> dict[uuid.UUID, Decimal]:
    """Sum received purchase line qty normalized to each item's stock unit."""
    if not item_ids:
        return {}
    filters = [
        TradePurchase.business_id == business_id,
        TradePurchase.purchase_date >= period_start,
        TradePurchase.purchase_date <= period_end,
        TradePurchase.status.notin_(("cancelled", "deleted")),
        TradePurchaseLine.catalog_item_id.in_(item_ids),
        CatalogItem.business_id == business_id,
        CatalogItem.deleted_at.is_(None),
    ]
    if delivered_only:
        filters.append(
            TradePurchase.delivery_status.in_(("stock_committed", "partial", "staff_verified"))
        )
    stmt = (
        select(TradePurchaseLine, CatalogItem)
        .join(TradePurchase, TradePurchaseLine.trade_purchase_id == TradePurchase.id)
        .join(CatalogItem, TradePurchaseLine.catalog_item_id == CatalogItem.id)
        .where(*filters)
    )
    r = await db.execute(stmt)
    totals: dict[uuid.UUID, Decimal] = defaultdict(lambda: Decimal(0))
    for line, item in r.all():
        totals[item.id] += line_qty_in_stock_unit(line, item)
    staff = await _staff_quick_purchased_map(
        db, business_id, item_ids, period_start, period_end
    )
    for iid, qty in staff.items():
        totals[iid] += qty
    return dict(totals)


async def _staff_quick_purchased_map(
    db: AsyncSession,
    business_id: uuid.UUID,
    item_ids: list[uuid.UUID],
    period_start: date,
    period_end: date,
) -> dict[uuid.UUID, Decimal]:
    """Staff quick purchases in period (stock list PURCHASE column)."""
    if not item_ids:
        return {}
    start_dt = datetime.combine(period_start, time.min, tzinfo=timezone.utc)
    end_dt = datetime.combine(period_end, time.max, tzinfo=timezone.utc)
    r = await db.execute(
        select(
            StaffPurchaseLog.item_id,
            func.coalesce(func.sum(StaffPurchaseLog.qty), 0),
        )
        .where(
            StaffPurchaseLog.business_id == business_id,
            StaffPurchaseLog.item_id.in_(item_ids),
            StaffPurchaseLog.created_at >= start_dt,
            StaffPurchaseLog.created_at <= end_dt,
        )
        .group_by(StaffPurchaseLog.item_id)
    )
    return {row[0]: Decimal(row[1] or 0) for row in r.all()}


async def _period_usage_map(
    db: AsyncSession,
    business_id: uuid.UUID,
    item_ids: list[uuid.UUID],
    period_start: date,
    period_end: date,
) -> dict[uuid.UUID, Decimal]:
    if not item_ids:
        return {}
    r = await db.execute(
        select(
            DailyUsageLog.item_id,
            func.coalesce(func.sum(DailyUsageLog.used_qty), 0),
        )
        .where(
            DailyUsageLog.business_id == business_id,
            DailyUsageLog.usage_date >= period_start,
            DailyUsageLog.usage_date <= period_end,
            DailyUsageLog.item_id.in_(item_ids),
        )
        .group_by(DailyUsageLog.item_id)
    )
    return {row[0]: Decimal(row[1] or 0) for row in r.all()}


_PURCHASE_ADJ_TYPES = frozenset({"purchase", "purchase_reversal", "purchase_adjustment"})


async def _ledger_variance_map(
    db: AsyncSession,
    business_id: uuid.UUID,
    items: list[CatalogItem],
) -> dict[uuid.UUID, Decimal | None]:
    """
    Reconcile on-hand stock vs all-time purchases − usage ± manual adjustments.

    Returns None when item has no movement history to reconcile.
    """
    if not items:
        return {}
    item_ids = [i.id for i in items]
    all_purchased = await _period_purchased_map(
        db,
        business_id,
        item_ids,
        date(1970, 1, 1),
        date(2099, 12, 31),
    )
    usage_r = await db.execute(
        select(
            DailyUsageLog.item_id,
            func.coalesce(func.sum(DailyUsageLog.used_qty), 0),
        )
        .where(
            DailyUsageLog.business_id == business_id,
            DailyUsageLog.item_id.in_(item_ids),
        )
        .group_by(DailyUsageLog.item_id)
    )
    all_usage = {row[0]: Decimal(row[1] or 0) for row in usage_r.all()}
    adj_r = await db.execute(
        select(
            StockAdjustmentLog.item_id,
            func.coalesce(func.sum(StockAdjustmentLog.new_qty - StockAdjustmentLog.old_qty), 0),
        )
        .where(
            StockAdjustmentLog.business_id == business_id,
            StockAdjustmentLog.item_id.in_(item_ids),
            StockAdjustmentLog.adjustment_type.notin_(_PURCHASE_ADJ_TYPES),
        )
        .group_by(StockAdjustmentLog.item_id)
    )
    adj_net = {row[0]: Decimal(row[1] or 0) for row in adj_r.all()}
    out: dict[uuid.UUID, Decimal | None] = {}
    for item in items:
        purchased = all_purchased.get(item.id, Decimal(0))
        usage = all_usage.get(item.id, Decimal(0))
        adj = adj_net.get(item.id, Decimal(0))
        if purchased == 0 and usage == 0 and adj == 0:
            out[item.id] = None
            continue
        expected = purchased - usage + adj
        out[item.id] = catalog_stock_qty(item) - expected
    return out


def _needs_verification(
    current: Decimal, purchased: Decimal, *, threshold_pct: float = 0.1
) -> bool:
    if purchased <= 0:
        return False
    delta = abs(current - purchased)
    return delta / purchased > Decimal(str(threshold_pct))


def _sort_stock_rows(
    rows: list[tuple[CatalogItem, str | None, str | None]],
    sort: SortBy,
) -> None:
    if sort == "stock_asc":
        rows.sort(key=lambda t: catalog_stock_qty(t[0]))
    elif sort == "stock_desc":
        rows.sort(key=lambda t: catalog_stock_qty(t[0]), reverse=True)
    elif sort == "recent":
        rows.sort(
            key=lambda t: t[0].last_stock_updated_at
            or datetime.min.replace(tzinfo=timezone.utc),
            reverse=True,
        )
    else:
        rows.sort(key=lambda t: (t[0].name or "").lower())


async def _query_items(
    db: AsyncSession,
    business_id: uuid.UUID,
    *,
    q: str,
    category: str,
    subcategory: str,
    status_val: StatusFilter,
    sort: SortBy,
    page: int,
    per_page: int,
):
    stmt = (
        select(CatalogItem, ItemCategory.name, CategoryType.name)
        .join(ItemCategory, CatalogItem.category_id == ItemCategory.id)
        .outerjoin(CategoryType, CatalogItem.type_id == CategoryType.id)
        .where(
            CatalogItem.business_id == business_id,
            CatalogItem.deleted_at.is_(None),
        )
    )
    if q.strip():
        like = f"%{q.strip().lower()}%"
        stmt = stmt.where(
            or_(
                func.lower(CatalogItem.name).like(like),
                func.lower(func.coalesce(CatalogItem.item_code, "")).like(like),
                func.lower(func.coalesce(CatalogItem.barcode, "")).like(like),
            )
        )
    if category.strip():
        stmt = stmt.where(func.lower(ItemCategory.name) == category.strip().lower())
    if subcategory.strip():
        stmt = stmt.where(func.lower(CategoryType.name) == subcategory.strip().lower())

    rows = (await db.execute(stmt)).all()
    out: list[tuple[CatalogItem, str | None, str | None]] = []
    for item, cat_name, type_name in rows:
        cur = catalog_stock_qty(item)
        ro = catalog_reorder(item)
        st = stock_status(cur, ro)
        if status_val == "shortage":
            if st not in ("low", "critical", "out"):
                continue
        elif status_val != "all" and st != status_val:
            continue
        out.append((item, cat_name, type_name))

    _sort_stock_rows(out, sort)
    total = len(out)
    start = (page - 1) * per_page
    page_rows = out[start : start + per_page]
    return total, page_rows


async def _opening_setup_summary(
    db: AsyncSession,
    business_id: uuid.UUID,
) -> OpeningStockSetupSummaryOut:
    base = (
        CatalogItem.business_id == business_id,
        CatalogItem.deleted_at.is_(None),
    )
    total_r = await db.execute(select(func.count(CatalogItem.id)).where(*base))
    pending_r = await db.execute(
        select(func.count(CatalogItem.id)).where(
            *base,
            CatalogItem.opening_stock_set_at.is_(None),
        )
    )
    total = int(total_r.scalar_one() or 0)
    pending = int(pending_r.scalar_one() or 0)
    completed = max(0, total - pending)
    last_r = await db.execute(
        select(CatalogItem.opening_stock_set_at, CatalogItem.opening_stock_set_by)
        .where(*base, CatalogItem.opening_stock_set_at.isnot(None))
        .order_by(desc(CatalogItem.opening_stock_set_at))
        .limit(1)
    )
    last_row = last_r.one_or_none()
    last_at = last_row[0] if last_row else None
    last_by = last_row[1] if last_row else None
    return OpeningStockSetupSummaryOut(
        pending_count=pending,
        completed_count=completed,
        total_count=total,
        last_updated_at=last_at,
        last_updated_by=last_by,
    )


async def _query_opening_setup_items(
    db: AsyncSession,
    business_id: uuid.UUID,
    *,
    q: str,
    setup_status: OpeningSetupStatus,
    stock_status_val: StatusFilter,
    category: str,
    subcategory: str,
    missing_barcode: bool,
    missing_item_code: bool,
    supplier_id: uuid.UUID | None,
    unit: str,
    updated_today: bool,
    updated_by: str,
    page: int,
    per_page: int,
) -> tuple[int, list[tuple[CatalogItem, str | None, str | None]]]:
    stmt = (
        select(CatalogItem, ItemCategory.name, CategoryType.name)
        .join(ItemCategory, CatalogItem.category_id == ItemCategory.id)
        .outerjoin(CategoryType, CatalogItem.type_id == CategoryType.id)
        .where(
            CatalogItem.business_id == business_id,
            CatalogItem.deleted_at.is_(None),
        )
    )
    if q.strip():
        like = f"%{q.strip().lower()}%"
        stmt = stmt.where(
            or_(
                func.lower(CatalogItem.name).like(like),
                func.lower(func.coalesce(CatalogItem.item_code, "")).like(like),
                func.lower(func.coalesce(CatalogItem.barcode, "")).like(like),
                func.lower(func.coalesce(CategoryType.name, "")).like(like),
                func.lower(func.coalesce(ItemCategory.name, "")).like(like),
            )
        )
    if category.strip():
        stmt = stmt.where(func.lower(ItemCategory.name) == category.strip().lower())
    if subcategory.strip():
        stmt = stmt.where(func.lower(CategoryType.name) == subcategory.strip().lower())
    if supplier_id is not None:
        stmt = stmt.where(CatalogItem.last_supplier_id == supplier_id)
    if unit.strip():
        u = unit.strip().lower()
        stmt = stmt.where(
            or_(
                func.lower(func.coalesce(CatalogItem.stock_unit, "")) == u,
                func.lower(func.coalesce(CatalogItem.default_unit, "")) == u,
            )
        )
    if updated_today:
        today = date.today()
        stmt = stmt.where(
            func.date(CatalogItem.opening_stock_set_at) == today,
        )
    if updated_by.strip():
        like = f"%{updated_by.strip().lower()}%"
        stmt = stmt.where(
            func.lower(func.coalesce(CatalogItem.opening_stock_set_by, "")).like(like)
        )

    rows = (await db.execute(stmt)).all()
    out: list[tuple[CatalogItem, str | None, str | None]] = []
    for item, cat_name, type_name in rows:
        is_pending = item.opening_stock_set_at is None
        if setup_status == "pending" and not is_pending:
            continue
        if setup_status == "completed" and is_pending:
            continue
        if missing_barcode and (item.barcode and str(item.barcode).strip()):
            continue
        if missing_item_code and (item.item_code and str(item.item_code).strip()):
            continue
        cur = catalog_stock_qty(item)
        ro = catalog_reorder(item)
        st = stock_status(cur, ro)
        if stock_status_val != "all" and st != stock_status_val:
            continue
        out.append((item, cat_name, type_name))

    out.sort(key=lambda t: ((0 if t[0].opening_stock_set_at is None else 1), (t[0].name or "").lower()))
    total = len(out)
    start = (page - 1) * per_page
    return total, out[start : start + per_page]


def _opening_setup_item_row(
    item: CatalogItem,
    cat_name: str | None,
    type_name: str | None,
    supplier_name: str | None,
) -> OpeningStockSetupItemOut:
    base = _item_to_list_row(item, cat_name, type_name, supplier_name)
    is_pending = item.opening_stock_set_at is None
    missing_bc = not (getattr(item, "barcode", None) and str(item.barcode).strip())
    data = base.model_dump()
    data["setup_status"] = "pending" if is_pending else "completed"
    data["barcode_state"] = "missing" if missing_bc else "ok"
    return OpeningStockSetupItemOut(**data)


@router.get("/opening/setup", response_model=OpeningStockSetupOut)
async def list_opening_stock_setup(
    business_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
    page: int = Query(1, ge=1),
    per_page: int = Query(50, ge=1, le=200),
    q: str = Query(""),
    status: OpeningSetupStatus = Query("all"),
    stock_status: StatusFilter = Query("all"),
    category: str = Query(""),
    subcategory: str = Query(""),
    missing_barcode: bool = Query(False),
    missing_item_code: bool = Query(False),
    supplier_id: uuid.UUID | None = Query(None),
    unit: str = Query(""),
    updated_today: bool = Query(False),
    updated_by: str = Query(""),
):
    summary = await _opening_setup_summary(db, business_id)
    total, rows = await _query_opening_setup_items(
        db,
        business_id,
        q=q,
        setup_status=status,
        stock_status_val=stock_status,
        category=category,
        subcategory=subcategory,
        missing_barcode=missing_barcode,
        missing_item_code=missing_item_code,
        supplier_id=supplier_id,
        unit=unit,
        updated_today=updated_today,
        updated_by=updated_by,
        page=page,
        per_page=per_page,
    )
    items: list[OpeningStockSetupItemOut] = []
    items_dict = {item.id: item for item, _, _ in rows}
    sup_map = await _supplier_names_bulk(db, items_dict)
    for item, cat_name, type_name in rows:
        sup = sup_map.get(item.id)
        items.append(_opening_setup_item_row(item, cat_name, type_name, sup))
    return OpeningStockSetupOut(
        summary=summary,
        items=items,
        total=total,
        page=page,
        per_page=per_page,
    )


@router.get("/inventory-summary", response_model=InventorySummaryOut)
async def stock_inventory_summary(
    business_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
) -> InventorySummaryOut:
    """On-hand stock valuation (landing cost × qty) and unit buckets for owner home."""
    del _m
    payload = await compute_inventory_summary(db, business_id)
    return InventorySummaryOut(**payload)


@router.post("/items/{item_id}/recompute")
async def recompute_item_stock(
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
    _m: Annotated[Membership, Depends(require_permission("stock_edit"))],
):
    """Recompute item stock from delivered purchases + non-purchase movement deltas."""
    del _m
    item_r = await db.execute(
        select(CatalogItem).where(
            CatalogItem.id == item_id,
            CatalogItem.business_id == business_id,
            CatalogItem.deleted_at.is_(None),
        )
    )
    item = item_r.scalar_one_or_none()
    if item is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Item not found")

    delivered_r = await db.execute(
        select(TradePurchaseLine, CatalogItem)
        .join(TradePurchase, TradePurchaseLine.trade_purchase_id == TradePurchase.id)
        .join(CatalogItem, TradePurchaseLine.catalog_item_id == CatalogItem.id)
        .where(
            TradePurchase.business_id == business_id,
            TradePurchase.status.notin_(("cancelled", "deleted")),
            TradePurchase.is_delivered.is_(True),
            TradePurchaseLine.catalog_item_id == item_id,
            CatalogItem.business_id == business_id,
            CatalogItem.deleted_at.is_(None),
        )
    )
    delivered_total = Decimal("0")
    for line, line_item in delivered_r.all():
        delivered_total += line_qty_in_stock_unit(line, line_item)

    non_purchase_delta_r = await db.execute(
        select(func.coalesce(func.sum(StockMovement.delta_qty), 0)).where(
            StockMovement.business_id == business_id,
            StockMovement.item_id == item_id,
            StockMovement.movement_kind.notin_(
                (
                    "delivery_receive",
                    "purchase",
                    "quick_purchase",
                )
            ),
        )
    )
    non_purchase_delta = Decimal(non_purchase_delta_r.scalar_one() or 0)
    recomputed_qty = delivered_total + non_purchase_delta
    if recomputed_qty < 0:
        recomputed_qty = Decimal("0")

    result = await apply_stock_movement(
        db,
        business_id=business_id,
        item_id=item_id,
        user=user,
        movement_kind="correction",
        mode="absolute",
        qty=recomputed_qty,
        reason="Stock recompute from delivered purchases",
        notes="Manual recompute",
        source_type="stock_recompute",
        source_id=item_id,
        metadata={
            "delivered_total": float(delivered_total),
            "non_purchase_delta": float(non_purchase_delta),
        },
        create_projection=True,
        create_activity=True,
    )
    await db.commit()
    return {
        "item_id": str(item_id),
        "recomputed_qty": float(result.item.current_stock),
        "delivered_total": float(delivered_total),
        "non_purchase_delta": float(non_purchase_delta),
    }


@router.get("/items/{item_id}/purchase-intelligence")
async def get_item_purchase_intelligence(
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _user: Annotated[User, Depends(get_current_user)],
    _m: Annotated[Membership, Depends(require_membership)],
):
    del _m
    rows_r = await db.execute(
        select(
            TradePurchaseLine.qty,
            TradePurchase.created_at,
            TradePurchase.supplier_id,
        )
        .join(TradePurchase, TradePurchaseLine.trade_purchase_id == TradePurchase.id)
        .where(
            TradePurchase.business_id == business_id,
            TradePurchaseLine.catalog_item_id == item_id,
            TradePurchase.status.notin_(("cancelled", "deleted")),
        )
        .order_by(desc(TradePurchase.created_at))
        .limit(12)
    )
    rows = rows_r.all()
    if not rows:
        return {"suggested_qty": None, "avg_interval_days": None, "default_supplier": None}

    qtys = [float(r[0] or 0) for r in rows]
    avg_qty = sum(qtys) / max(len(qtys), 1)

    dates = [r[1] for r in rows if r[1] is not None]
    avg_interval_days = None
    if len(dates) >= 2:
        ordered = sorted(dates)
        diffs = []
        for i in range(len(ordered) - 1):
            d = (ordered[i + 1] - ordered[i]).days
            if d > 0:
                diffs.append(d)
        if diffs:
            avg_interval_days = round(sum(diffs) / len(diffs))

    supplier_counts: dict[str, int] = {}
    for _, _, sid in rows:
        if sid is None:
            continue
        k = str(sid)
        supplier_counts[k] = supplier_counts.get(k, 0) + 1
    top_supplier = max(supplier_counts, key=lambda k: supplier_counts[k]) if supplier_counts else None
    default_supplier = None
    if top_supplier:
        supp_r = await db.execute(
            select(Supplier.id, Supplier.name).where(Supplier.id == top_supplier)
        )
        srow = supp_r.first()
        if srow:
            default_supplier = {"id": str(srow[0]), "name": srow[1] or "Supplier"}

    return {
        "suggested_qty": round(avg_qty),
        "avg_interval_days": avg_interval_days,
        "default_supplier": default_supplier,
    }


async def _stock_totals_purchased_in_period(
    db: AsyncSession,
    business_id: uuid.UUID,
    date_from: date,
    date_to: date,
) -> StockTotalsOut:
    """Sum purchased quantities in [date_from, date_to] for home period chips."""
    bag_expr = tq.trade_line_qty_bags_expr()
    box_expr = tq.trade_line_qty_boxes_expr()
    tin_expr = tq.trade_line_qty_tins_expr()
    kg_expr = tq.trade_line_weight_expr()
    bf = tq.trade_purchase_date_filter(business_id, date_from, date_to)
    deleted_filter = getattr(TradePurchase, "deleted_at", None)
    if deleted_filter is not None:
        bf = bf & TradePurchase.deleted_at.is_(None)
    r = await db.execute(
        select(
            func.coalesce(func.sum(bag_expr), 0),
            func.coalesce(func.sum(kg_expr), 0),
            func.coalesce(func.sum(box_expr), 0),
            func.coalesce(func.sum(tin_expr), 0),
            func.count(func.distinct(TradePurchaseLine.catalog_item_id)),
        )
        .select_from(TradePurchaseLine)
        .join(TradePurchase, TradePurchase.id == TradePurchaseLine.trade_purchase_id)
        .where(bf)
    )
    row = r.one()
    return StockTotalsOut(
        total_items=int(row[4] or 0),
        total_bags=float(row[0] or 0),
        total_kg=float(row[1] or 0),
        total_boxes=float(row[2] or 0),
        total_tins=float(row[3] or 0),
    )


@router.get("/totals", response_model=StockTotalsOut)
async def stock_totals(
    business_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
    period_start: str | None = Query(None),
    period_end: str | None = Query(None),
) -> StockTotalsOut:
    """On-hand totals by default; with period_start/end, purchased qty in range."""
    del _m
    if period_start and period_end:
        try:
            d_from = date.fromisoformat(str(period_start)[:10])
            d_to = date.fromisoformat(str(period_end)[:10])
        except ValueError as exc:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid period_start or period_end (use YYYY-MM-DD)",
            ) from exc
        if d_from > d_to:
            d_from, d_to = d_to, d_from
        return await _stock_totals_purchased_in_period(db, business_id, d_from, d_to)

    base = CatalogItem.business_id == business_id
    if hasattr(CatalogItem, "deleted_at"):
        base = base & CatalogItem.deleted_at.is_(None)
    r = await db.execute(
        select(
            func.count(CatalogItem.id),
            func.coalesce(
                func.sum(
                    case(
                        (CatalogItem.default_unit == "bag", CatalogItem.current_stock),
                        else_=0,
                    )
                ),
                0,
            ),
            func.coalesce(
                func.sum(
                    case(
                        (
                            CatalogItem.default_unit == "bag",
                            CatalogItem.current_stock
                            * func.coalesce(CatalogItem.default_kg_per_bag, 0),
                        ),
                        (CatalogItem.default_unit == "kg", CatalogItem.current_stock),
                        else_=0,
                    )
                ),
                0,
            ),
            func.coalesce(
                func.sum(
                    case(
                        (CatalogItem.default_unit == "box", CatalogItem.current_stock),
                        else_=0,
                    )
                ),
                0,
            ),
            func.coalesce(
                func.sum(
                    case(
                        (CatalogItem.default_unit == "tin", CatalogItem.current_stock),
                        else_=0,
                    )
                ),
                0,
            ),
        ).where(base)
    )
    row = r.one()
    return StockTotalsOut(
        total_items=int(row[0] or 0),
        total_bags=float(row[1] or 0),
        total_kg=float(row[2] or 0),
        total_boxes=float(row[3] or 0),
        total_tins=float(row[4] or 0),
    )


@router.get("/list", response_model=StockListOut)
async def list_stock(
    business_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
    page: int = Query(1, ge=1),
    per_page: int = Query(50, ge=1, le=2000),
    q: str = Query(""),
    category: str = Query(""),
    subcategory: str = Query(""),
    status: StatusFilter = Query("all"),
    sort: SortBy = Query("name"),
    include_period: bool = Query(False),
    period_start: str | None = Query(None),
    period_end: str | None = Query(None),
    include_today: bool = Query(True),
    purchased_in_period: bool = Query(False),
):
    ps, pe = _parse_period_dates(period_start, period_end)
    if purchased_in_period and include_period and ps and pe:
        _, all_rows = await _query_items(
            db,
            business_id,
            q=q,
            category=category,
            subcategory=subcategory,
            status_val=status,
            sort=sort,
            page=1,
            per_page=10000,
        )
        all_ids = [item.id for item, _, _ in all_rows]
        period_map_all = await _period_purchased_map(
            db, business_id, all_ids, ps, pe
        )
        filtered = [
            row
            for row in all_rows
            if period_map_all.get(row[0].id, Decimal(0)) > 0
        ]
        total = len(filtered)
        start = (page - 1) * per_page
        rows = filtered[start : start + per_page]
    else:
        total, rows = await _query_items(
            db,
            business_id,
            q=q,
            category=category,
            subcategory=subcategory,
            status_val=status,
            sort=sort,
            page=page,
            per_page=per_page,
        )
    period_map: dict[uuid.UUID, Decimal] = {}
    period_usage_map: dict[uuid.UUID, Decimal] = {}
    item_ids = [item.id for item, _, _ in rows]
    if include_period and ps and pe:
        if purchased_in_period:
            period_map = {
                iid: period_map_all.get(iid, Decimal(0))
                for iid in item_ids
            }
        else:
            period_map = await _period_purchased_map(
                db, business_id, item_ids, ps, pe
            )
        period_usage_map = await _period_usage_map(
            db, business_id, item_ids, ps, pe
        )
    today = date.today()
    today_purchased: dict[uuid.UUID, Decimal] = {}
    today_usage: dict[uuid.UUID, Decimal] = {}
    if include_today and item_ids:
        today_purchased = await _today_purchased_map(db, business_id, item_ids, today)
        today_usage = await _today_usage_map(db, business_id, item_ids, today)
    cat_ids = {item.category_id for item, _, _ in rows if item.category_id}
    perishable_by_cat: dict[uuid.UUID, bool] = {}
    if cat_ids:
        cr = await db.execute(
            select(ItemCategory.id, ItemCategory.is_perishable).where(
                ItemCategory.id.in_(cat_ids)
            )
        )
        perishable_by_cat = {row[0]: bool(row[1]) for row in cr.all()}
    catalog_items = [item for item, _, _ in rows]
    trade_meta = await _last_trade_meta_map(db, catalog_items)
    ledger_map = await _ledger_variance_map(db, business_id, catalog_items)
    pending_meta = await _pending_order_meta_map(db, business_id, item_ids)
    physical_meta = await _latest_physical_count_map(db, business_id, item_ids)
    movement_delivered = await movement_delivered_qty_map(db, business_id, item_ids)
    movement_quick = await movement_quick_purchase_qty_map(db, business_id, item_ids)
    items_dict = {item.id: item for item, _, _ in rows}
    sup_map = await _supplier_names_bulk(db, items_dict)
    items: list[StockListItemOut] = []
    for item, cat_name, type_name in rows:
        sup = sup_map.get(item.id)
        meta = trade_meta.get(item.id, (None, None))
        pend = pending_meta.get(item.id, (False, None, None))
        valid_last_trade = meta[0] is not None
        phys = physical_meta.get(item.id)
        purchased = period_map.get(item.id) if include_period else None
        usage = period_usage_map.get(item.id) if include_period else None
        cur = catalog_stock_qty(item)
        ledger_var = ledger_map.get(item.id)
        verify = False
        if ledger_var is not None and purchased is not None and purchased > 0:
            verify = abs(ledger_var) / purchased > Decimal("0.1")
        elif purchased is not None and purchased > 0:
            verify = _needs_verification(cur, purchased)
        perishable = perishable_by_cat.get(item.category_id, False) if item.category_id else False
        su = catalog_stock_unit(item)
        total_delivered = movement_delivered.get(item.id, Decimal(0))
        total_quick = movement_quick.get(item.id, Decimal(0))
        expected_sys = compute_expected_system_qty(
            getattr(item, "opening_stock_qty", None),
            total_delivered,
            total_quick_purchase_qty=total_quick,
        )
        phys_qty = phys.counted_qty if phys else None
        spec_diff: Decimal | None = None
        if phys is not None:
            spec_diff = phys.difference_qty
        elif phys_qty is not None:
            spec_diff = phys_qty - expected_sys
        items.append(
            _item_to_list_row(
                item,
                cat_name,
                type_name,
                sup,
                period_purchased_qty=purchased,
                period_usage_qty=usage,
                ledger_variance_qty=ledger_var,
                stock_unit=su,
                needs_verification=verify,
                purchased_today_qty=today_purchased.get(item.id),
                usage_today_qty=today_usage.get(item.id),
                is_perishable=perishable,
                last_purchase_human_id=meta[0],
                last_purchase_delivered=meta[1],
                last_line_qty=getattr(item, "last_line_qty", None)
                if valid_last_trade
                else None,
                last_purchase_at=getattr(item, "last_purchase_at", None)
                if valid_last_trade
                else None,
                has_pending_order=pend[0],
                pending_order_days=pend[1],
                pending_delivery_qty=pend[2],
                physical_stock_qty=phys_qty,
                physical_stock_difference_qty=spec_diff
                if spec_diff is not None
                else (phys.difference_qty if phys else None),
                physical_stock_counted_at=phys.counted_at if phys else None,
                physical_stock_counted_by=phys.counted_by_name if phys else None,
                total_delivered_qty=total_delivered,
                total_quick_purchase_qty=total_quick,
                total_pending_delivery_qty=pend[2],
            )
        )
    return StockListOut(items=items, total=total, page=page, per_page=per_page)


def _stock_row_to_minimal(row: StockListItemOut) -> StockListItemMinimalOut:
    return StockListItemMinimalOut(
        id=row.id,
        name=row.name,
        item_code=row.item_code,
        barcode=row.barcode,
        current_stock=row.current_stock,
        stock_unit=row.stock_unit,
        stock_status=row.stock_status,
        supplier_name=row.supplier_name,
        reorder_level=row.reorder_level,
        rack_location=row.rack_location,
        is_perishable=row.is_perishable,
        missing_barcode=row.missing_barcode,
        opening_stock_qty=row.opening_stock_qty,
        last_stock_updated_at=row.last_stock_updated_at,
    )


@router.get("/list/compact", response_model=StockListCompactOut)
async def list_stock_compact(
    business_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
    page: int = Query(1, ge=1),
    per_page: int = Query(50, ge=1, le=2000),
    q: str = Query(""),
    category: str = Query(""),
    subcategory: str = Query(""),
    status: StatusFilter = Query("all"),
    sort: SortBy = Query("name"),
    include_period: bool = Query(False),
    period_start: str | None = Query(None),
    period_end: str | None = Query(None),
    include_today: bool = Query(True),
    purchased_in_period: bool = Query(False),
):
    """Slim stock list payload for mobile table views."""
    full = await list_stock(
        business_id,
        db,
        _m,
        page=page,
        per_page=per_page,
        q=q,
        category=category,
        subcategory=subcategory,
        status=status,
        sort=sort,
        include_period=include_period,
        period_start=period_start,
        period_end=period_end,
        include_today=include_today,
        purchased_in_period=purchased_in_period,
    )
    return StockListCompactOut(
        items=[_stock_row_to_minimal(i) for i in full.items],
        total=full.total,
        page=full.page,
        per_page=full.per_page,
    )


@router.get("/search", response_model=StockListOut)
async def search_stock(
    business_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
    page: int = Query(1, ge=1),
    per_page: int = Query(50, ge=1, le=2000),
    q: str = Query(""),
    category: str = Query(""),
    subcategory: str = Query(""),
    status: StatusFilter = Query("all"),
    sort: SortBy = Query("name"),
):
    return await list_stock(
        business_id,
        db,
        _m,
        page=page,
        per_page=per_page,
        q=q,
        category=category,
        subcategory=subcategory,
        status=status,
        sort=sort,
    )


@router.get("/low", response_model=StockListOut)
async def low_stock(
    business_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
    page: int = Query(1, ge=1),
    per_page: int = Query(50, ge=1, le=2000),
):
    total, rows = await _query_items(
        db,
        business_id,
        q="",
        category="",
        subcategory="",
        status_val="all",
        sort="stock_asc",
        page=1,
        per_page=10_000,
    )
    filtered: list[tuple[CatalogItem, str | None, str | None, Decimal]] = []
    for item, cat_name, type_name in rows:
        cur = catalog_stock_qty(item)
        ro = catalog_reorder(item)
        if ro > 0 and cur < ro:
            ratio = cur / ro if ro > 0 else Decimal("1")
            filtered.append((item, cat_name, type_name, ratio))
    filtered.sort(key=lambda x: x[3])
    total = len(filtered)
    start = (page - 1) * per_page
    page_slice = filtered[start : start + per_page]
    items_dict = {item.id: item for item, _, _, _ in page_slice}
    sup_map = await _supplier_names_bulk(db, items_dict)
    items: list[StockListItemOut] = []
    for item, cat_name, type_name, _ in page_slice:
        sup = sup_map.get(item.id)
        items.append(_item_to_list_row(item, cat_name, type_name, sup))
    return StockListOut(items=items, total=total, page=page, per_page=per_page)


@router.get("/critical", response_model=StockListOut)
async def critical_stock(
    business_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
    page: int = Query(1, ge=1),
    per_page: int = Query(50, ge=1, le=2000),
):
    return await list_stock(
        business_id,
        db,
        _m,
        page=page,
        per_page=per_page,
        status="critical",
    )


@router.get("/barcode/lookup", response_model=BarcodeLookupOut)
async def barcode_lookup(
    business_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
    code: str = Query(..., min_length=1),
):
    code_s = code.strip()
    r = await db.execute(
        select(CatalogItem).where(
            CatalogItem.business_id == business_id,
            CatalogItem.barcode == code_s,
            CatalogItem.deleted_at.is_(None),
        )
    )
    item = r.scalar_one_or_none()
    if item is None:
        r2 = await db.execute(
            select(CatalogItem).where(
                CatalogItem.business_id == business_id,
                CatalogItem.item_code == code_s,
                CatalogItem.deleted_at.is_(None),
            )
        )
        item = r2.scalar_one_or_none()
    if not item:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Item not found")
    label = await _barcode_label(db, business_id, item)
    return BarcodeLookupOut(
        id=item.id,
        name=item.name,
        item_code=item.item_code,
        barcode=getattr(item, "barcode", None),
        current_stock=label.current_stock or catalog_stock_qty(item),
        reorder_level=catalog_reorder(item),
        unit=label.unit,
        last_purchase_date=label.last_purchase_date,
        last_purchase_qty=label.last_purchase_qty,
        last_purchase_unit=label.last_purchase_unit,
        last_purchase_rate=label.last_purchase_rate,
        supplier_name=label.supplier_name,
    )


async def _adjustments_to_out(
    db: AsyncSession,
    business_id: uuid.UUID,
    logs: list[StockAdjustmentLog],
) -> list[StockAdjustmentOut]:
    if not logs:
        return []
    item_ids = {log.item_id for log in logs}
    ir = await db.execute(
        select(CatalogItem).where(
            CatalogItem.business_id == business_id,
            CatalogItem.id.in_(item_ids),
        )
    )
    items = {i.id: i for i in ir.scalars().all()}
    out: list[StockAdjustmentOut] = []
    for log in logs:
        item = items.get(log.item_id)
        var_exp: Decimal | None = None
        var_delta: Decimal | None = None
        if log.adjustment_type in ("verification", "correction", "manual"):
            exp = await _last_purchase_expected_qty(db, business_id, log.item_id)
            if exp is not None:
                var_exp = exp
                var_delta = log.new_qty - exp
        out.append(
            StockAdjustmentOut(
                id=log.id,
                item_id=log.item_id,
                item_name=item.name if item else None,
                item_code=item.item_code if item else None,
                unit=(item.stock_unit or item.default_unit) if item else None,
                old_qty=log.old_qty,
                new_qty=log.new_qty,
                adjustment_type=log.adjustment_type,
                reason=log.reason,
                updated_by_name=log.updated_by_name,
                updated_at=log.updated_at,
                variance_expected_qty=var_exp,
                variance_delta=var_delta,
            )
        )
    return out


@router.get("/alerts/summary", response_model=StockAlertsSummaryOut)
async def stock_alerts_summary(
    business_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
):
    """Operational alert counts for owner home strip."""
    today = date.today()
    low = crit = out = active_out = missing_barcode = missing_item_code = eviction = 0
    catalog_total = 0
    ir = await db.execute(
        select(
            CatalogItem.current_stock,
            CatalogItem.reorder_level,
            CatalogItem.item_code,
            CatalogItem.barcode,
            CatalogItem.last_purchase_at,
            CatalogItem.opening_stock_qty,
            CatalogItem.eviction_days,
            ItemCategory.is_perishable,
        )
        .join(ItemCategory, CatalogItem.category_id == ItemCategory.id)
        .where(
            CatalogItem.business_id == business_id,
            CatalogItem.deleted_at.is_(None),
        )
    )
    for row in ir.all():
        catalog_total += 1
        cur, ro, code, barcode, lpa, opening_qty, ev_days, perish = row
        cur_d = Decimal(cur or 0)
        ro_d = Decimal(ro or 0)
        st = stock_status(cur_d, ro_d)
        if st == "low":
            low += 1
        elif st == "critical":
            crit += 1
        elif st == "out":
            out += 1
            opening_set = opening_qty is not None and Decimal(opening_qty) > 0
            if opening_set or lpa is not None:
                active_out += 1
        if not (barcode and str(barcode).strip()):
            missing_barcode += 1
        if not (code and str(code).strip()):
            missing_item_code += 1
        if perish and cur_d > 0 and ev_days and lpa:
            days = max(0, (datetime.now(timezone.utc) - lpa).days)
            if days > int(ev_days):
                eviction += 1
    lr = await db.execute(
        select(func.count(DailyUsageLog.id)).where(
            DailyUsageLog.business_id == business_id,
            DailyUsageLog.usage_date == today,
        )
    )
    logged = int(lr.scalar_one() or 0)
    return StockAlertsSummaryOut(
        low_stock=low,
        critical_stock=crit,
        out_of_stock=out,
        active_out_of_stock=active_out,
        missing_barcode=missing_barcode,
        missing_item_code=missing_item_code,
        missing_usage_logs=max(0, catalog_total - logged),
        eviction_count=eviction,
        total_items=catalog_total,
    )


@router.get("/warehouse/alerts-summary", response_model=WarehouseAlertsSummaryOut)
async def warehouse_alerts_summary(
    business_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
):
    """Collapsed owner-home alert summary to avoid Flutter provider waterfalls."""
    stock = await stock_alerts_summary(business_id=business_id, db=db, _m=_m)
    today = date.today()

    pending_deliveries_q = await db.execute(
        select(func.count(TradePurchase.id)).where(
            TradePurchase.business_id == business_id,
            TradePurchase.status.notin_(("cancelled", "deleted")),
            TradePurchase.is_delivered.is_(False),
        )
    )
    pending_deliveries = int(pending_deliveries_q.scalar_one() or 0)

    variances_q = await db.execute(
        select(func.count(StockAdjustmentLog.id)).where(
            StockAdjustmentLog.business_id == business_id,
            StockAdjustmentLog.adjustment_type.in_(("verification", "correction", "manual")),
            func.date(StockAdjustmentLog.updated_at) == today,
        )
    )
    pending_verifications = int(variances_q.scalar_one() or 0)

    templates_q = await db.execute(
        select(func.count())
        .select_from(StaffChecklistTemplate)
        .where(
            or_(
                StaffChecklistTemplate.business_id == business_id,
                StaffChecklistTemplate.business_id.is_(None),
            )
        )
    )
    checklist_total = int(templates_q.scalar_one() or 0)
    completed_q = await db.execute(
        select(func.count(func.distinct(StaffChecklistCompletion.task_key))).where(
            StaffChecklistCompletion.business_id == business_id,
            StaffChecklistCompletion.checklist_date == today,
        )
    )
    checklist_done = int(completed_q.scalar_one() or 0)
    checklist_completion_pct = (
        round((checklist_done / checklist_total) * 100, 1) if checklist_total > 0 else 100.0
    )

    return WarehouseAlertsSummaryOut(
        pending_deliveries=pending_deliveries,
        low_stock=stock.low_stock,
        critical_stock=stock.critical_stock,
        pending_verifications=pending_verifications,
        missing_barcode=stock.missing_barcode,
        missing_usage_logs=stock.missing_usage_logs,
        eviction_count=stock.eviction_count,
        checklist_completion_pct=checklist_completion_pct,
        total_items=stock.total_items,
    )


LowStockOpsFilter = Literal[
    "all",
    "low",
    "out",
    "pending",
    "delayed",
    "disputed",
    "verification",
    "urgent",
    "high_impact",
]

LowStockOpsSort = Literal["priority", "stock_asc", "name"]


def _days_between(period_start: date | None, period_end: date | None) -> int:
    if not period_start or not period_end:
        return 0
    return max(0, (period_end - period_start).days) + 1


async def _fetch_low_stock_candidates(
    *,
    business_id: uuid.UUID,
    db: AsyncSession,
    membership: Membership,
    q: str,
    category: str,
    subcategory: str,
    status: StatusFilter,
    period_start: str | None,
    period_end: str | None,
    fetch_per_page: int,
    max_pages: int,
) -> tuple[int, dict[uuid.UUID, StockListItemOut]]:
    """Fetch a capped set of low-stock candidates for server-side priority sorting."""
    ps, pe = _parse_period_dates(period_start, period_end)
    period_days = _days_between(ps, pe)
    # If period is not provided, we still fetch items; priority score just uses
    # reorder_gap + mismatch + verification signals.
    if period_days <= 0:
        include_period = False
    else:
        include_period = True

    merged: dict[uuid.UUID, StockListItemOut] = {}
    total_seen = 0
    for page in range(1, max_pages + 1):
        out = await list_stock(
            business_id=business_id,
            db=db,
            _m=membership,
            page=page,
            per_page=fetch_per_page,
            q=q,
            category=category,
            subcategory=subcategory,
            status=status,
            sort="stock_asc",
            include_period=include_period,
            period_start=period_start,
            period_end=period_end,
            include_today=False,
        )
        total_seen = out.total
        for it in out.items:
            merged[it.id] = it
        # Stop early once the page is empty.
        if not out.items or len(merged) >= total_seen:
            break
    return total_seen, merged


async def _enrich_low_stock_ops_rows(
    db: AsyncSession,
    business_id: uuid.UUID,
    items: list[StockListItemOut],
) -> list[LowStockOpsItemOut]:
    """Attach priority, lifecycle, reorder, and dispute signals to stock rows."""
    item_ids = [it.id for it in items]
    reorder_map = await reorder_status_map(db, business_id, item_ids)
    dispute_ids = await open_dispute_item_ids(db, business_id, item_ids)
    rejected_ids = await rejected_audit_item_ids(db, business_id, item_ids)

    out: list[LowStockOpsItemOut] = []
    for it in items:
        pr = compute_low_stock_priority(it)
        ro_status = reorder_map.get(it.id)
        open_dispute = it.id in dispute_ids
        disputed = item_is_disputed(
            it,
            open_disputes=dispute_ids,
            rejected_audits=rejected_ids,
        )
        lifecycle = derive_lifecycle_stage(
            it,
            reorder_entry_status=ro_status,
            has_open_dispute=open_dispute or it.id in rejected_ids,
        )
        verification_state = "pending" if pr.needs_verification else "none"
        out.append(
            LowStockOpsItemOut(
                **it.model_dump(),
                priority_score=pr.score,
                priority_band=pr.band,
                is_delayed_supplier=pr.delayed_flag,
                has_mismatch=pr.mismatch_flag,
                verification_state=verification_state,
                lifecycle_stage=lifecycle,
                reorder_entry_status=ro_status,
                has_open_dispute=open_dispute or disputed,
            )
        )
    return out


@router.get("/low-stock/summary", response_model=LowStockOpsSummaryOut)
async def low_stock_operations_summary(
    business_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
    q: str = Query(""),
    category: str = Query(""),
    subcategory: str = Query(""),
    period_start: str | None = Query(None),
    period_end: str | None = Query(None),
):
    """KPIs for the low-stock operations header."""
    ps, pe = _parse_period_dates(period_start, period_end)
    period_days = _days_between(ps, pe)

    # Fetch low/critical/out candidates in one sweep (capped).
    fetch_per_page = 200
    max_pages = 12
    _, merged = await _fetch_low_stock_candidates(
        business_id=business_id,
        db=db,
        membership=_m,
        q=q,
        category=category,
        subcategory=subcategory,
        status="shortage",  # type: ignore[arg-type]
        period_start=period_start,
        period_end=period_end,
        fetch_per_page=fetch_per_page,
        max_pages=max_pages,
    )

    total_attention = 0
    out_of_stock = 0
    pending_purchase = 0
    delayed_supplier = 0
    mismatch_items = 0
    pending_verification = 0
    disputed_items = 0

    impact_units_per_day = 0.0
    usage_sum: Decimal = Decimal(0)
    merged_list = list(merged.values())
    item_ids = [it.id for it in merged_list]
    dispute_ids = await open_dispute_item_ids(db, business_id, item_ids)
    rejected_ids = await rejected_audit_item_ids(db, business_id, item_ids)

    for it in merged_list:
        pr = compute_low_stock_priority(it)
        # attention = low/critical/out shortage bucket
        is_out = pr.out_of_stock_flag
        if pr.out_of_stock_flag or it.stock_status.lower() in ("low", "critical"):
            total_attention += 1
        if is_out:
            out_of_stock += 1
        if it.has_pending_order:
            pending_purchase += 1
        if pr.delayed_flag:
            delayed_supplier += 1
        if pr.mismatch_flag:
            mismatch_items += 1
        if item_is_disputed(
            it,
            open_disputes=dispute_ids,
            rejected_audits=rejected_ids,
        ):
            disputed_items += 1
        if pr.needs_verification:
            pending_verification += 1
        if it.period_usage_qty is not None:
            usage_sum += it.period_usage_qty

    if period_days > 0:
        impact_units_per_day = float(usage_sum / Decimal(period_days))

    return LowStockOpsSummaryOut(
        total_attention=total_attention,
        out_of_stock=out_of_stock,
        pending_purchase=pending_purchase,
        delayed_supplier=delayed_supplier,
        mismatch_items=mismatch_items,
        pending_verification=pending_verification,
        disputed_items=disputed_items,
        estimated_impact_units_per_day=impact_units_per_day,
    )


@router.get("/low-stock/operations", response_model=LowStockOpsOut)
async def low_stock_operations(
    business_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
    page: int = Query(1, ge=1),
    per_page: int = Query(50, ge=1, le=200),
    q: str = Query(""),
    filter: LowStockOpsFilter = Query("all"),
    category: str = Query(""),
    subcategory: str = Query(""),
    supplier_id: uuid.UUID | None = Query(None),
    sort: LowStockOpsSort = Query("priority"),
    period_start: str | None = Query(None),
    period_end: str | None = Query(None),
):
    """Paginated low-stock operations list (priority-sorted v1)."""
    ps, pe = _parse_period_dates(period_start, period_end)
    period_days = _days_between(ps, pe)

    fetch_per_page = min(200, per_page * 4)
    max_pages = 20
    _, merged = await _fetch_low_stock_candidates(
        business_id=business_id,
        db=db,
        membership=_m,
        q=q,
        category=category,
        subcategory=subcategory,
        status="shortage",  # type: ignore[arg-type]
        period_start=period_start,
        period_end=period_end,
        fetch_per_page=fetch_per_page,
        max_pages=max_pages,
    )

    items = list(merged.values())
    if supplier_id is not None and items:
        item_ids = [it.id for it in items]
        supplier_rows = await db.execute(
            select(CatalogItem.id, CatalogItem.last_supplier_id).where(
                CatalogItem.business_id == business_id,
                CatalogItem.id.in_(item_ids),
                CatalogItem.deleted_at.is_(None),
            )
        )
        supplier_by_item = {iid: sid for iid, sid in supplier_rows.all()}
        items = [
            it
            for it in items
            if supplier_by_item.get(it.id) is not None
            and supplier_by_item.get(it.id) == supplier_id
        ]

    # High-impact threshold (v1): usage quantile across fetched items.
    usage_vals = [float(it.period_usage_qty or 0) for it in items]
    usage_vals = [v for v in usage_vals if v > 0.0]
    usage_vals.sort()
    high_threshold = usage_vals[int(len(usage_vals) * 0.75)] if usage_vals else 0.0

    item_ids = [it.id for it in items]
    dispute_ids = await open_dispute_item_ids(db, business_id, item_ids)
    rejected_ids = await rejected_audit_item_ids(db, business_id, item_ids)

    passing: list[StockListItemOut] = []
    for it in items:
        pr = compute_low_stock_priority(it)
        delayed_supplier = pr.delayed_flag
        disputed = item_is_disputed(
            it,
            open_disputes=dispute_ids,
            rejected_audits=rejected_ids,
        )

        ok = True
        if filter != "all":
            if filter == "low":
                ok = it.stock_status.lower() in ("low", "critical") and not pr.out_of_stock_flag
            elif filter == "out":
                ok = pr.out_of_stock_flag
            elif filter == "pending":
                ok = it.has_pending_order
            elif filter == "delayed":
                ok = delayed_supplier
            elif filter == "disputed":
                ok = disputed
            elif filter == "verification":
                ok = pr.needs_verification
            elif filter == "urgent":
                ok = pr.band in ("critical", "high")
            elif filter == "high_impact":
                usage = float(it.period_usage_qty or 0)
                ok = usage >= high_threshold and high_threshold > 0
        if not ok:
            continue

        if q.strip():
            hay = " ".join(
                str(x).lower()
                for x in (
                    it.name,
                    it.item_code,
                    it.barcode,
                    it.supplier_name,
                    it.category_name,
                    it.subcategory_name,
                    it.last_stock_updated_by,
                    it.last_purchase_human_id,
                )
                if x is not None
            )
            if q.strip().lower() not in hay:
                continue

        passing.append(it)

    filtered = await _enrich_low_stock_ops_rows(db, business_id, passing)

    # Sort & paginate
    if sort == "stock_asc":
        filtered.sort(key=lambda x: float(x.current_stock))
    elif sort == "name":
        filtered.sort(key=lambda x: (x.name or "").lower())
    else:
        filtered.sort(key=lambda x: x.priority_score, reverse=True)

    total = len(filtered)
    start = (page - 1) * per_page
    page_items = filtered[start : start + per_page]

    # Summary slice for current query (counts include filter selections).
    # Header UI uses global summary; for now keep slice-aligned.
    pending_verification_cnt = sum(1 for it in filtered if it.needs_verification)
    out_cnt = sum(1 for it in filtered if it.stock_status.lower() == "out" or float(it.current_stock) <= 0)
    pending_cnt = sum(1 for it in filtered if it.has_pending_order)
    delayed_cnt = sum(1 for it in filtered if it.is_delayed_supplier)
    mismatch_cnt = sum(1 for it in filtered if it.has_mismatch)
    disputed_cnt = sum(1 for it in filtered if it.has_open_dispute)
    total_attention = total
    usage_sum: Decimal = Decimal(0)
    for it in filtered:
        if it.period_usage_qty is not None:
            usage_sum += it.period_usage_qty
    impact = float(usage_sum / Decimal(period_days)) if period_days > 0 else 0.0

    return LowStockOpsOut(
        summary_slice=LowStockOpsSummaryOut(
            total_attention=total_attention,
            out_of_stock=out_cnt,
            pending_purchase=pending_cnt,
            delayed_supplier=delayed_cnt,
            mismatch_items=mismatch_cnt,
            pending_verification=pending_verification_cnt,
            disputed_items=disputed_cnt,
            estimated_impact_units_per_day=impact,
        ),
        items=page_items,
        total=total,
        page=page,
        per_page=per_page,
    )


@router.get("/audit/feed", response_model=list[StockAdjustmentOut])
async def audit_feed(
    business_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
    limit: int = Query(50, ge=1, le=200),
    on: date | None = Query(None),
):
    """Alias for owner-wide stock change feed."""
    return await recent_adjustments_all(business_id, db, _m, limit=limit, on=on)


@router.get("/audit/recent", response_model=list[StockAdjustmentOut])
async def recent_adjustments_all(
    business_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
    limit: int = Query(5, ge=1, le=250),
    on: date | None = Query(None, description="Filter to calendar day (UTC) YYYY-MM-DD"),
):
    stmt = select(StockAdjustmentLog).where(
        StockAdjustmentLog.business_id == business_id,
    )
    if on is not None:
        start = datetime.combine(on, time.min, tzinfo=timezone.utc)
        end = datetime.combine(on, time.max, tzinfo=timezone.utc)
        stmt = stmt.where(
            StockAdjustmentLog.updated_at >= start,
            StockAdjustmentLog.updated_at <= end,
        )
    r = await db.execute(stmt.order_by(desc(StockAdjustmentLog.updated_at)).limit(limit))
    return await _adjustments_to_out(db, business_id, list(r.scalars().all()))


@router.get("/variances/today", response_model=list[StockVarianceOut])
async def variances_today(
    business_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
):
    day = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    start = datetime.combine(date.fromisoformat(day), time.min, tzinfo=timezone.utc)
    r = await db.execute(
        select(AppNotification)
        .where(
            AppNotification.business_id == business_id,
            AppNotification.kind == "stock_variance",
            AppNotification.created_at >= start,
        )
        .order_by(desc(AppNotification.created_at))
        .limit(50)
    )
    rows: list[StockVarianceOut] = []
    seen: set[str] = set()
    for n in r.scalars().all():
        p = n.payload or {}
        iid = p.get("item_id")
        if not iid or iid in seen:
            continue
        seen.add(iid)
        rows.append(
            StockVarianceOut(
                item_id=uuid.UUID(str(iid)),
                item_name=str(p.get("item_name") or "Item"),
                expected_qty=Decimal(str(p.get("expected_qty", 0))),
                found_qty=Decimal(str(p.get("found_qty", 0))),
                variance_delta=Decimal(str(p.get("variance_delta", 0))),
                unit=p.get("unit"),
                updated_at=n.created_at,
            )
        )
    return rows


@router.get("/audit/{item_id}", response_model=list[StockAdjustmentOut])
async def audit_for_item(
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
):
    r = await db.execute(
        select(StockAdjustmentLog)
        .where(
            StockAdjustmentLog.business_id == business_id,
            StockAdjustmentLog.item_id == item_id,
        )
        .order_by(desc(StockAdjustmentLog.updated_at))
        .limit(50)
    )
    return await _adjustments_to_out(db, business_id, list(r.scalars().all()))


@router.get("/{item_id}/activity", response_model=StockItemActivityOut)
async def stock_item_activity(
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    membership: Annotated[Membership, Depends(require_membership)],
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0, le=5000),
    kind: str | None = Query(None, description="Comma-separated movement kinds filter (purchase,physical_count,damage,correction,sale,transfer,staff_purchase_log,staff_activity_log)."),
):
    item = await get_stock_item(business_id, item_id, db, membership)
    kinds = [k.strip() for k in (kind or "").split(",") if k.strip()]
    movement_q = (
        select(StockMovement)
        .where(
            StockMovement.business_id == business_id,
            StockMovement.item_id == item_id,
        )
        .order_by(desc(StockMovement.created_at))
        .offset(offset)
        .limit(limit)
    )
    if kinds:
        movement_q = movement_q.where(StockMovement.movement_kind.in_(kinds))
    movement_r = await db.execute(movement_q)
    movements = list(movement_r.scalars().all())
    purchase_q = (
        select(StaffPurchaseLog)
        .where(
            StaffPurchaseLog.business_id == business_id,
            StaffPurchaseLog.item_id == item_id,
        )
        .order_by(desc(StaffPurchaseLog.created_at))
        .offset(offset)
        .limit(limit)
    )
    if kinds and "staff_purchase_log" not in kinds:
        purchase_q = purchase_q.where(literal(False))
    purchase_r = await db.execute(purchase_q)
    purchases = list(purchase_r.scalars().all())
    staff_q = (
        select(StaffActivityLog)
        .where(
            StaffActivityLog.business_id == business_id,
            StaffActivityLog.item_id == item_id,
        )
        .order_by(desc(StaffActivityLog.created_at))
        .offset(offset)
        .limit(limit)
    )
    if kinds:
        # staff log uses action_type as kind, but keep it behind explicit allow.
        allow_staff = "staff_activity_log" in kinds
        if not allow_staff:
            staff_q = staff_q.where(literal(False))
    staff_r = await db.execute(staff_q)
    staff_events = list(staff_r.scalars().all())
    events: list[StockActivityEventOut] = []
    for m in movements:
        title = {
            "quick_purchase": "Purchase quantity added",
            "physical_count": "Physical stock updated",
            "damage": "Damage recorded",
            "correction": "Stock corrected",
            "sale": "Sale adjustment",
        }.get(m.movement_kind, m.movement_kind.replace("_", " ").title())
        events.append(
            StockActivityEventOut(
                id=str(m.id),
                kind=m.movement_kind,
                title=title,
                qty_before=m.qty_before,
                qty_after=m.qty_after,
                delta_qty=m.delta_qty,
                unit=m.stock_unit,
                reason=m.reason,
                notes=m.notes,
                actor_name=m.actor_name,
                created_at=m.created_at,
                source_type=m.source_type,
                source_id=str(m.source_id) if m.source_id else None,
            )
        )
    for p in purchases:
        events.append(
            StockActivityEventOut(
                id=str(p.id),
                kind="staff_purchase_log",
                title="Staff purchase entry",
                delta_qty=p.qty,
                unit=p.unit,
                notes=p.notes,
                actor_name=p.created_by_name,
                supplier_name=p.supplier_name,
                broker_name=getattr(p, "broker_name", None),
                created_at=p.created_at,
                source_type="staff_purchase_log",
                source_id=str(p.id),
            )
        )
    for ev in staff_events:
        events.append(
            StockActivityEventOut(
                id=str(ev.id),
                kind=ev.action_type,
                title=ev.action_type.replace("_", " ").title(),
                actor_name=ev.user_name,
                notes=None,
                created_at=ev.created_at,
                source_type="staff_activity_log",
                source_id=str(ev.id),
            )
        )
    events.sort(key=lambda e: e.created_at, reverse=True)
    return StockItemActivityOut(
        item=item,
        movements=[_movement_out(m, item_name=item.name) for m in movements],
        purchases=[_staff_purchase_out(p) for p in purchases],
        activity=events[:limit],
    )


async def _barcode_label(
    db: AsyncSession, business_id: uuid.UUID, item: CatalogItem
) -> BarcodeLabelOut:
    cat_name: str | None = None
    if item.category_id:
        cr = await db.execute(select(ItemCategory.name).where(ItemCategory.id == item.category_id))
        cat_name = cr.scalar_one_or_none()
    purchases = await _recent_purchases(db, item, limit=1)
    lp = purchases[0] if purchases else None
    sup = await _supplier_name(db, item)
    bc = getattr(item, "barcode", None) or item.item_code
    return BarcodeLabelOut(
        id=item.id,
        barcode=bc,
        item_code=item.item_code,
        item_name=item.name,
        category_name=cat_name,
        unit=item.stock_unit or item.default_unit,
        current_stock=catalog_stock_qty(item),
        last_purchase_date=lp.purchase_date if lp else None,
        last_purchase_qty=lp.qty if lp else None,
        last_purchase_unit=lp.unit if lp else None,
        last_purchase_rate=lp.rate if lp else None,
        supplier_name=sup,
    )


@router.get("/barcode/{item_id}", response_model=BarcodeLabelOut)
async def barcode_label(
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
):
    r = await db.execute(
        select(CatalogItem).where(
            CatalogItem.id == item_id,
            CatalogItem.business_id == business_id,
            CatalogItem.deleted_at.is_(None),
        )
    )
    item = r.scalar_one_or_none()
    if not item:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Item not found")
    return await _barcode_label(db, business_id, item)


async def _latest_purchase_by_item(
    db: AsyncSession,
    items: dict[uuid.UUID, CatalogItem],
) -> dict[uuid.UUID, RecentPurchaseOut]:
    """One query for latest purchase line per catalog item (bulk label print)."""
    if not items:
        return {}
    ids = list(items.keys())
    r = await db.execute(
        select(TradePurchaseLine, TradePurchase, Supplier.name)
        .join(TradePurchase, TradePurchaseLine.trade_purchase_id == TradePurchase.id)
        .outerjoin(Supplier, TradePurchase.supplier_id == Supplier.id)
        .where(TradePurchaseLine.catalog_item_id.in_(ids))
        .order_by(
            TradePurchaseLine.catalog_item_id,
            desc(TradePurchase.purchase_date),
        )
    )
    out: dict[uuid.UUID, RecentPurchaseOut] = {}
    for line, tp, sup_name in r.all():
        cid = line.catalog_item_id
        if cid in out:
            continue
        item = items.get(cid)
        if item is None:
            continue
        pd = tp.purchase_date
        if pd is not None and not isinstance(pd, datetime):
            from datetime import date as date_cls

            if isinstance(pd, date_cls):
                pd = datetime.combine(pd, datetime.min.time(), tzinfo=timezone.utc)
        su = catalog_stock_unit(item)
        qty_su = line_qty_in_stock_unit(line, item)
        out[cid] = RecentPurchaseOut(
            id=tp.id,
            invoice_number=tp.invoice_number,
            human_id=tp.human_id,
            purchase_date=pd,
            qty=line.qty,
            unit=line.unit,
            entered_qty=line.qty,
            entered_unit=line.unit,
            qty_in_stock_unit=qty_su,
            stock_unit=su,
            rate=getattr(line, "landing_cost", None) or getattr(line, "purchase_rate", None),
            supplier_name=sup_name,
        )
    return out


async def _supplier_names_bulk(
    db: AsyncSession, items: dict[uuid.UUID, CatalogItem]
) -> dict[uuid.UUID, str | None]:
    sup_ids = {i.last_supplier_id for i in items.values() if i.last_supplier_id}
    if not sup_ids:
        return {}
    r = await db.execute(select(Supplier.id, Supplier.name).where(Supplier.id.in_(sup_ids)))
    names = {row[0]: row[1] for row in r.all()}
    return {
        iid: names.get(item.last_supplier_id)
        for iid, item in items.items()
        if item.last_supplier_id
    }


async def _category_names_bulk(
    db: AsyncSession, items: dict[uuid.UUID, CatalogItem]
) -> dict[uuid.UUID, str | None]:
    cat_ids = {i.category_id for i in items.values() if i.category_id}
    if not cat_ids:
        return {}
    r = await db.execute(
        select(ItemCategory.id, ItemCategory.name).where(ItemCategory.id.in_(cat_ids))
    )
    names = {row[0]: row[1] for row in r.all()}
    return {
        iid: names.get(item.category_id)
        for iid, item in items.items()
        if item.category_id
    }


def _barcode_label_from_parts(
    item: CatalogItem,
    *,
    category_name: str | None,
    lp: RecentPurchaseOut | None,
    supplier_name: str | None,
) -> BarcodeLabelOut:
    bc = getattr(item, "barcode", None) or item.item_code
    return BarcodeLabelOut(
        id=item.id,
        barcode=bc,
        item_code=item.item_code,
        item_name=item.name,
        category_name=category_name,
        unit=item.stock_unit or item.default_unit,
        current_stock=catalog_stock_qty(item),
        last_purchase_date=lp.purchase_date if lp else None,
        last_purchase_qty=lp.qty if lp else None,
        last_purchase_unit=lp.unit if lp else None,
        last_purchase_rate=lp.rate if lp else None,
        supplier_name=supplier_name,
    )


@router.post("/barcode/batch", response_model=BarcodeBatchOut)
async def barcode_batch(
    business_id: uuid.UUID,
    body: BarcodeBatchIn,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_permission("barcode_print"))],
):
    r = await db.execute(
        select(CatalogItem).where(
            CatalogItem.business_id == business_id,
            CatalogItem.id.in_(body.item_ids),
            CatalogItem.deleted_at.is_(None),
        )
    )
    items = {i.id: i for i in r.scalars().all()}
    if not items:
        return BarcodeBatchOut(labels=[])
    lp_map = await _latest_purchase_by_item(db, items)
    sup_map = await _supplier_names_bulk(db, items)
    cat_map = await _category_names_bulk(db, items)
    labels: list[BarcodeLabelOut] = []
    for iid in body.item_ids:
        item = items.get(iid)
        if item:
            labels.append(
                _barcode_label_from_parts(
                    item,
                    category_name=cat_map.get(item.id),
                    lp=lp_map.get(item.id),
                    supplier_name=sup_map.get(item.id),
                )
            )
    return BarcodeBatchOut(labels=labels)


async def _recent_purchases(
    db: AsyncSession,
    item: CatalogItem,
    limit: int = 5,
) -> list[RecentPurchaseOut]:
    r = await db.execute(
        select(TradePurchaseLine, TradePurchase, Supplier.name)
        .join(TradePurchase, TradePurchaseLine.trade_purchase_id == TradePurchase.id)
        .outerjoin(Supplier, TradePurchase.supplier_id == Supplier.id)
        .where(TradePurchaseLine.catalog_item_id == item.id)
        .order_by(desc(TradePurchase.purchase_date))
        .limit(limit)
    )
    su = catalog_stock_unit(item)
    out: list[RecentPurchaseOut] = []
    for line, tp, sup_name in r.all():
        pd = tp.purchase_date
        if pd is not None and not isinstance(pd, datetime):
            from datetime import date as date_cls

            if isinstance(pd, date_cls):
                pd = datetime.combine(pd, datetime.min.time(), tzinfo=timezone.utc)
        qty_su = line_qty_in_stock_unit(line, item)
        out.append(
            RecentPurchaseOut(
                id=tp.id,
                invoice_number=tp.invoice_number,
                human_id=tp.human_id,
                purchase_date=pd,
                qty=line.qty,
                unit=line.unit,
                entered_qty=line.qty,
                entered_unit=line.unit,
                qty_in_stock_unit=qty_su,
                stock_unit=su,
                rate=getattr(line, "landing_cost", None) or getattr(line, "purchase_rate", None),
                supplier_name=sup_name,
            )
        )
    return out


@router.get("/reorder", response_model=ReorderListOut)
async def list_reorder_entries(
    business_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
    status: str = "pending",
):
    st = (status or "pending").strip().lower()
    if st not in ("pending", "ordered", "done", "all"):
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="Invalid status filter")

    q = (
        select(ReorderListEntry, CatalogItem)
        .join(CatalogItem, CatalogItem.id == ReorderListEntry.item_id)
        .where(
            ReorderListEntry.business_id == business_id,
            CatalogItem.deleted_at.is_(None),
        )
        .order_by(ReorderListEntry.created_at.desc())
    )
    if st != "all":
        q = q.where(ReorderListEntry.status == st)
    rows = (await db.execute(q)).all()
    items_dict = {item.id: item for _, item in rows}
    sup_map = await _supplier_names_bulk(db, items_dict)
    items: list[ReorderListEntryOut] = []
    for entry, item in rows:
        cur = catalog_stock_qty(item)
        ro = catalog_reorder(item)
        sup = sup_map.get(item.id)
        purchases = await _recent_purchases(db, item, limit=1)
        lp = purchases[0] if purchases else None
        items.append(
            ReorderListEntryOut(
                id=entry.id,
                item_id=item.id,
                item_name=item.name,
                item_code=item.item_code,
                current_stock=cur,
                reorder_level=ro,
                unit=item.default_unit,
                status=entry.status,
                added_by_name=entry.added_by_name,
                supplier_name=sup,
                last_purchase_rate=lp.rate if lp else None,
                created_at=entry.created_at,
                updated_at=entry.updated_at,
            )
        )
    return ReorderListOut(items=items, total=len(items))


@router.patch("/reorder/{entry_id}", response_model=ReorderListEntryOut)
async def patch_reorder_entry(
    business_id: uuid.UUID,
    entry_id: uuid.UUID,
    body: ReorderListPatchIn,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
):
    r = await db.execute(
        select(ReorderListEntry, CatalogItem)
        .join(CatalogItem, CatalogItem.id == ReorderListEntry.item_id)
        .where(
            ReorderListEntry.id == entry_id,
            ReorderListEntry.business_id == business_id,
        )
    )
    row = r.first()
    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Reorder entry not found")
    entry, item = row
    entry.status = body.status
    entry.updated_at = datetime.now(timezone.utc)
    await db.commit()
    await db.refresh(entry)
    return ReorderListEntryOut(
        id=entry.id,
        item_id=item.id,
        item_name=item.name,
        item_code=item.item_code,
        current_stock=catalog_stock_qty(item),
        reorder_level=catalog_reorder(item),
        unit=item.default_unit,
        status=entry.status,
        added_by_name=entry.added_by_name,
        created_at=entry.created_at,
        updated_at=entry.updated_at,
    )


@router.delete("/reorder/{entry_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_reorder_entry(
    business_id: uuid.UUID,
    entry_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
):
    r = await db.execute(
        select(ReorderListEntry).where(
            ReorderListEntry.id == entry_id,
            ReorderListEntry.business_id == business_id,
        )
    )
    entry = r.scalar_one_or_none()
    if entry is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Reorder entry not found")
    await db.delete(entry)
    await db.commit()


@router.get("/opening/missing", response_model=OpeningStockMissingOut)
async def missing_opening_stock(
    business_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
    limit: int = Query(100, ge=1, le=500),
):
    r = await db.execute(
        select(CatalogItem, ItemCategory.name, CategoryType.name)
        .join(ItemCategory, CatalogItem.category_id == ItemCategory.id)
        .outerjoin(CategoryType, CatalogItem.type_id == CategoryType.id)
        .where(
            CatalogItem.business_id == business_id,
            CatalogItem.deleted_at.is_(None),
            CatalogItem.opening_stock_set_at.is_(None),
        )
        .order_by(CatalogItem.name.asc())
        .limit(limit)
    )
    rows = r.all()
    count_r = await db.execute(
        select(func.count(CatalogItem.id)).where(
            CatalogItem.business_id == business_id,
            CatalogItem.deleted_at.is_(None),
            CatalogItem.opening_stock_set_at.is_(None),
        )
    )
    items_dict = {item.id: item for item, _, _ in rows}
    sup_map = await _supplier_names_bulk(db, items_dict)
    items = [
        _item_to_list_row(item, cat_name, type_name, sup_map.get(item.id))
        for item, cat_name, type_name in rows
    ]
    return OpeningStockMissingOut(
        items=items,
        missing_count=int(count_r.scalar_one() or 0),
    )


def _staff_purchase_out(log: StaffPurchaseLog) -> StaffPurchaseLogOut:
    return StaffPurchaseLogOut(
        id=log.id,
        item_id=log.item_id,
        item_name=log.item_name,
        qty=log.qty,
        unit=log.unit,
        amount=log.amount,
        supplier_id=getattr(log, "supplier_id", None),
        supplier_name=log.supplier_name,
        broker_id=getattr(log, "broker_id", None),
        broker_name=getattr(log, "broker_name", None),
        notes=log.notes,
        idempotency_key=getattr(log, "idempotency_key", None),
        stock_movement_id=getattr(log, "stock_movement_id", None),
        created_by_name=log.created_by_name,
        created_at=log.created_at,
    )


def _movement_out(
    movement: StockMovement,
    *,
    item_name: str | None = None,
    duplicate: bool = False,
) -> StockMovementOut:
    return StockMovementOut(
        id=movement.id,
        item_id=movement.item_id,
        item_name=item_name,
        movement_kind=movement.movement_kind,
        delta_qty=movement.delta_qty,
        qty_before=movement.qty_before,
        qty_after=movement.qty_after,
        stock_unit=movement.stock_unit,
        reason=movement.reason,
        notes=movement.notes,
        source_type=movement.source_type,
        source_id=movement.source_id,
        idempotency_key=movement.idempotency_key,
        actor_id=movement.actor_id,
        actor_name=movement.actor_name,
        created_at=movement.created_at,
        metadata_json=movement.metadata_json,
        duplicate=duplicate,
    )


async def _supplier_snapshot(
    db: AsyncSession,
    business_id: uuid.UUID,
    supplier_id: uuid.UUID | None,
) -> tuple[uuid.UUID | None, str | None]:
    if supplier_id is None:
        return None, None
    r = await db.execute(
        select(Supplier).where(
            Supplier.id == supplier_id,
            Supplier.business_id == business_id,
        )
    )
    supplier = r.scalar_one_or_none()
    if supplier is None:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="Invalid supplier")
    return supplier.id, supplier.name


async def _broker_snapshot(
    db: AsyncSession,
    business_id: uuid.UUID,
    broker_id: uuid.UUID | None,
) -> tuple[uuid.UUID | None, str | None]:
    if broker_id is None:
        return None, None
    r = await db.execute(
        select(Broker).where(
            Broker.id == broker_id,
            Broker.business_id == business_id,
        )
    )
    broker = r.scalar_one_or_none()
    if broker is None:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="Invalid broker")
    return broker.id, broker.name


@router.get("/staff-purchases", response_model=list[StaffPurchaseLogOut])
async def list_staff_purchase_logs(
    business_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
    item_id: uuid.UUID | None = Query(None),
    limit: int = Query(100, ge=1, le=500),
):
    stmt = select(StaffPurchaseLog).where(StaffPurchaseLog.business_id == business_id)
    if item_id:
        stmt = stmt.where(StaffPurchaseLog.item_id == item_id)
    r = await db.execute(stmt.order_by(desc(StaffPurchaseLog.created_at)).limit(limit))
    return [_staff_purchase_out(log) for log in r.scalars().all()]


@router.post("/staff-purchases", response_model=StaffPurchaseLogOut)
async def create_staff_purchase_log(
    business_id: uuid.UUID,
    body: StaffPurchaseLogIn,
    db: Annotated[AsyncSession, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
    _membership: Annotated[Membership, Depends(require_permission("stock_edit"))],
):
    qty = Decimal(body.qty)
    supplier_id, supplier_name = await _supplier_snapshot(db, business_id, body.supplier_id)
    broker_id, broker_name = await _broker_snapshot(db, business_id, body.broker_id)
    supplier_snapshot = supplier_name or (body.supplier_name.strip() if body.supplier_name else None)
    broker_snapshot = broker_name or (body.broker_name.strip() if body.broker_name else None)
    log_id = uuid.uuid4()
    idem = body.idempotency_key or f"staff-purchase:{log_id}"
    try:
        result = await apply_stock_movement(
            db,
            business_id=business_id,
            item_id=body.item_id,
            user=user,
            movement_kind="quick_purchase",
            mode="delta",
            qty=qty,
            reason="Staff purchase quantity",
            notes=body.notes,
            source_type="staff_purchase_log",
            source_id=log_id,
            idempotency_key=idem,
            metadata={
                "supplier_id": str(supplier_id) if supplier_id else None,
                "supplier_name": supplier_snapshot,
                "broker_id": str(broker_id) if broker_id else None,
                "broker_name": broker_snapshot,
                "amount": str(body.amount) if body.amount is not None else None,
            },
        )
    except ValueError as e:
        if str(e) == "Item not found":
            raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Item not found") from e
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail=str(e)) from e

    if result.duplicate:
        lr = await db.execute(
            select(StaffPurchaseLog).where(
                StaffPurchaseLog.business_id == business_id,
                StaffPurchaseLog.idempotency_key == idem,
            )
        )
        existing = lr.scalar_one_or_none()
        if existing is not None:
            return _staff_purchase_out(existing)

    item = result.item
    display = _user_display(user)
    unit = catalog_stock_unit(item)
    item.last_supplier_id = supplier_id or getattr(item, "last_supplier_id", None)
    item.last_broker_id = broker_id
    item.last_line_qty = qty
    item.last_line_unit = unit
    log = StaffPurchaseLog(
        id=log_id,
        business_id=business_id,
        item_id=item.id,
        item_name=item.name,
        qty=qty,
        unit=unit,
        amount=body.amount,
        supplier_id=supplier_id,
        supplier_name=supplier_snapshot,
        broker_id=broker_id,
        broker_name=broker_snapshot,
        notes=body.notes.strip() if body.notes else None,
        idempotency_key=idem,
        stock_movement_id=result.movement.id,
        created_by=user.id,
        created_by_name=display,
    )
    db.add(log)
    await db.commit()
    await db.refresh(log)
    publish_business_event(
        business_id,
        "stock.changed",
        {
            "item_id": str(item.id),
            "movement_id": str(result.movement.id),
            "kind": "quick_purchase",
        },
    )
    return _staff_purchase_out(log)


@router.post("/{item_id}/quick-purchase", response_model=QuickPurchaseOut)
async def create_item_quick_purchase(
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    body: QuickPurchaseIn,
    db: Annotated[AsyncSession, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
    membership: Annotated[Membership, Depends(require_permission("stock_edit"))],
):
    staff_body = StaffPurchaseLogIn(
        item_id=item_id,
        qty=body.qty,
        supplier_id=body.supplier_id,
        broker_id=body.broker_id,
        notes=body.notes,
        idempotency_key=body.idempotency_key,
    )
    log = await create_staff_purchase_log(business_id, staff_body, db, user, membership)
    movement_r = await db.execute(
        select(StockMovement).where(StockMovement.id == log.stock_movement_id)
    )
    movement = movement_r.scalar_one_or_none()
    if movement is None:
        raise HTTPException(status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Stock movement missing")
    item = await get_stock_item(business_id, item_id, db, membership)
    return QuickPurchaseOut(
        purchase_log=log,
        movement=_movement_out(movement, item_name=item.name),
        item=item,
    )


@router.get("/{item_id}/intelligence", response_model=StockIntelligenceOut)
async def get_stock_intelligence(
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
    period_start: str | None = Query(None),
    period_end: str | None = Query(None),
):
    r = await db.execute(
        select(CatalogItem, ItemCategory.name, CategoryType.name)
        .join(ItemCategory, CatalogItem.category_id == ItemCategory.id)
        .outerjoin(CategoryType, CatalogItem.type_id == CategoryType.id)
        .where(
            CatalogItem.id == item_id,
            CatalogItem.business_id == business_id,
            CatalogItem.deleted_at.is_(None),
        )
    )
    row = r.one_or_none()
    if not row:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Item not found")
    item, cat_name, type_name = row
    supplier_name = await _supplier_name(db, item)
    cur = catalog_stock_qty(item)
    ro = catalog_reorder(item)
    unit = item.stock_unit or item.default_unit or item.selling_unit
    purchased = Decimal("0")
    period_usage = Decimal("0")
    ps, pe = _parse_period_dates(period_start, period_end)
    if ps and pe:
        m = await _period_purchased_map(db, business_id, [item_id], ps, pe)
        purchased = m.get(item_id, Decimal("0"))
        um = await _period_usage_map(db, business_id, [item_id], ps, pe)
        period_usage = um.get(item_id, Decimal("0"))
    ledger_map = await _ledger_variance_map(db, business_id, [item])
    ledger_var = ledger_map.get(item_id)
    su = catalog_stock_unit(item)
    purchases = await _recent_purchases(db, item)
    if should_redact_financials(_m.role):
        purchases = [
            p.model_copy(update={"rate": None}) if hasattr(p, "model_copy") else p
            for p in purchases
        ]
    adj_r = await db.execute(
        select(StockAdjustmentLog)
        .where(
            StockAdjustmentLog.business_id == business_id,
            StockAdjustmentLog.item_id == item_id,
        )
        .order_by(desc(StockAdjustmentLog.updated_at))
        .limit(8)
    )
    adjustments = [
        StockAdjustmentOut.model_validate(a) for a in adj_r.scalars().all()
    ]
    profile = profile_from_catalog_item(item)
    return StockIntelligenceOut(
        id=item.id,
        item_code=item.item_code,
        name=item.name,
        category_name=cat_name,
        subcategory_name=type_name,
        supplier_name=supplier_name,
        barcode=getattr(item, "barcode", None),
        default_kg_per_bag=getattr(item, "default_kg_per_bag", None),
        stock_unit=su,
        stock_tracking=profile.as_dict(),
        current_stock_kg=stock_qty_kg_equivalent(item, cur),
        last_stock_updated_at=getattr(item, "last_stock_updated_at", None),
        last_stock_updated_by=getattr(item, "last_stock_updated_by", None),
        current_stock=cur,
        reorder_level=ro,
        unit=unit,
        stock_status=stock_status(cur, ro),
        period_purchased_qty=purchased,
        period_usage_qty=period_usage,
        period_variance_qty=ledger_var,
        ledger_variance_qty=ledger_var,
        needs_verification=(
            abs(ledger_var) / purchased > Decimal("0.1")
            if ledger_var is not None and purchased > 0
            else _needs_verification(cur, purchased)
        ),
        recent_purchases=purchases,
        recent_adjustments=adjustments,
    )


@router.get("/{item_id}", response_model=StockDetailOut)
async def get_stock_item(
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
    period_start: str | None = Query(None),
    period_end: str | None = Query(None),
):
    r = await db.execute(
        select(CatalogItem, ItemCategory.name, CategoryType.name)
        .join(ItemCategory, CatalogItem.category_id == ItemCategory.id)
        .outerjoin(CategoryType, CatalogItem.type_id == CategoryType.id)
        .where(
            CatalogItem.id == item_id,
            CatalogItem.business_id == business_id,
            CatalogItem.deleted_at.is_(None),
        )
    )
    row = r.one_or_none()
    if not row:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Item not found")
    item, cat_name, type_name = row
    sup = await _supplier_name(db, item)
    phys = (await _latest_physical_count_map(db, business_id, [item_id])).get(item_id)
    delivered_map, pending_lifetime_map = await _lifetime_purchase_qty_maps(
        db, business_id, [item_id]
    )
    total_delivered = delivered_map.get(item_id)
    total_pending_lifetime = pending_lifetime_map.get(item_id)
    pend = (await _pending_order_meta_map(db, business_id, [item_id])).get(
        item_id, (False, None, None)
    )
    ps, pe = _parse_period_dates(period_start, period_end)
    purchased = None
    usage = None
    ledger_var = None
    verify = False
    if ps and pe:
        period_map = await _period_purchased_map(db, business_id, [item_id], ps, pe)
        purchased = period_map.get(item_id)
        usage_map = await _period_usage_map(db, business_id, [item_id], ps, pe)
        usage = usage_map.get(item_id)
        ledger_map = await _ledger_variance_map(db, business_id, [item])
        ledger_var = ledger_map.get(item_id)
        cur = catalog_stock_qty(item)
        if ledger_var is not None and purchased is not None and purchased > 0:
            verify = abs(ledger_var) / purchased > Decimal("0.1")
        elif purchased is not None and purchased > 0:
            verify = _needs_verification(cur, purchased)
    base = _item_to_list_row(
        item,
        cat_name,
        type_name,
        sup,
        period_purchased_qty=purchased,
        period_usage_qty=usage,
        ledger_variance_qty=ledger_var,
        stock_unit=catalog_stock_unit(item),
        needs_verification=verify,
        has_pending_order=pend[0],
        pending_order_days=pend[1],
        pending_delivery_qty=pend[2],
        physical_stock_qty=phys.counted_qty if phys else None,
        physical_stock_difference_qty=phys.difference_qty if phys else None,
        physical_stock_counted_at=phys.counted_at if phys else None,
        physical_stock_counted_by=phys.counted_by_name if phys else None,
        total_delivered_qty=total_delivered,
        total_pending_delivery_qty=total_pending_lifetime or pend[2],
    )
    purchases = await _recent_purchases(db, item)
    if should_redact_financials(_m.role):
        purchases = [
            p.model_copy(update={"rate": None}) if hasattr(p, "model_copy") else p
            for p in purchases
        ]
    return StockDetailOut(**base.model_dump(), recent_purchases=purchases)


def _physical_count_out(
    item: CatalogItem,
    entry: StockPhysicalCount,
) -> PhysicalStockCountOut:
    return PhysicalStockCountOut(
        id=entry.id,
        item_id=entry.item_id,
        item_name=item.name,
        system_qty=entry.system_qty,
        counted_qty=entry.counted_qty,
        difference_qty=entry.difference_qty,
        purchased_qty=entry.purchased_qty,
        stock_unit=entry.stock_unit,
        period_start=entry.period_start.isoformat() if entry.period_start else None,
        period_end=entry.period_end.isoformat() if entry.period_end else None,
        notes=entry.notes,
        counted_by_name=entry.counted_by_name,
        counted_at=entry.counted_at,
    )


@router.post("/{item_id}/opening-stock", response_model=StockDetailOut)
async def set_opening_stock(
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    body: OpeningStockIn,
    db: Annotated[AsyncSession, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
    _m: Annotated[Membership, Depends(require_role("owner", "super_admin"))],
):
    r = await db.execute(
        select(CatalogItem).where(
            CatalogItem.id == item_id,
            CatalogItem.business_id == business_id,
            CatalogItem.deleted_at.is_(None),
        )
    )
    item = r.scalar_one_or_none()
    if not item:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Item not found")
    qty = Decimal(body.qty)
    prev_opening = getattr(item, "opening_stock_qty", None)
    already_set = item.opening_stock_set_at is not None
    if already_set and prev_opening is not None and qty != prev_opening:
        if not (body.reason and body.reason.strip()):
            raise HTTPException(
                status.HTTP_400_BAD_REQUEST,
                detail="Reason required when changing opening stock",
            )
    reason = (body.reason or "").strip() or "Opening stock setup"
    notes = body.notes.strip() if body.notes else None
    idem = body.idempotency_key
    if not idem and already_set:
        idem = f"opening_stock:{item_id}:{uuid.uuid4().hex[:12]}"
    try:
        result = await apply_stock_movement(
            db,
            business_id=business_id,
            item_id=item_id,
            user=user,
            movement_kind="opening_stock",
            mode="absolute",
            qty=qty,
            reason=reason,
            notes=notes,
            source_type="opening_stock_setup",
            idempotency_key=idem,
        )
    except ValueError as e:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail=str(e)) from e
    item = result.item
    display = _user_display(user)
    now = datetime.now(timezone.utc)
    item.opening_stock_qty = qty
    item.opening_stock_set_at = now
    item.opening_stock_set_by = display
    item.opening_stock_locked = True
    await db.commit()
    await db.refresh(result.movement)
    publish_business_event(
        business_id,
        "stock.changed",
        {
            "item_id": str(item_id),
            "movement_id": str(result.movement.id),
            "kind": "opening_stock",
        },
    )
    return await get_stock_item(
        business_id,
        item_id,
        db,
        _m,
        period_start=None,
        period_end=None,
    )


@router.post("/{item_id}/physical-count", response_model=PhysicalStockCountOut)
async def record_physical_stock_count(
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    body: PhysicalStockCountIn,
    db: Annotated[AsyncSession, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
    _membership: Annotated[Membership, Depends(require_permission("stock_edit"))],
):
    """Record a physical count without mutating authoritative stock."""
    r = await db.execute(
        select(CatalogItem).where(
            CatalogItem.id == item_id,
            CatalogItem.business_id == business_id,
            CatalogItem.deleted_at.is_(None),
        )
    )
    item = r.scalar_one_or_none()
    if not item:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Item not found")
    counted = Decimal(body.counted_qty)
    system_qty = catalog_stock_qty(item)
    ps, pe = _parse_period_dates(body.period_start, body.period_end)
    purchased_qty: Decimal | None = None
    if ps and pe:
        purchased_qty = (await _period_purchased_map(db, business_id, [item_id], ps, pe)).get(
            item_id, Decimal("0")
        )
    display = _user_display(user)
    entry = StockPhysicalCount(
        business_id=business_id,
        item_id=item_id,
        system_qty=system_qty,
        counted_qty=counted,
        difference_qty=counted - system_qty,
        purchased_qty=purchased_qty,
        stock_unit=catalog_stock_unit(item),
        period_start=ps,
        period_end=pe,
        notes=body.notes.strip() if body.notes else None,
        counted_by=user.id,
        counted_by_name=display,
    )
    db.add(entry)
    await log_staff_activity(
        db,
        business_id=business_id,
        user=user,
        action_type="PHYSICAL_STOCK_COUNT",
        item_id=item_id,
        item_name=item.name,
        before_data={"system_qty": float(system_qty)},
        after_data={"counted_qty": float(counted), "difference_qty": float(counted - system_qty)},
    )
    await db.commit()
    await db.refresh(entry)
    return _physical_count_out(item, entry)


@router.post("/{item_id}/physical-update", response_model=StockPhysicalUpdateOut)
async def update_physical_stock(
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    body: StockPhysicalUpdateIn,
    db: Annotated[AsyncSession, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
    membership: Annotated[Membership, Depends(require_permission("stock_edit"))],
):
    kind = {
        "verification": "physical_count",
        "damaged": "damage",
        "correction": "correction",
        "sale": "sale",
    }.get(body.adjustment_type, "physical_count")
    try:
        result = await apply_stock_movement(
            db,
            business_id=business_id,
            item_id=item_id,
            user=user,
            movement_kind=kind,
            mode="absolute",
            qty=Decimal(body.counted_qty),
            reason=body.reason,
            notes=body.notes,
            source_type="physical_update",
            idempotency_key=body.idempotency_key,
            last_seen_stock_version=body.last_seen_stock_version,
        )
    except StaleStockVersionError as e:
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            detail={
                "code": "STALE_STOCK_VERSION",
                "message": str(e),
                "current_stock": str(e.current_qty),
                "stock_version": e.current_version,
            },
        ) from e
    except ValueError as e:
        if str(e) == "Item not found":
            raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Item not found") from e
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail=str(e)) from e
    await maybe_notify_stock_variance(
        db,
        business_id=business_id,
        item_id=item_id,
        adjustment_type=body.adjustment_type,
        new_qty=result.movement.qty_after,
    )
    counted = Decimal(body.counted_qty)
    system_before = result.movement.qty_before
    ps, pe = _parse_period_dates(body.period_start, body.period_end)
    purchased_qty: Decimal | None = None
    if ps and pe:
        purchased_qty = (
            await _period_purchased_map(db, business_id, [item_id], ps, pe)
        ).get(item_id, Decimal("0"))
    item_r = await db.execute(
        select(CatalogItem).where(
            CatalogItem.id == item_id,
            CatalogItem.business_id == business_id,
            CatalogItem.deleted_at.is_(None),
        )
    )
    count_item = item_r.scalar_one_or_none()
    if count_item is not None:
        display = _user_display(user)
        db.add(
            StockPhysicalCount(
                business_id=business_id,
                item_id=item_id,
                system_qty=system_before,
                counted_qty=counted,
                difference_qty=counted - system_before,
                purchased_qty=purchased_qty,
                stock_unit=catalog_stock_unit(count_item),
                period_start=ps,
                period_end=pe,
                notes=body.notes.strip() if body.notes else None,
                counted_by=user.id,
                counted_by_name=display,
            )
        )
    await db.commit()
    await db.refresh(result.movement)
    publish_business_event(
        business_id,
        "stock.changed",
        {
            "item_id": str(item_id),
            "movement_id": str(result.movement.id),
            "kind": kind,
        },
    )
    item = await get_stock_item(business_id, item_id, db, membership)
    return StockPhysicalUpdateOut(
        item=item,
        movement=_movement_out(
            result.movement,
            item_name=item.name,
            duplicate=result.duplicate,
        ),
    )


@router.post("/{item_id}/verify-count", response_model=StockDetailOut)
async def verify_stock_count(
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    body: StockVerifyCountIn,
    db: Annotated[AsyncSession, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
    membership: Annotated[Membership, Depends(require_permission("stock_edit"))],
):
    """Physical count from barcode scan — sets stock to counted qty with mandatory reason on variance."""
    from app.services.stock_audit_service import apply_audit_line_to_stock
    r = await db.execute(
        select(CatalogItem)
        .options(selectinload(CatalogItem.category))
        .where(
            CatalogItem.id == item_id,
            CatalogItem.business_id == business_id,
            CatalogItem.deleted_at.is_(None),
        )
    )
    item = r.scalar_one_or_none()
    if not item:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Item not found")

    old_qty = catalog_stock_qty(item)
    counted = Decimal(body.counted_qty)
    if counted < 0:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="Stock cannot be negative")
    diff = old_qty - counted
    if diff != 0 and not (body.reason and body.reason.strip()):
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            detail="Reason required when counted stock differs from system",
        )

    await apply_audit_line_to_stock(
        db,
        business_id=business_id,
        user=user,
        item=item,
        counted_qty=counted,
        adjustment_type=body.adjustment_type,
        reason=body.reason + (f" — {body.notes}" if body.notes else ""),
        audit_id=None,
    )
    await log_staff_activity(
        db,
        business_id=business_id,
        user=user,
        action_type="BARCODE_COUNT_VERIFY",
        item_id=item_id,
        item_name=item.name,
        before_data={"qty": float(old_qty)},
        after_data={"qty": float(counted), "type": body.adjustment_type},
    )
    await maybe_notify_stock_variance(
        db,
        business_id=business_id,
        item_id=item_id,
        adjustment_type=body.adjustment_type,
        new_qty=counted,
    )
    await db.commit()
    await db.refresh(item)
    return await get_stock_item(business_id, item_id, db, membership)


@router.patch("/{item_id}", response_model=StockDetailOut)
async def patch_stock_item(
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    body: StockPatchIn,
    db: Annotated[AsyncSession, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
    _membership: Annotated[Membership, Depends(require_permission("stock_edit"))],
):
    item_r = await db.execute(
        select(CatalogItem).where(
            CatalogItem.id == item_id,
            CatalogItem.business_id == business_id,
            CatalogItem.deleted_at.is_(None),
        )
    )
    item = item_r.scalar_one_or_none()
    if not item:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Item not found")
    role = (_membership.role or "").strip().lower()
    if bool(getattr(item, "opening_stock_locked", False)) and role not in (
        "owner",
        "super_admin",
        "admin",
    ):
        raise HTTPException(
            status.HTTP_403_FORBIDDEN,
            detail="Opening stock is locked — only the owner can adjust this item",
        )
    kind = {
        "verification": "physical_count",
        "damaged": "damage",
        "correction": "correction",
        "sale": "sale",
    }.get(body.adjustment_type, body.adjustment_type)
    try:
        result = await apply_stock_movement(
            db,
            business_id=business_id,
            item_id=item_id,
            user=user,
            movement_kind=kind,
            mode="absolute",
            qty=Decimal(body.new_qty),
            reason=body.reason or body.adjustment_type,
            source_type="stock_patch",
        )
    except ValueError as e:
        if str(e) == "Item not found":
            raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Item not found") from e
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail=str(e)) from e
    await maybe_notify_stock_variance(
        db,
        business_id=business_id,
        item_id=item_id,
        adjustment_type=body.adjustment_type,
        new_qty=result.movement.qty_after,
        triggered_by_user_id=user.id,
    )
    item = result.item
    unit = catalog_stock_unit(item) or item.default_unit or ""
    await maybe_notify_staff_system_stock_edit(
        db,
        business_id=business_id,
        item_id=item_id,
        item_name=item.name,
        unit=unit,
        old_qty=result.movement.qty_before,
        new_qty=result.movement.qty_after,
        actor_user_id=user.id,
        actor_display=_user_display(user),
        actor_role=_membership.role or "",
    )
    await db.commit()
    publish_business_event(
        business_id,
        "stock.changed",
        {
            "item_id": str(item_id),
            "movement_id": str(result.movement.id),
            "kind": kind,
        },
    )

    return await get_stock_item(business_id, item_id, db, _membership)


@router.post("/{item_id}/undo-last", response_model=StockDetailOut)
async def undo_last_stock_change(
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
    _membership: Annotated[Membership, Depends(require_permission("stock_edit"))],
):
    """Revert the user's most recent stock adjustment within 15 minutes."""
    cutoff = datetime.now(timezone.utc) - timedelta(minutes=15)
    r = await db.execute(
        select(StockAdjustmentLog)
        .where(
            StockAdjustmentLog.business_id == business_id,
            StockAdjustmentLog.item_id == item_id,
            StockAdjustmentLog.updated_by == user.id,
            StockAdjustmentLog.updated_at >= cutoff,
        )
        .order_by(desc(StockAdjustmentLog.updated_at))
        .limit(1)
    )
    log = r.scalar_one_or_none()
    if not log:
        raise HTTPException(
            status.HTTP_404_NOT_FOUND,
            detail="No recent stock change to undo",
        )
    if log.adjustment_type in ("opening_stock", "opening_stock_setup") and (
        _membership.role or ""
    ) not in (
        "owner",
        "super_admin",
        "admin",
    ):
        raise HTTPException(
            status.HTTP_403_FORBIDDEN,
            detail="Opening stock cannot be undone. Contact owner.",
        )
    item_r = await db.execute(
        select(CatalogItem).where(
            CatalogItem.id == item_id,
            CatalogItem.business_id == business_id,
            CatalogItem.deleted_at.is_(None),
        )
    )
    item = item_r.scalar_one_or_none()
    if not item:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Item not found")
    revert_to = log.old_qty
    try:
        result = await apply_stock_movement(
            db,
            business_id=business_id,
            item_id=item_id,
            user=user,
            movement_kind="undo",
            mode="absolute",
            qty=revert_to,
            reason="Undo previous adjustment",
            source_type="undo",
            source_id=log.id,
            idempotency_key=f"undo:{log.id}",
        )
    except ValueError as e:
        if str(e) == "Item not found":
            raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Item not found") from e
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail=str(e)) from e
    await db.commit()
    publish_business_event(
        business_id,
        "stock.changed",
        {
            "item_id": str(item_id),
            "movement_id": str(result.movement.id),
            "kind": "undo",
        },
    )
    return await get_stock_item(business_id, item_id, db, _membership)


@router.post("/{item_id}/notify-owner", status_code=status.HTTP_201_CREATED)
async def notify_owner_about_item(
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
    _m: Annotated[Membership, Depends(require_membership)],
    alert: str = Query("reorder", pattern="^(reorder|missing_barcode)$"),
):
    """Staff/manager alert: ping business owners about this catalog item."""
    r = await db.execute(
        select(CatalogItem).where(
            CatalogItem.id == item_id,
            CatalogItem.business_id == business_id,
            CatalogItem.deleted_at.is_(None),
        )
    )
    item = r.scalar_one_or_none()
    if not item:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Item not found")

    mems = await db.execute(
        select(Membership.user_id, Membership.role).where(
            Membership.business_id == business_id,
            Membership.role.in_(("owner", "manager", "admin")),
        )
    )
    targets = [(row[0], row[1]) for row in mems.all() if row[0] != user.id]
    if not targets:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="No owner/manager to notify")

    display = _user_display(user)
    day = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    cur = catalog_stock_qty(item)
    ro = catalog_reorder(item)
    if alert == "missing_barcode":
        kind = "missing_barcode"
        title = "Missing barcode label"
        body = f"{display} flagged {item.name} — needs packaging barcode + label print"
        dedupe_prefix = "missing_barcode"
        cta = "labels"
    else:
        kind = "reorder_request"
        title = "Reorder requested"
        body = f"{display} needs reorder for {item.name} ({cur} on hand, reorder {ro})"
        dedupe_prefix = "reorder_request"
        cta = "purchase"
    inserted = 0
    for uid, role in targets:
        dedupe = f"{dedupe_prefix}:{item_id}:{uid}:{day}"
        ex = await db.execute(
            select(AppNotification.id).where(
                AppNotification.business_id == business_id,
                AppNotification.dedupe_key == dedupe,
            ).limit(1)
        )
        if ex.scalar_one_or_none() is not None:
            continue
        item_route = f"/catalog/item/{item_id}"
        db.add(
            AppNotification(
                id=uuid.uuid4(),
                business_id=business_id,
                user_id=uid,
                kind=kind,
                title=title,
                body=body,
                payload={
                    "item_id": str(item_id),
                    "from_user_id": str(user.id),
                    "from_user_name": display,
                    "target_role": role,
                    "cta": cta,
                },
                action_route=item_route,
                dedupe_key=dedupe,
                category=CATEGORY_STAFF,
                priority="high",
                triggered_by_user_id=user.id,
            )
        )
        inserted += 1
    if inserted:
        await db.commit()
        publish_notification_changed(business_id)
    return {"ok": True, "notifications_created": inserted}


@router.post("/{item_id}/reorder", status_code=status.HTTP_201_CREATED)
async def add_item_to_reorder_list(
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
    _m: Annotated[Membership, Depends(require_membership)],
):
    r = await db.execute(
        select(CatalogItem).where(
            CatalogItem.id == item_id,
            CatalogItem.business_id == business_id,
            CatalogItem.deleted_at.is_(None),
        )
    )
    item = r.scalar_one_or_none()
    if not item:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Item not found")

    ex = await db.execute(
        select(ReorderListEntry).where(
            ReorderListEntry.business_id == business_id,
            ReorderListEntry.item_id == item_id,
            ReorderListEntry.status == "pending",
        ).limit(1)
    )
    row = ex.scalar_one_or_none()
    display = _user_display(user)
    if row is not None:
        row.added_by = user.id
        row.added_by_name = display
        row.updated_at = datetime.now(timezone.utc)
    else:
        db.add(
            ReorderListEntry(
                id=uuid.uuid4(),
                business_id=business_id,
                item_id=item_id,
                added_by=user.id,
                added_by_name=display,
                status="pending",
            )
        )
    await db.commit()
    return {"ok": True, "item_id": str(item_id), "status": "pending"}
