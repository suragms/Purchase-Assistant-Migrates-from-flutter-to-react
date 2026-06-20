import asyncio
import hashlib
import json
import logging
import uuid
from collections import defaultdict
from time import monotonic
from datetime import date, datetime, time, timedelta, timezone
from decimal import Decimal
from typing import Annotated, Literal

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from fastapi.responses import JSONResponse, Response
from sqlalchemy import and_, case, desc, func, literal, or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.database import get_db
from app.deps import get_current_user, require_membership, require_permission, require_role
from app.services.staff_audit import log_staff_activity, log_staff_activity_best_effort
from app.services.notification_emitter import CATEGORY_STAFF, publish_notification_changed
from app.services.stock_inventory import (
    catalog_reorder,
    catalog_stock_qty,
    compute_inventory_summary,
    compute_stock_alerts_summary,
    movement_delivered_qty_map,
    stock_status,
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
    StockMovement,
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
    StockDeliveryIndicatorCountsOut,
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
    StockShellBundleOut,
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
from app.services import trade_query as tq
from app.services.staff_view import should_redact_financials
from app.services.low_stock_priority import compute_low_stock_priority
from app.services.low_stock_ops_enrichment import (
    derive_lifecycle_stage,
    item_is_disputed,
    open_dispute_item_ids,
    rejected_audit_item_ids,
    reorder_status_map,
)
from app.services.stock_movement_service import (
    NegativeStockError,
    StaleStockVersionError,
    apply_stock_movement,
    apply_stock_movement_with_retry,
)
from app.services.realtime_events import publish_business_event
from app.services.stock_variance_notifications import (
    maybe_notify_staff_system_stock_edit,
    maybe_notify_stock_variance,
)
from app.services.stock_tracking_profile import profile_from_catalog_item
from app.services.unit_normalization import (
    catalog_stock_unit,
    current_stock_kg as stock_qty_kg_equivalent,
    line_qty_in_stock_unit,
)
from app.services import stock_helpers as sh
from app.services.stock_helpers import OpeningSetupStatus, SortBy, StatusFilter
from app.read_cache_generation import trade_read_cache_generation
from app.services.app_cache import (
    STOCK_LIST_TTL_S,
    STOCK_SHELL_BUNDLE_TTL_S,
    get_cached,
    set_cached,
    stock_list_cache_key,
    stock_shell_bundle_cache_key,
)
from app.routers.stock.stock_audit import fetch_recent_adjustments

logger = logging.getLogger(__name__)

router = APIRouter()

async def _list_stock_page(
    *,
    business_id: uuid.UUID,
    db: AsyncSession,
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
    date_from: str | None = Query(None, description="Alias for period_start (YYYY-MM-DD)"),
    date_to: str | None = Query(None, description="Alias for period_end (YYYY-MM-DD)"),
    include_today: bool = Query(True),
    purchased_in_period: bool = Query(False),
    missing_barcode: bool = Query(False),
    missing_item_code: bool = Query(False),
    reorder_only: bool = Query(False),
    unit: str = Query(""),
):
    ps_raw, pe_raw = sh._resolve_period_query(
        period_start, period_end, date_from, date_to
    )
    ps, pe = sh._parse_period_dates(ps_raw, pe_raw)
    op_kwargs = {
        "missing_barcode": missing_barcode,
        "missing_item_code": missing_item_code,
        "reorder_only": reorder_only,
        "unit": unit,
    }
    if purchased_in_period and include_period and ps and pe:
        purchased_ids = await sh._catalog_item_ids_purchased_in_period(
            db, business_id, ps, pe
        )
        total, rows = await sh._query_items(
            db,
            business_id,
            q=q,
            category=category,
            subcategory=subcategory,
            status_val=status,
            sort=sort,
            page=page,
            per_page=per_page,
            whitelist_ids=purchased_ids,
            **op_kwargs,
        )
        period_map_all = (
            await sh._period_purchased_map(
                db, business_id, [item.id for item, _, _ in rows], ps, pe
            )
            if rows
            else {}
        )
    else:
        total, rows = await sh._query_items(
            db,
            business_id,
            q=q,
            category=category,
            subcategory=subcategory,
            status_val=status,
            sort=sort,
            page=page,
            per_page=per_page,
            **op_kwargs,
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
            period_map = await sh._period_purchased_map(
                db, business_id, item_ids, ps, pe
            )
        period_usage_map = await sh._period_usage_map(
            db, business_id, item_ids, ps, pe
        )
    today = date.today()
    today_purchased: dict[uuid.UUID, Decimal] = {}
    today_usage: dict[uuid.UUID, Decimal] = {}
    if include_today and item_ids:
        today_purchased = await sh._today_purchased_map(db, business_id, item_ids, today)
        today_usage = await sh._today_usage_map(db, business_id, item_ids, today)
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
    trade_meta = await sh._last_trade_meta_map(db, catalog_items)
    ledger_map = await sh._ledger_variance_map(db, business_id, catalog_items)
    pending_meta = await sh._pending_order_meta_map(db, business_id, item_ids)
    physical_meta = await sh._latest_physical_count_map(db, business_id, item_ids)
    movement_delivered = await movement_delivered_qty_map(db, business_id, item_ids)
    movement_at_map = await sh._last_movement_at_map(db, business_id, item_ids)
    items_dict = {item.id: item for item, _, _ in rows}
    sup_map = await sh._supplier_names_bulk(db, items_dict)
    items: list[StockListItemOut] = []
    for item, cat_name, type_name in rows:
        sup = sup_map.get(item.id)
        meta = trade_meta.get(item.id, (None, None))
        pend = pending_meta.get(item.id, (False, None, None))
        valid_last_trade = meta[0] is not None
        last_delivered = meta[1] if valid_last_trade else False
        last_lq = (
            getattr(item, "last_line_qty", None) if valid_last_trade else None
        )
        last_pur_at = (
            getattr(item, "last_purchase_at", None) if valid_last_trade else None
        )
        phys = physical_meta.get(item.id)
        purchased = period_map.get(item.id) if include_period else None
        usage = period_usage_map.get(item.id) if include_period else None
        cur = catalog_stock_qty(item)
        ledger_var = ledger_map.get(item.id)
        verify = False
        if ledger_var is not None and purchased is not None and purchased > 0:
            verify = abs(ledger_var) / purchased > Decimal("0.1")
        elif purchased is not None and purchased > 0:
            verify = sh._needs_verification(cur, purchased)
        perishable = perishable_by_cat.get(item.category_id, False) if item.category_id else False
        su = catalog_stock_unit(item)
        total_delivered = movement_delivered.get(item.id, Decimal(0))
        phys_qty = phys.counted_qty if phys else None
        spec_diff: Decimal | None = None
        if phys is not None:
            spec_diff = phys.difference_qty
        elif phys_qty is not None:
            spec_diff = phys_qty - cur
        items.append(
            sh._item_to_list_row(
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
                last_purchase_human_id=meta[0] if valid_last_trade else None,
                last_purchase_delivered=last_delivered,
                last_line_qty=last_lq,
                last_purchase_at=last_pur_at,
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
                total_pending_delivery_qty=pend[2],
                last_movement_at=movement_at_map.get(item.id),
            )
        )
    return StockListOut(items=items, total=total, page=page, per_page=per_page)
@router.get("/list", response_model=StockListOut)
async def list_stock(
    request: Request,
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
    date_from: str | None = Query(None, description="Alias for period_start (YYYY-MM-DD)"),
    date_to: str | None = Query(None, description="Alias for period_end (YYYY-MM-DD)"),
    include_today: bool = Query(True),
    purchased_in_period: bool = Query(False),
    missing_barcode: bool = Query(False),
    missing_item_code: bool = Query(False),
    reorder_only: bool = Query(False),
    unit: str = Query(""),
):
    gen = trade_read_cache_generation(business_id)
    cache_query = {
        "gen": gen,
        "page": page,
        "per_page": per_page,
        "q": q,
        "category": category,
        "subcategory": subcategory,
        "status": status,
        "sort": sort,
        "include_period": include_period,
        "period_start": period_start,
        "period_end": period_end,
        "date_from": date_from,
        "date_to": date_to,
        "include_today": include_today,
        "purchased_in_period": purchased_in_period,
        "missing_barcode": missing_barcode,
        "missing_item_code": missing_item_code,
        "reorder_only": reorder_only,
        "unit": unit,
    }
    cache_key = stock_list_cache_key(business_id, cache_query)
    cached_payload = get_cached(cache_key, STOCK_LIST_TTL_S)
    if cached_payload is not None:
        body = json.dumps(cached_payload, sort_keys=True, default=str).encode()
        etag = '"' + hashlib.md5(body).hexdigest()[:16] + '"'
        if request.headers.get("if-none-match") == etag:
            return Response(status_code=304, headers={"ETag": etag})
        return JSONResponse(
            content=cached_payload,
            headers={"ETag": etag, "Cache-Control": "private, max-age=0"},
        )

    out = await _list_stock_page(
        business_id=business_id,
        db=db,
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
        date_from=date_from,
        date_to=date_to,
        include_today=include_today,
        purchased_in_period=purchased_in_period,
        missing_barcode=missing_barcode,
        missing_item_code=missing_item_code,
        reorder_only=reorder_only,
        unit=unit,
    )
    payload = out.model_dump(mode="json")
    set_cached(cache_key, payload, STOCK_LIST_TTL_S)
    body = json.dumps(payload, sort_keys=True, default=str).encode()
    etag = '"' + hashlib.md5(body).hexdigest()[:16] + '"'
    if request.headers.get("if-none-match") == etag:
        return Response(status_code=304, headers={"ETag": etag})
    return JSONResponse(
        content=payload,
        headers={"ETag": etag, "Cache-Control": "private, max-age=0"},
    )


@router.get("/shell-bundle", response_model=StockShellBundleOut)
async def stock_shell_bundle(
    business_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
    page: int = Query(1, ge=1),
    per_page: int = Query(50, ge=1, le=200),
    q: str = Query(""),
    category: str = Query(""),
    subcategory: str = Query(""),
    status: StatusFilter = Query("all"),
    sort: SortBy = Query("name"),
    include_period: bool = Query(False),
    period_start: str | None = Query(None),
    period_end: str | None = Query(None),
    date_from: str | None = Query(None),
    date_to: str | None = Query(None),
    include_today: bool = Query(True),
    purchased_in_period: bool = Query(False),
    missing_barcode: bool = Query(False),
    missing_item_code: bool = Query(False),
    reorder_only: bool = Query(False),
    unit: str = Query(""),
    audit_limit: int = Query(12, ge=1, le=50),
):
    """Bundled Stock tab payload — list, KPI chips, delivery counts, recent activity."""
    gen = trade_read_cache_generation(business_id)
    cache_query = {
        "gen": gen,
        "page": page,
        "per_page": per_page,
        "q": q,
        "category": category,
        "subcategory": subcategory,
        "status": status,
        "sort": sort,
        "include_period": include_period,
        "period_start": period_start,
        "period_end": period_end,
        "date_from": date_from,
        "date_to": date_to,
        "include_today": include_today,
        "purchased_in_period": purchased_in_period,
        "missing_barcode": missing_barcode,
        "missing_item_code": missing_item_code,
        "reorder_only": reorder_only,
        "unit": unit,
        "audit_limit": audit_limit,
    }
    cache_key = stock_shell_bundle_cache_key(business_id, cache_query)
    cached = get_cached(cache_key, STOCK_SHELL_BUNDLE_TTL_S)
    if cached is not None:
        return StockShellBundleOut(**cached)

    list_out, status_counts, delivery_counts, audit_recent = await asyncio.gather(
        _list_stock_page(
            business_id=business_id,
            db=db,
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
            date_from=date_from,
            date_to=date_to,
            include_today=include_today,
            purchased_in_period=purchased_in_period,
            missing_barcode=missing_barcode,
            missing_item_code=missing_item_code,
            reorder_only=reorder_only,
            unit=unit,
        ),
        compute_stock_alerts_summary(db, business_id),
        _compute_delivery_indicator_counts(
            db=db,
            business_id=business_id,
            q=q,
            category=category,
            subcategory=subcategory,
            status=status,
            sort=sort,
            period_start=period_start,
            period_end=period_end,
            date_from=date_from,
            date_to=date_to,
            missing_barcode=missing_barcode,
            missing_item_code=missing_item_code,
            reorder_only=reorder_only,
            unit=unit,
        ),
        fetch_recent_adjustments(db, business_id, limit=audit_limit),
    )
    payload = StockShellBundleOut(
        list=list_out,
        status_counts=status_counts,
        delivery_counts=delivery_counts,
        audit_recent=audit_recent,
    ).model_dump(mode="json")
    set_cached(cache_key, payload, STOCK_SHELL_BUNDLE_TTL_S)
    return StockShellBundleOut.model_validate(payload)


async def _compute_delivery_indicator_counts(
    *,
    db: AsyncSession,
    business_id: uuid.UUID,
    q: str,
    category: str,
    subcategory: str,
    status: StatusFilter,
    sort: SortBy,
    period_start: str | None,
    period_end: str | None,
    date_from: str | None,
    date_to: str | None,
    missing_barcode: bool,
    missing_item_code: bool,
    reorder_only: bool,
    unit: str,
) -> StockDeliveryIndicatorCountsOut:
    ps_raw, pe_raw = sh._resolve_period_query(
        period_start, period_end, date_from, date_to
    )
    ps, pe = sh._parse_period_dates(ps_raw, pe_raw)
    del ps, pe
    op_kwargs = {
        "missing_barcode": missing_barcode,
        "missing_item_code": missing_item_code,
        "reorder_only": reorder_only,
        "unit": unit,
    }
    pending_n = 0
    delivered_n = 0
    page_num = 1
    batch_size = 500
    while True:
        total, rows = await sh._query_items(
            db,
            business_id,
            q=q,
            category=category,
            subcategory=subcategory,
            status_val=status,
            sort=sort,
            page=page_num,
            per_page=batch_size,
            **op_kwargs,
        )
        if not rows:
            break
        catalog_items = [item for item, _, _ in rows]
        item_ids = [item.id for item in catalog_items]
        trade_meta = await sh._last_trade_meta_map(db, catalog_items)
        pending_meta = await sh._pending_order_meta_map(db, business_id, item_ids)
        for item, _, _ in rows:
            meta = trade_meta.get(item.id, (None, None))
            valid_last_trade = meta[0] is not None
            pend = pending_meta.get(item.id, (False, None, None))
            kind = sh._classify_delivery_indicator(
                has_pending_order=pend[0],
                pending_delivery_qty=pend[2],
                last_purchase_human_id=meta[0] if valid_last_trade else None,
                last_purchase_delivered=meta[1] if valid_last_trade else None,
                last_purchase_at=(
                    getattr(item, "last_purchase_at", None) if valid_last_trade else None
                ),
            )
            if kind == "pending":
                pending_n += 1
            elif kind == "delivered":
                delivered_n += 1
        if page_num * batch_size >= total:
            break
        page_num += 1
    return StockDeliveryIndicatorCountsOut(pending=pending_n, delivered=delivered_n)


@router.get("/delivery-indicator-counts", response_model=StockDeliveryIndicatorCountsOut)
async def delivery_indicator_counts(
    business_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
    q: str = Query(""),
    category: str = Query(""),
    subcategory: str = Query(""),
    status: StatusFilter = Query("all"),
    sort: SortBy = Query("name"),
    include_period: bool = Query(False),
    period_start: str | None = Query(None),
    period_end: str | None = Query(None),
    date_from: str | None = Query(None),
    date_to: str | None = Query(None),
    missing_barcode: bool = Query(False),
    missing_item_code: bool = Query(False),
    reorder_only: bool = Query(False),
    unit: str = Query(""),
):
    """Global pending/delivered truck counts for stock list filters (not page-limited)."""
    return await _compute_delivery_indicator_counts(
        db=db,
        business_id=business_id,
        q=q,
        category=category,
        subcategory=subcategory,
        status=status,
        sort=sort,
        period_start=period_start,
        period_end=period_end,
        date_from=date_from,
        date_to=date_to,
        missing_barcode=missing_barcode,
        missing_item_code=missing_item_code,
        reorder_only=reorder_only,
        unit=unit,
    )


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
    full = await _list_stock_page(
        business_id=business_id,
        db=db,
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
    return await _list_stock_page(
        business_id=business_id,
        db=db,
        page=page,
        per_page=per_page,
        q=q,
        category=category,
        subcategory=subcategory,
        status=status,
        sort=sort,
    )
@router.get("/low", response_model=StockListOut, deprecated=True)
async def low_stock(
    business_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
    page: int = Query(1, ge=1),
    per_page: int = Query(50, ge=1, le=2000),
):
    """Items below reorder level — SQL-filtered (no in-memory 10k sweep)."""
    return await _list_stock_page(
        business_id=business_id,
        db=db,
        page=page,
        per_page=per_page,
        status="low",
        sort="stock_asc",
    )
@router.get("/critical", response_model=StockListOut, deprecated=True)
async def critical_stock(
    business_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
    page: int = Query(1, ge=1),
    per_page: int = Query(50, ge=1, le=2000),
):
    return await _list_stock_page(
        business_id=business_id,
        db=db,
        page=page,
        per_page=per_page,
        status="critical",
    )
@router.get("/alerts/summary", response_model=StockAlertsSummaryOut)
async def stock_alerts_summary(
    business_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
):
    """Stock-only alert counts — same scan as `/warehouse/alerts-summary` stock slice."""
    return await compute_stock_alerts_summary(db, business_id)
async def warehouse_alerts_from_stock(
    db: AsyncSession,
    business_id: uuid.UUID,
    stock: StockAlertsSummaryOut,
) -> WarehouseAlertsSummaryOut:
    """Warehouse KPIs from an existing stock alert scan (avoids duplicate catalog pass)."""
    today = date.today()
    (
        pending_deliveries_q,
        variances_q,
        templates_q,
        completed_q,
    ) = await asyncio.gather(
        db.execute(
            select(func.count(TradePurchase.id)).where(
                TradePurchase.business_id == business_id,
                TradePurchase.status.notin_(("cancelled", "deleted")),
                TradePurchase.is_delivered.is_(False),
            )
        ),
        db.execute(
            select(func.count(StockAdjustmentLog.id)).where(
                StockAdjustmentLog.business_id == business_id,
                StockAdjustmentLog.adjustment_type.in_(("verification", "correction", "manual")),
                func.date(StockAdjustmentLog.updated_at) == today,
            )
        ),
        db.execute(
            select(func.count())
            .select_from(StaffChecklistTemplate)
            .where(
                or_(
                    StaffChecklistTemplate.business_id == business_id,
                    StaffChecklistTemplate.business_id.is_(None),
                )
            )
        ),
        db.execute(
            select(func.count(func.distinct(StaffChecklistCompletion.task_key))).where(
                StaffChecklistCompletion.business_id == business_id,
                StaffChecklistCompletion.checklist_date == today,
            )
        ),
    )
    pending_deliveries = int(pending_deliveries_q.scalar_one() or 0)
    pending_verifications = int(variances_q.scalar_one() or 0)
    checklist_total = int(templates_q.scalar_one() or 0)
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
@router.get("/warehouse/alerts-summary", response_model=WarehouseAlertsSummaryOut)
async def warehouse_alerts_summary(
    business_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
):
    """Collapsed owner-home alert summary to avoid Flutter provider waterfalls."""
    stock = await compute_stock_alerts_summary(db, business_id)
    return await warehouse_alerts_from_stock(db, business_id, stock)
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
    ps, pe = sh._parse_period_dates(period_start, period_end)
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
        out = await _list_stock_page(
            business_id=business_id,
            db=db,
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
            purchased_in_period=False,
            missing_barcode=False,
            missing_item_code=False,
            reorder_only=False,
            unit="",
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
    ps, pe = sh._parse_period_dates(period_start, period_end)
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
    ps, pe = sh._parse_period_dates(period_start, period_end)
    period_days = _days_between(ps, pe)

    fetch_per_page = min(200, max(per_page, 50))
    max_pages = min(5, max(2, (page * per_page + fetch_per_page - 1) // fetch_per_page))
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

    if sort == "stock_asc":
        passing.sort(key=lambda x: float(x.current_stock))
    elif sort == "name":
        passing.sort(key=lambda x: (x.name or "").lower())
    else:
        passing.sort(
            key=lambda x: compute_low_stock_priority(x).score,
            reverse=True,
        )

    total = len(passing)
    start = (page - 1) * per_page
    page_stock_items = passing[start : start + per_page]
    page_items = await _enrich_low_stock_ops_rows(db, business_id, page_stock_items)

    pending_verification_cnt = sum(
        1 for it in passing if compute_low_stock_priority(it).needs_verification
    )
    out_cnt = sum(
        1
        for it in passing
        if it.stock_status.lower() == "out" or float(it.current_stock) <= 0
    )
    pending_cnt = sum(1 for it in passing if it.has_pending_order)
    delayed_cnt = sum(
        1 for it in passing if compute_low_stock_priority(it).delayed_flag
    )
    mismatch_cnt = sum(
        1 for it in passing if compute_low_stock_priority(it).mismatch_flag
    )
    disputed_cnt = sum(
        1
        for it in passing
        if item_is_disputed(
            it,
            open_disputes=dispute_ids,
            rejected_audits=rejected_ids,
        )
    )
    total_attention = total
    usage_sum: Decimal = Decimal(0)
    for it in passing:
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
