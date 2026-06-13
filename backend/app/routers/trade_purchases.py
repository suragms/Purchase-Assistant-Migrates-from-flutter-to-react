"""Wholesale trade purchase API (PUR-YYYY-XXXX), parallel to legacy entries."""

from __future__ import annotations

import logging
import uuid
from datetime import date
from typing import Annotated, Any

from fastapi import APIRouter, Body, Depends, Header, HTTPException, Query, Response, status
from fastapi.responses import JSONResponse
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.db_resilience import execute_with_retry
from app.deps import get_current_user, require_membership, require_permission, require_role
from app.models import Membership, User
from app.schemas.trade_purchases import (
    TradeDraftUpsertRequest,
    TradeDraftOut,
    TradeDuplicateCheckRequest,
    TradeDuplicateCheckResponse,
    TradeMarkPaidRequest,
    TradeNextHumanIdOut,
    TradePurchaseCreateRequest,
    TradePurchaseOut,
    TradePurchaseDeliveryPatch,
    TradePurchaseDispatchIn,
    TradePurchaseArriveIn,
    TradePurchaseDeliveryPipelineOut,
    TradePurchasePaymentPatch,
    TradePurchaseVerifyIn,
    TradePurchasePreviewOut,
    TradePurchaseUpdateRequest,
    TradePurchaseValidateOut,
    PurchaseLifecycleEventOut,
    PurchaseLifecycleTransitionIn,
)
from app.services import trade_purchase_service as tps
from app.services.staff_view import (
    should_redact_financials,
    trade_purchase_to_staff_dict,
    trade_purchases_to_staff_dicts,
)
from app.services.trade_preview_service import (
    build_trade_purchase_preview,
    build_trade_purchase_validate,
    coerce_raw_to_trade_purchase_create,
)
from app.services.realtime_events import publish_business_event
from app.services.stock_movement_service import NegativeStockError, StaleStockVersionError
from app.services import purchase_damage_service as pds
from app.schemas.purchase_damage import PurchaseDamageReportIn, PurchaseDamageReportOut

router = APIRouter(prefix="/v1/businesses/{business_id}/trade-purchases", tags=["trade-purchases"])
_log = logging.getLogger(__name__)


def _stock_version_conflict_http(e: StaleStockVersionError) -> HTTPException:
    return HTTPException(
        status.HTTP_409_CONFLICT,
        detail={
            "code": "STOCK_VERSION_CONFLICT",
            "message": f"Stock conflict on {e.item_name}. Please retry.",
            "item_name": e.item_name,
            "current_version": e.current_version,
        },
    )

_ALLOWED_TRADE_LIST_STATUSES = frozenset({
    "draft",
    "due_soon",
    "overdue",
    "paid",
    "pending",
    "delivered",
    "cancelled",
    "in_transit",
    "dispatched",
    "arrived",
    "staff_verifying",
    "staff_verified",
    "partial",
    "stock_committed",
})
_LEGACY_TRADE_LIST_STATUS_INT = {
    "0": "pending",
    "1": "paid",
    "2": "overdue",
    "3": "draft",
    "4": "due_soon",
}


def _purchase_list_response(
    role: str, rows: list[TradePurchaseOut]
) -> list[TradePurchaseOut] | JSONResponse:
    if should_redact_financials(role):
        return JSONResponse(trade_purchases_to_staff_dicts(rows))
    return rows


def _purchase_detail_response(
    role: str, out: TradePurchaseOut
) -> TradePurchaseOut | JSONResponse:
    if should_redact_financials(role):
        return JSONResponse(trade_purchase_to_staff_dict(out))
    return out


def _purchase_detail_with_event(
    business_id: uuid.UUID,
    role: str,
    out: TradePurchaseOut,
) -> TradePurchaseOut | JSONResponse:
    _publish_purchase_changed(business_id, out)
    return _purchase_detail_response(role, out)


def _catalog_item_ids_from_purchase(out: TradePurchaseOut) -> list[str]:
    seen: set[str] = set()
    ids: list[str] = []
    for line in out.lines:
        sid = str(line.catalog_item_id)
        if sid in seen:
            continue
        seen.add(sid)
        ids.append(sid)
    return ids


def _catalog_item_ids_from_update(body: TradePurchaseUpdateRequest) -> list[str]:
    seen: set[str] = set()
    ids: list[str] = []
    for line in body.lines:
        sid = str(line.catalog_item_id)
        if sid in seen:
            continue
        seen.add(sid)
        ids.append(sid)
    return ids


