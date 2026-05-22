"""Business-scoped warehouse stock audit sessions."""

from __future__ import annotations

import uuid
from datetime import date
from decimal import Decimal
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.database import get_db
from app.deps import get_current_user, require_membership, require_permission
from app.models import Membership, User
from app.models.stock_audit import StockAudit, StockAuditItem
from app.schemas.stock_audit import (
    StockAuditCreate,
    StockAuditKpisOut,
    StockAuditLineUpsert,
    StockAuditOut,
    StockAuditUpdate,
)
from app.services.stock_audit_service import (
    approve_audit_line,
    complete_stock_audit,
    get_audit_for_business,
    upsert_audit_line,
)
from app.services.stock_inventory import catalog_stock_qty

router = APIRouter(
    prefix="/v1/businesses/{business_id}/stock-audits",
    tags=["stock-audits"],
)

# Legacy global prefix — forwards to business-scoped handlers where possible.
legacy_router = APIRouter(prefix="/v1/stock-audits", tags=["stock-audits-legacy"])


def _audit_to_out(audit: StockAudit) -> StockAuditOut:
    return StockAuditOut.model_validate(audit)


@router.post("", response_model=StockAuditOut, status_code=status.HTTP_201_CREATED)
async def create_stock_audit(
    business_id: uuid.UUID,
    audit_in: StockAuditCreate,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
    _m: Annotated[Membership, Depends(require_permission("stock_edit"))],
):
    db_audit = StockAudit(
        business_id=business_id,
        audit_date=audit_in.audit_date or date.today(),
        auditor_id=current_user.id,
        status="draft",
        notes=audit_in.notes,
    )
    db.add(db_audit)
    await db.flush()

    for item_in in audit_in.items:
        await upsert_audit_line(
            db,
            business_id=business_id,
            audit=db_audit,
            user=current_user,
            item_id=item_in.item_id,
            counted_qty=item_in.counted_qty,
            adjustment_type=item_in.adjustment_type,
            reason=item_in.reason,
            notes=item_in.notes,
        )

    await db.commit()
    return _audit_to_out(await get_audit_for_business(db, business_id, db_audit.id))


@router.get("/active", response_model=StockAuditOut | None)
async def get_active_stock_audit(
    business_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
    _m: Annotated[Membership, Depends(require_membership)],
):
    r = await db.execute(
        select(StockAudit)
        .where(
            StockAudit.business_id == business_id,
            StockAudit.auditor_id == current_user.id,
            StockAudit.status.in_(("draft", "pending_review")),
        )
        .order_by(StockAudit.created_at.desc())
        .limit(1)
        .options(selectinload(StockAudit.items))
    )
    audit = r.scalar_one_or_none()
    return _audit_to_out(audit) if audit else None


@router.get("", response_model=list[StockAuditOut])
async def list_stock_audits(
    business_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
    skip: int = 0,
    limit: int = 100,
):
    result = await db.execute(
        select(StockAudit)
        .where(StockAudit.business_id == business_id)
        .order_by(StockAudit.created_at.desc())
        .offset(skip)
        .limit(limit)
        .options(selectinload(StockAudit.items))
    )
    return [_audit_to_out(a) for a in result.scalars().all()]


@router.get("/kpis", response_model=StockAuditKpisOut)
async def stock_audit_kpis(
    business_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
):
    today = date.today()
    items_today = await db.scalar(
        select(func.count(StockAuditItem.id))
        .join(StockAudit, StockAudit.id == StockAuditItem.audit_id)
        .where(
            StockAudit.business_id == business_id,
            StockAudit.audit_date == today,
        )
    )
    mismatch_today = await db.scalar(
        select(func.count(StockAuditItem.id))
        .join(StockAudit, StockAudit.id == StockAuditItem.audit_id)
        .where(
            StockAudit.business_id == business_id,
            StockAudit.audit_date == today,
            StockAuditItem.difference_qty != 0,
        )
    )
    pending = await db.scalar(
        select(func.count(StockAuditItem.id))
        .join(StockAudit, StockAudit.id == StockAuditItem.audit_id)
        .where(
            StockAudit.business_id == business_id,
            StockAuditItem.line_status == "pending_approval",
        )
    )
    drafts = await db.scalar(
        select(func.count(StockAudit.id)).where(
            StockAudit.business_id == business_id,
            StockAudit.status == "draft",
        )
    )
    return StockAuditKpisOut(
        items_audited_today=int(items_today or 0),
        mismatch_lines_today=int(mismatch_today or 0),
        pending_approval_count=int(pending or 0),
        open_draft_sessions=int(drafts or 0),
    )


