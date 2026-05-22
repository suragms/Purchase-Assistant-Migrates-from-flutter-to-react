import uuid
from datetime import date, datetime, time, timedelta, timezone
from decimal import Decimal
from typing import Annotated, Literal

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import case, desc, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.database import get_db
from app.deps import get_current_user, require_membership, require_permission
from app.services.staff_audit import log_staff_activity
from app.models import (
    CatalogItem,
    CategoryType,
    DailyUsageLog,
    ItemCategory,
    Membership,
    Supplier,
    TradePurchase,
    TradePurchaseLine,
    User,
)
from app.models.notification import AppNotification
from app.models.reorder_list import ReorderListEntry
from app.models.stock_adjustment import StockAdjustmentLog
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
    StockListOut,
    StockPatchIn,
    RecentPurchaseOut,
    ReorderListEntryOut,
    ReorderListOut,
    ReorderListPatchIn,
    InventorySummaryOut,
    StockTotalsOut,
    StockAlertsSummaryOut,
)
from app.services.staff_view import should_redact_financials
from app.services.stock_inventory import (
    catalog_reorder,
    catalog_stock_qty,
    compute_inventory_summary,
    stock_status,
)
from app.services.stock_variance_notifications import (
    _last_purchase_expected_qty,
    maybe_notify_stock_variance,
)

router = APIRouter(prefix="/v1/businesses/{business_id}/stock", tags=["stock"])

StatusFilter = Literal["all", "low", "critical", "out"]
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
    delta = datetime.now(timezone.utc) - item.last_purchase_at
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


def _item_to_list_row(
    item: CatalogItem,
    category_name: str | None,
    subcategory_name: str | None,
    supplier_name: str | None,
    *,
    period_purchased_qty: Decimal | None = None,
    period_variance_qty: Decimal | None = None,
    needs_verification: bool = False,
    purchased_today_qty: Decimal | None = None,
    usage_today_qty: Decimal | None = None,
    is_perishable: bool = False,
) -> StockListItemOut:
    cur = catalog_stock_qty(item)
    ro = catalog_reorder(item)
    unit = item.stock_unit or item.default_unit or item.selling_unit
    return StockListItemOut(
        id=item.id,
        item_code=item.item_code,
        name=item.name,
        category_name=category_name,
        subcategory_name=subcategory_name,
        current_stock=cur,
        reorder_level=ro,
        unit=unit,
        rack_location=item.rack_location,
        supplier_name=supplier_name,
        stock_status=stock_status(cur, ro),
        last_stock_updated_at=item.last_stock_updated_at,
        last_stock_updated_by=item.last_stock_updated_by,
        period_purchased_qty=period_purchased_qty,
        period_variance_qty=period_variance_qty,
        needs_verification=needs_verification,
        purchased_today_qty=purchased_today_qty,
        usage_today_qty=usage_today_qty,
        days_since_last_purchase=_days_since_last_purchase(item),
        needs_eviction=_needs_eviction(item, is_perishable=is_perishable, current=cur),
        is_perishable=is_perishable,
        missing_barcode=not (getattr(item, "barcode", None) and str(item.barcode).strip()),
        missing_item_code=not (item.item_code and str(item.item_code).strip()),
        barcode=getattr(item, "barcode", None),
    )


def _parse_period_dates(
    period_start: str | None, period_end: str | None
) -> tuple[date | None, date | None]:
    if not period_start or not period_end:
        return None, None
    try:
        ps = date.fromisoformat(period_start.strip()[:10])
        pe = date.fromisoformat(period_end.strip()[:10])
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
) -> dict[uuid.UUID, Decimal]:
    if not item_ids:
        return {}
    r = await db.execute(
        select(
            TradePurchaseLine.catalog_item_id,
            func.coalesce(func.sum(TradePurchaseLine.qty), 0),
        )
        .join(TradePurchase, TradePurchaseLine.trade_purchase_id == TradePurchase.id)
        .where(
            TradePurchase.business_id == business_id,
            TradePurchase.purchase_date >= period_start,
            TradePurchase.purchase_date <= period_end,
            TradePurchase.status != "cancelled",
            TradePurchaseLine.catalog_item_id.in_(item_ids),
        )
        .group_by(TradePurchaseLine.catalog_item_id)
    )
    return {row[0]: Decimal(row[1] or 0) for row in r.all()}


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
        if status_val != "all" and st != status_val:
            continue
        out.append((item, cat_name, type_name))

    _sort_stock_rows(out, sort)
    total = len(out)
    start = (page - 1) * per_page
    page_rows = out[start : start + per_page]
    return total, page_rows


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