def _catalog_item_ids_from_create(body: TradePurchaseCreateRequest) -> list[str]:
    seen: set[str] = set()
    ids: list[str] = []
    for line in body.lines:
        sid = str(line.catalog_item_id)
        if sid in seen:
            continue
        seen.add(sid)
        ids.append(sid)
    return ids


def _publish_purchase_changed(
    business_id: uuid.UUID,
    out: TradePurchaseOut,
    *,
    item_ids: list[str] | None = None,
) -> None:
    ids = item_ids if item_ids is not None else _catalog_item_ids_from_purchase(out)
    payload: dict[str, Any] = {
        "purchase_id": str(out.id),
        "item_ids": ids,
    }
    if len(ids) == 1:
        payload["item_id"] = ids[0]
    publish_business_event(business_id, "purchase.changed", payload)
    for iid in ids:
        publish_business_event(
            business_id,
            "stock.changed",
            {"item_id": iid, "purchase_id": str(out.id)},
        )


def _normalize_trade_list_status(status: str | None) -> str | None:
    """Map query `status` to a value the list service understands, or None (= all). Never 422."""
    if status is None:
        return None
    s = status.strip().lower()
    if not s or s in ("all", "undefined", "null"):
        return None
    if s.isdigit() and s in _LEGACY_TRADE_LIST_STATUS_INT:
        s = _LEGACY_TRADE_LIST_STATUS_INT[s]
    if s in _ALLOWED_TRADE_LIST_STATUSES:
        return s
    return None


@router.get("/draft", response_model=TradeDraftOut)
async def read_trade_draft(
    business_id: uuid.UUID,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
):
    d = await execute_with_retry(lambda: tps.get_draft(db, business_id, user.id))
    if not d:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="No draft")
    return d


@router.put("/draft", response_model=TradeDraftOut)
async def upsert_trade_draft(
    business_id: uuid.UUID,
    body: TradeDraftUpsertRequest,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
):
    return await tps.upsert_draft(db, business_id, user.id, body.step, body.payload)


@router.delete("/draft", status_code=status.HTTP_204_NO_CONTENT)
async def delete_trade_draft(
    business_id: uuid.UUID,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
):
    await tps.delete_draft(db, business_id, user.id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/preview-lines", response_model=TradePurchasePreviewOut)
async def preview_trade_purchase_lines(
    business_id: uuid.UUID,
    user: Annotated[User, Depends(get_current_user)],
    _m: Annotated[Membership, Depends(require_membership)],
    body: dict[str, Any] = Body(...),
):
    """Non-mutating SSOT totals for wizard / PDF blocks (relaxed gross check for drafts)."""
    del user
    req = coerce_raw_to_trade_purchase_create(body)
    errs = tps.collect_trade_purchase_preview_errors(req)
    if errs:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, detail=errs)
    return build_trade_purchase_preview(req)


@router.post("/validate", response_model=TradePurchaseValidateOut)
async def validate_trade_purchase(
    business_id: uuid.UUID,
    user: Annotated[User, Depends(get_current_user)],
    _m: Annotated[Membership, Depends(require_membership)],
    body: dict[str, Any] = Body(...),
):
    """Full create/save validation without persisting (blocking issues for scanner / wizard)."""
    del user
    req = coerce_raw_to_trade_purchase_create(body)
    return build_trade_purchase_validate(req)


@router.post("/check-duplicate", response_model=TradeDuplicateCheckResponse)
async def check_trade_duplicate(
    business_id: uuid.UUID,
    body: TradeDuplicateCheckRequest,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
):
    del user
    return await tps.check_duplicate(db, business_id, body)


@router.get("/next-human-id", response_model=TradeNextHumanIdOut)
async def next_trade_human_id(
    business_id: uuid.UUID,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
):
    del user
    hid = await execute_with_retry(lambda: tps.next_human_id(db, business_id))
    return TradeNextHumanIdOut(human_id=hid)


