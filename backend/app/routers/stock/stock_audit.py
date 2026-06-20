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

logger = logging.getLogger(__name__)


from app.services.stock_variance_notifications import _last_purchase_expected_qty_map
router = APIRouter()

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
    variance_ids = {
        log.item_id
        for log in logs
        if log.adjustment_type in ("verification", "correction", "manual")
    }
    expected_map = await _last_purchase_expected_qty_map(
        db, business_id, variance_ids
    )
    out: list[StockAdjustmentOut] = []
    for log in logs:
        item = items.get(log.item_id)
        var_exp: Decimal | None = None
        var_delta: Decimal | None = None
        if log.adjustment_type in ("verification", "correction", "manual"):
            exp = expected_map.get(log.item_id)
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


async def fetch_recent_adjustments(
    db: AsyncSession,
    business_id: uuid.UUID,
    *,
    limit: int = 12,
    on: date | None = None,
) -> list[StockAdjustmentOut]:
    """Recent stock adjustments for shell bundle / activity tab."""
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
    return await fetch_recent_adjustments(db, business_id, limit=limit, on=on)
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
    except NegativeStockError as e:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(e)) from e
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
    display = sh._user_display(user)
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