@router.get("/totals", response_model=StockTotalsOut)
async def stock_totals(
    business_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
) -> StockTotalsOut:
    """Sum on-hand stock by unit for owner home movement card."""
    del _m
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
):
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
    ps, pe = _parse_period_dates(period_start, period_end)
    item_ids = [item.id for item, _, _ in rows]
    if include_period and ps and pe:
        period_map = await _period_purchased_map(db, business_id, item_ids, ps, pe)
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
    items: list[StockListItemOut] = []
    for item, cat_name, type_name in rows:
        sup = await _supplier_name(db, item)
        purchased = period_map.get(item.id) if include_period else None
        cur = catalog_stock_qty(item)
        variance = (cur - purchased) if purchased is not None else None
        verify = (
            _needs_verification(cur, purchased) if purchased is not None else False
        )
        perishable = perishable_by_cat.get(item.category_id, False) if item.category_id else False
        items.append(
            _item_to_list_row(
                item,
                cat_name,
                type_name,
                sup,
                period_purchased_qty=purchased,
                period_variance_qty=variance,
                needs_verification=verify,
                purchased_today_qty=today_purchased.get(item.id),
                usage_today_qty=today_usage.get(item.id),
                is_perishable=perishable,
            )
        )
    return StockListOut(items=items, total=total, page=page, per_page=per_page)


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
    items: list[StockListItemOut] = []
    for item, cat_name, type_name, _ in page_slice:
        sup = await _supplier_name(db, item)
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
    return BarcodeLookupOut(
        id=item.id,
        name=item.name,
        item_code=item.item_code,
        barcode=getattr(item, "barcode", None),
        current_stock=catalog_stock_qty(item),
        reorder_level=catalog_reorder(item),
        unit=item.stock_unit or item.default_unit,
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
    low = crit = missing_barcode = missing_item_code = eviction = 0
    ir = await db.execute(
        select(
            CatalogItem.id,
            CatalogItem.current_stock,
            CatalogItem.reorder_level,
            CatalogItem.item_code,
            CatalogItem.barcode,
            CatalogItem.last_purchase_at,
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
        _iid, cur, ro, code, barcode, lpa, ev_days, perish = row
        cur_d = Decimal(cur or 0)
        ro_d = Decimal(ro or 0)
        st = stock_status(cur_d, ro_d)
        if st == "low":
            low += 1
        elif st in ("critical", "out"):
            crit += 1
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
    ar = await db.execute(
        select(func.count()).select_from(CatalogItem).where(
            CatalogItem.business_id == business_id,
            CatalogItem.deleted_at.is_(None),
            CatalogItem.current_stock > 0,
        )
    )
    active = int(ar.scalar_one() or 0)
    return StockAlertsSummaryOut(
        low_stock=low,
        critical_stock=crit,
        missing_barcode=missing_barcode,
        missing_usage_logs=max(0, active - logged),
        eviction_count=eviction,
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
    limit: int = Query(5, ge=1, le=100),
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


async def _barcode_label(
    db: AsyncSession, business_id: uuid.UUID, item: CatalogItem
) -> BarcodeLabelOut:
    cat_name: str | None = None
    if item.category_id:
        cr = await db.execute(select(ItemCategory.name).where(ItemCategory.id == item.category_id))
        cat_name = cr.scalar_one_or_none()
    purchases = await _recent_purchases(db, item.id, limit=1)
    lp = purchases[0] if purchases else None
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


@router.post("/barcode/batch", response_model=BarcodeBatchOut)
async def barcode_batch(
    business_id: uuid.UUID,
    body: BarcodeBatchIn,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
):
    r = await db.execute(
        select(CatalogItem).where(
            CatalogItem.business_id == business_id,
            CatalogItem.id.in_(body.item_ids),
            CatalogItem.deleted_at.is_(None),
        )
    )
    items = {i.id: i for i in r.scalars().all()}
    labels: list[BarcodeLabelOut] = []
    for iid in body.item_ids:
        item = items.get(iid)
        if item:
            labels.append(await _barcode_label(db, business_id, item))
    return BarcodeBatchOut(labels=labels)


async def _recent_purchases(db: AsyncSession, item_id: uuid.UUID, limit: int = 5) -> list[RecentPurchaseOut]:
    r = await db.execute(
        select(TradePurchaseLine, TradePurchase, Supplier.name)
        .join(TradePurchase, TradePurchaseLine.trade_purchase_id == TradePurchase.id)
        .outerjoin(Supplier, TradePurchase.supplier_id == Supplier.id)
        .where(TradePurchaseLine.catalog_item_id == item_id)
        .order_by(desc(TradePurchase.purchase_date))
        .limit(limit)
    )
    out: list[RecentPurchaseOut] = []
    for line, tp, sup_name in r.all():
        pd = tp.purchase_date
        if pd is not None and not isinstance(pd, datetime):
            from datetime import date as date_cls

            if isinstance(pd, date_cls):
                pd = datetime.combine(pd, datetime.min.time(), tzinfo=timezone.utc)
        out.append(
            RecentPurchaseOut(
                id=tp.id,
                invoice_number=tp.invoice_number,
                human_id=tp.human_id,
                purchase_date=pd,
                qty=line.qty,
                unit=line.unit,
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
    items: list[ReorderListEntryOut] = []
    for entry, item in rows:
        cur = catalog_stock_qty(item)
        ro = catalog_reorder(item)
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
    ps, pe = _parse_period_dates(period_start, period_end)
    if ps and pe:
        m = await _period_purchased_map(db, business_id, [item_id], ps, pe)
        purchased = m.get(item_id, Decimal("0"))
    variance = cur - purchased
    purchases = await _recent_purchases(db, item_id)
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
    return StockIntelligenceOut(
        id=item.id,
        item_code=item.item_code,
        name=item.name,
        category_name=cat_name,
        subcategory_name=type_name,
        supplier_name=supplier_name,
        barcode=getattr(item, "barcode", None),
        default_kg_per_bag=getattr(item, "default_kg_per_bag", None),
        last_stock_updated_at=getattr(item, "last_stock_updated_at", None),
        last_stock_updated_by=getattr(item, "last_stock_updated_by", None),
        current_stock=cur,
        reorder_level=ro,
        unit=unit,
        stock_status=stock_status(cur, ro),
        period_purchased_qty=purchased,
        period_variance_qty=variance,
        needs_verification=_needs_verification(cur, purchased),
        recent_purchases=purchases,
        recent_adjustments=adjustments,
    )


@router.get("/{item_id}", response_model=StockDetailOut)
async def get_stock_item(
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
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
    base = _item_to_list_row(item, cat_name, type_name, sup)
    purchases = await _recent_purchases(db, item_id)
    if should_redact_financials(_m.role):
        purchases = [
            p.model_copy(update={"rate": None}) if hasattr(p, "model_copy") else p
            for p in purchases
        ]
    return StockDetailOut(**base.model_dump(), recent_purchases=purchases)


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
    new_qty = Decimal(body.new_qty)
    display = _user_display(user)
    log = StockAdjustmentLog(
        business_id=business_id,
        item_id=item_id,
        old_qty=old_qty,
        new_qty=new_qty,
        adjustment_type=body.adjustment_type,
        reason=body.reason,
        updated_by=user.id,
        updated_by_name=display,
    )
    item.current_stock = new_qty
    item.last_stock_updated_at = datetime.now(timezone.utc)
    item.last_stock_updated_by = display
    item.updated_by_user_id = user.id
    db.add(log)
    await log_staff_activity(
        db,
        business_id=business_id,
        user=user,
        action_type="STOCK_UPDATE",
        item_id=item_id,
        item_name=item.name,
        before_data={"qty": float(old_qty)},
        after_data={"qty": float(new_qty), "type": body.adjustment_type},
    )
    await maybe_notify_stock_variance(
        db,
        business_id=business_id,
        item_id=item_id,
        adjustment_type=body.adjustment_type,
        new_qty=new_qty,
    )
    await db.commit()
    await db.refresh(item)

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
    current = catalog_stock_qty(item)
    revert_to = log.old_qty
    display = _user_display(user)
    db.add(
        StockAdjustmentLog(
            business_id=business_id,
            item_id=item_id,
            old_qty=current,
            new_qty=revert_to,
            adjustment_type="correction",
            reason="Undo previous adjustment",
            updated_by=user.id,
            updated_by_name=display,
        )
    )
    item.current_stock = revert_to
    item.last_stock_updated_at = datetime.now(timezone.utc)
    item.last_stock_updated_by = display
    await db.commit()
    await db.refresh(item)
    return await get_stock_item(business_id, item_id, db, _membership)


@router.post("/{item_id}/notify-owner", status_code=status.HTTP_201_CREATED)
async def notify_owner_about_item(
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
    _m: Annotated[Membership, Depends(require_membership)],
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
            Membership.role.in_(("owner", "manager")),
        )
    )
    targets = [(row[0], row[1]) for row in mems.all() if row[0] != user.id]
    if not targets:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="No owner/manager to notify")

    display = _user_display(user)
    day = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    cur = catalog_stock_qty(item)
    ro = catalog_reorder(item)
    inserted = 0
    for uid, role in targets:
        dedupe = f"notify_owner:{item_id}:{uid}:{day}"
        ex = await db.execute(
            select(AppNotification.id).where(
                AppNotification.business_id == business_id,
                AppNotification.dedupe_key == dedupe,
            ).limit(1)
        )
        if ex.scalar_one_or_none() is not None:
            continue
        db.add(
            AppNotification(
                id=uuid.uuid4(),
                business_id=business_id,
                user_id=uid,
                kind="staff_alert",
                title="Stock attention needed",
                body=f"{display} flagged {item.name} ({cur} on hand, reorder {ro})",
                payload={
                    "item_id": str(item_id),
                    "from_user_id": str(user.id),
                    "from_user_name": display,
                    "target_role": role,
                },
                dedupe_key=dedupe,
            )
        )
        inserted += 1
    if inserted:
        await db.commit()
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