@router.get("", response_model=list[TradePurchaseOut])
async def list_trade_purchases(
    business_id: uuid.UUID,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
    # Accept large client `limit` values (legacy apps) and clamp in-handler — FastAPI
    # must not 422 here or those clients never reach `limit_v = min(limit, 50)`.
    limit: int = Query(20, ge=1, le=2000),
    offset: int = Query(0, ge=0, le=10_000),
    status: str | None = Query(
        None,
        description=(
            "Payment: draft|pending|due_soon|overdue|paid; delivery: dispatched|arrived|"
            "staff_verifying|stock_committed|…; omit or 'all' = no filter"
        ),
    ),
    q: str | None = Query(None, max_length=200),
    supplier_id: uuid.UUID | None = Query(None),
    broker_id: uuid.UUID | None = Query(None),
    catalog_item_id: uuid.UUID | None = Query(
        None, description="Only purchases that include a line for this catalog item"
    ),
    purchase_from: date | None = Query(
        None, description="Inclusive lower bound on purchase_date (calendar date)"
    ),
    purchase_to: date | None = Query(
        None, description="Inclusive upper bound on purchase_date (calendar date)"
    ),
):
    limit_v = max(1, min(limit, 50))
    offset_v = max(0, min(offset, 10_000))
    status_norm = _normalize_trade_list_status(status)
    _log.debug(
        "list_trade_purchases business_id=%s limit=%s offset=%s status_raw=%r status_norm=%r q=%s",
        business_id,
        limit_v,
        offset_v,
        status,
        status_norm,
        (q or "").strip()[:80] or None,
    )
    rows = await execute_with_retry(
        lambda: tps.list_trade_purchases(
        db,
        business_id,
        limit=limit_v,
        offset=offset_v,
        status_filter=status_norm,
        q=q,
        supplier_id=supplier_id,
        broker_id=broker_id,
        catalog_item_id=catalog_item_id,
        purchase_from=purchase_from,
        purchase_to=purchase_to,
    ),
    )
    return _purchase_list_response(_m.role, rows)


@router.get("/last-defaults")
async def last_trade_purchase_defaults(
    business_id: uuid.UUID,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
    catalog_item_id: uuid.UUID = Query(...),
    supplier_id: uuid.UUID | None = Query(None),
    broker_id: uuid.UUID | None = Query(None),
):
    del user, _m
    return await execute_with_retry(
        lambda: tps.last_purchase_defaults(
            db,
            business_id,
            catalog_item_id=catalog_item_id,
            supplier_id=supplier_id,
            broker_id=broker_id,
        ),
    )


@router.post("", response_model=TradePurchaseOut, status_code=status.HTTP_201_CREATED)
async def create_trade_purchase(
    business_id: uuid.UUID,
    body: TradePurchaseCreateRequest,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_permission("purchase_create"))],
    idempotency_key: str | None = Header(None, alias="Idempotency-Key"),
):
    normalized_key = (idempotency_key or "").strip()
    if normalized_key:
        existing_id = tps.lookup_idempotency_purchase_id(business_id, normalized_key)
        if existing_id is not None:
            existing = await tps.get_trade_purchase(db, business_id, existing_id)
            if existing is not None:
                return existing
    try:
        out = await tps.create_trade_purchase(db, business_id, user.id, body)
        if normalized_key:
            tps.remember_idempotency_purchase_id(
                business_id,
                normalized_key,
                out.id,
            )
        _publish_purchase_changed(
            business_id,
            out,
            item_ids=_catalog_item_ids_from_create(body),
        )
        return out
    except tps.TradePurchaseValidationError as e:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, detail=e.details) from e
    except tps.TradePurchaseDuplicateError as e:
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            detail={
                "code": e.code,
                "message": e.message,
                "existing_id": str(e.existing_id),
                "existing_human_id": e.existing_human_id,
            },
        ) from e
    except NegativeStockError as e:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(e)) from e
    except ValueError as e:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail=str(e)) from e


@router.patch("/{purchase_id}/payment", response_model=TradePurchaseOut)
async def patch_trade_purchase_payment(
    business_id: uuid.UUID,
    purchase_id: uuid.UUID,
    body: TradePurchasePaymentPatch,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_permission("purchase_edit"))],
):
    del user
    try:
        out = await tps.patch_trade_purchase_payment(db, business_id, purchase_id, body)
    except NegativeStockError as e:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(e)) from e
    except ValueError as e:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail=str(e)) from e
    if not out:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Purchase not found")
    _publish_purchase_changed(business_id, out)
    return out


@router.get("/delivery-pipeline", response_model=TradePurchaseDeliveryPipelineOut)
async def get_trade_purchase_delivery_pipeline(
    business_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
):
    del _m
    return await tps.get_trade_purchase_delivery_pipeline(db, business_id)


@router.patch("/{purchase_id}/delivery", response_model=TradePurchaseOut)
async def patch_trade_purchase_delivery(
    business_id: uuid.UUID,
    purchase_id: uuid.UUID,
    body: TradePurchaseDeliveryPatch,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_permission("stock_edit"))],
):
    del user
    try:
        out = await tps.patch_trade_purchase_delivery(db, business_id, purchase_id, body)
    except NegativeStockError as e:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(e)) from e
    except ValueError as e:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail=str(e)) from e
    if not out:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Purchase not found")
    return _purchase_detail_with_event(business_id, _m.role, out)