@router.get("/{audit_id}", response_model=StockAuditOut)
async def get_stock_audit(
    business_id: uuid.UUID,
    audit_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
):
    return _audit_to_out(await get_audit_for_business(db, business_id, audit_id))


@router.put("/{audit_id}", response_model=StockAuditOut)
async def update_stock_audit(
    business_id: uuid.UUID,
    audit_id: uuid.UUID,
    audit_in: StockAuditUpdate,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
    _m: Annotated[Membership, Depends(require_permission("stock_edit"))],
):
    db_audit = await get_audit_for_business(db, business_id, audit_id)
    if db_audit.status in ("completed",):
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            detail="Completed stock audits cannot be modified",
        )

    if audit_in.notes is not None:
        db_audit.notes = audit_in.notes

    if audit_in.items is not None:
        db_audit.items.clear()
        await db.flush()
        for item_in in audit_in.items:
            await upsert_audit_line(
                db,
                business_id=business_id,
                audit=db_audit,
                user=current_user,
                item_id=item_in.item_id,
                counted_qty=item_in.counted_qty,
                adjustment_type=item_in.adjustment_type,
                reason=item_in.reason,
                notes=item_in.notes,
            )

    await db.commit()
    return _audit_to_out(await get_audit_for_business(db, business_id, audit_id))


@router.post("/{audit_id}/lines", response_model=StockAuditOut)
async def upsert_stock_audit_line(
    business_id: uuid.UUID,
    audit_id: uuid.UUID,
    body: StockAuditLineUpsert,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
    _m: Annotated[Membership, Depends(require_permission("stock_edit"))],
):
    audit = await get_audit_for_business(db, business_id, audit_id)
    await upsert_audit_line(
        db,
        business_id=business_id,
        audit=audit,
        user=current_user,
        item_id=body.item_id,
        counted_qty=body.counted_qty,
        adjustment_type=body.adjustment_type,
        reason=body.reason,
        notes=body.notes,
        apply_immediately=body.apply_immediately,
    )
    await db.commit()
    return _audit_to_out(await get_audit_for_business(db, business_id, audit_id))


@router.post("/{audit_id}/complete", response_model=StockAuditOut)
async def complete_stock_audit_endpoint(
    business_id: uuid.UUID,
    audit_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
    _m: Annotated[Membership, Depends(require_permission("stock_edit"))],
):
    audit = await get_audit_for_business(db, business_id, audit_id)
    await complete_stock_audit(
        db, business_id=business_id, audit=audit, user=current_user
    )
    await db.commit()
    return _audit_to_out(await get_audit_for_business(db, business_id, audit_id))


@router.post("/{audit_id}/lines/{line_id}/approve", response_model=StockAuditOut)
async def approve_stock_audit_line(
    business_id: uuid.UUID,
    audit_id: uuid.UUID,
    line_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
    _m: Annotated[Membership, Depends(require_membership)],
):
    if _m.role not in ("owner", "manager", "admin"):
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail="Approval requires manager or owner")
    audit = await get_audit_for_business(db, business_id, audit_id)
    await approve_audit_line(
        db, business_id=business_id, audit=audit, line_id=line_id, user=current_user
    )
    await db.commit()
    return _audit_to_out(await get_audit_for_business(db, business_id, audit_id))


@router.delete("/{audit_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_stock_audit(
    business_id: uuid.UUID,
    audit_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_permission("stock_edit"))],
):
    db_audit = await get_audit_for_business(db, business_id, audit_id)
    if db_audit.status in ("completed", "pending_review"):
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            detail="Only draft audits can be deleted",
        )
    await db.delete(db_audit)
    await db.commit()
    return None