@router.post("/{purchase_id}/dispatch", response_model=TradePurchaseOut)
async def dispatch_trade_purchase(
    business_id: uuid.UUID,
    purchase_id: uuid.UUID,
    body: TradePurchaseDispatchIn,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_role("owner", "manager", "super_admin"))],
):
    try:
        out = await tps.dispatch_trade_purchase(
            db, business_id, purchase_id, user, body
        )
    except ValueError as e:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail=str(e)) from e
    if not out:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Purchase not found")
    return _purchase_detail_with_event(business_id, _m.role, out)


@router.post("/{purchase_id}/arrive", response_model=TradePurchaseOut)
async def arrive_trade_purchase(
    business_id: uuid.UUID,
    purchase_id: uuid.UUID,
    body: TradePurchaseArriveIn,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_permission("stock_edit"))],
):
    try:
        out = await tps.arrive_trade_purchase(
            db, business_id, purchase_id, user, body
        )
    except ValueError as e:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail=str(e)) from e
    if not out:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Purchase not found")
    return _purchase_detail_with_event(business_id, _m.role, out)


@router.post("/{purchase_id}/commit-stock", response_model=TradePurchaseOut)
async def commit_trade_purchase_delivery(
    business_id: uuid.UUID,
    purchase_id: uuid.UUID,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_role("owner", "manager", "admin", "super_admin"))],
):
    try:
        out = await tps.commit_trade_purchase_delivery(
            db, business_id, purchase_id, user
        )
    except StaleStockVersionError as e:
        raise _stock_version_conflict_http(e) from e
    except tps.UnitSetupRequiredError as e:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            detail={
                "code": "UNIT_SETUP_REQUIRED",
                "message": e.message,
                "items_needing_setup": e.items_needing_setup,
                "count": e.count,
            },
        ) from e
    except ValueError as e:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail=str(e)) from e
    if not out:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Purchase not found")
    return _purchase_detail_with_event(business_id, _m.role, out)


@router.post("/{purchase_id}/auto-commit", response_model=TradePurchaseOut)
async def auto_commit_trade_purchase_delivery(
    business_id: uuid.UUID,
    purchase_id: uuid.UUID,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_role("owner", "manager", "admin", "super_admin"))],
):
    out = await tps.try_auto_commit_trade_purchase_delivery(
        db, business_id, purchase_id, user
    )
    if not out:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            detail="Auto-commit not available — verify delivery and complete unit setup first.",
        )
    return _purchase_detail_with_event(business_id, _m.role, out)


@router.post("/{purchase_id}/verify", response_model=TradePurchaseOut)
async def verify_trade_purchase_delivery(
    business_id: uuid.UUID,
    purchase_id: uuid.UUID,
    body: TradePurchaseVerifyIn,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_permission("stock_edit"))],
):
    try:
        out = await tps.verify_trade_purchase_delivery(
            db,
            business_id,
            purchase_id,
            user,
            body,
        )
    except StaleStockVersionError as e:
        raise _stock_version_conflict_http(e) from e
    except ValueError as e:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail=str(e)) from e
    if not out:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Purchase not found")
    return _purchase_detail_with_event(business_id, _m.role, out)


@router.post("/{purchase_id}/mark-paid", response_model=TradePurchaseOut)
async def mark_trade_purchase_paid(
    business_id: uuid.UUID,
    purchase_id: uuid.UUID,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_permission("purchase_edit"))],
    body: TradeMarkPaidRequest = TradeMarkPaidRequest(),
):
    del user
    try:
        out = await tps.mark_trade_purchase_paid(db, business_id, purchase_id, body)
    except ValueError as e:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail=str(e)) from e
    if not out:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Purchase not found")
    _publish_purchase_changed(business_id, out)
    return out


@router.post("/{purchase_id}/cancel", response_model=TradePurchaseOut)
async def cancel_trade_purchase(
    business_id: uuid.UUID,
    purchase_id: uuid.UUID,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_permission("purchase_edit"))],
):
    del user
    try:
        out = await tps.cancel_trade_purchase(db, business_id, purchase_id)
    except ValueError as e:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail=str(e)) from e
    if not out:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Purchase not found")
    _publish_purchase_changed(business_id, out)
    return out


@router.put("/{purchase_id}", response_model=TradePurchaseOut)
async def update_trade_purchase(
    business_id: uuid.UUID,
    purchase_id: uuid.UUID,
    body: TradePurchaseUpdateRequest,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_permission("purchase_edit"))],
):
    del user
    try:
        out = await tps.update_trade_purchase(db, business_id, purchase_id, body)
    except tps.TradePurchaseValidationError as e:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, detail=e.details) from e
    except tps.TradePurchaseDuplicateError as e:
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            detail={
                "code": e.code,
                "message": e.message,
                "existing_id": str(e.existing_id),
                "existing_human_id": e.existing_human_id,
            },
        ) from e
    except tps.TradePurchaseStateConflictError as e:
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            detail={
                "code": e.code,
                "message": e.message,
            },
        ) from e
    except ValueError as e:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail=str(e)) from e
    if not out:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Purchase not found")
    _publish_purchase_changed(
        business_id,
        out,
        item_ids=_catalog_item_ids_from_update(body),
    )
    return out


@router.delete("/{purchase_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_trade_purchase(
    business_id: uuid.UUID,
    purchase_id: uuid.UUID,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_role("owner", "manager", "super_admin"))],
):
    del user
    ok = await tps.delete_trade_purchase(db, business_id, purchase_id)
    if not ok:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Purchase not found")
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/{purchase_id}", response_model=TradePurchaseOut)
async def get_trade_purchase(
    business_id: uuid.UUID,
    purchase_id: uuid.UUID,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
):
    out = await execute_with_retry(
        lambda: tps.get_trade_purchase(db, business_id, purchase_id),
    )
    if not out:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Purchase not found")
    return _purchase_detail_response(_m.role, out)


@router.post(
    "/{purchase_id}/damage-reports",
    response_model=PurchaseDamageReportOut,
    status_code=status.HTTP_201_CREATED,
)
async def create_purchase_damage_report(
    business_id: uuid.UUID,
    purchase_id: uuid.UUID,
    body: PurchaseDamageReportIn,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_permission("stock_edit"))],
):
    del _m
    try:
        row = await pds.create_damage_report(
            db,
            business_id=business_id,
            purchase_id=purchase_id,
            user=user,
            item_name=body.item_name,
            qty_damaged=body.qty_damaged,
            damage_type=body.damage_type,
            catalog_item_id=body.catalog_item_id,
            unit=body.unit,
            reason=body.reason,
            photo_url=body.photo_url,
            notes=body.notes,
            emit_notification=body.emit_notification,
            damaged_items_in_batch=body.damaged_items_in_batch,
        )
    except LookupError:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Purchase not found")
    except ValueError as e:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail=str(e)) from e
    reporter_name = (user.name or user.email or "").strip() or None
    return PurchaseDamageReportOut(
        **pds.damage_report_to_out(row, reporter_name=reporter_name),
    )


@router.get(
    "/{purchase_id}/damage-reports",
    response_model=list[PurchaseDamageReportOut],
)
async def list_purchase_damage_reports(
    business_id: uuid.UUID,
    purchase_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
):
    del _m
    try:
        rows = await pds.list_damage_reports(
            db, business_id=business_id, purchase_id=purchase_id
        )
    except LookupError:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Purchase not found")
    out: list[PurchaseDamageReportOut] = []
    for row, reporter_name in rows:
        out.append(
            PurchaseDamageReportOut(
                **pds.damage_report_to_out(row, reporter_name=reporter_name),
            )
        )
    return out


@router.get("/{purchase_id}/lifecycle-events", response_model=list[PurchaseLifecycleEventOut])
async def list_purchase_lifecycle_events(
    business_id: uuid.UUID,
    purchase_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
):
    del _m
    return await tps.list_purchase_lifecycle_events(db, business_id, purchase_id)


@router.post("/{purchase_id}/lifecycle", response_model=TradePurchaseOut)
async def transition_purchase_lifecycle(
    business_id: uuid.UUID,
    purchase_id: uuid.UUID,
    body: PurchaseLifecycleTransitionIn,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_role("owner", "manager", "super_admin"))],
):
    try:
        out = await tps.transition_purchase_lifecycle(
            db,
            business_id=business_id,
            purchase_id=purchase_id,
            to_status=body.to_status,
            actor=user,
            notes=body.notes,
            metadata=body.metadata,
        )
    except ValueError as e:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail=str(e)) from e
    if not out:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Purchase not found")
    _publish_purchase_changed(business_id, out)
    return _purchase_detail_response(_m.role, out)
