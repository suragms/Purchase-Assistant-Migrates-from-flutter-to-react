"""Warehouse stock audit: line upsert, approval threshold, complete → ledger."""

from __future__ import annotations

import uuid
from datetime import datetime, timezone
from decimal import Decimal

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models import CatalogItem, User
from app.models.stock_adjustment import StockAdjustmentLog
from app.models.stock_audit import StockAudit, StockAuditItem
from app.services.staff_audit import log_staff_activity
from app.services.stock_inventory import catalog_stock_qty

# Default: variance above 2 units AND >2% of system qty requires approval.
_APPROVAL_MIN_UNITS = Decimal("2")
_APPROVAL_PCT = Decimal("0.02")


def _user_display(user: User) -> str:
    return user.name or user.username or "User"


def variance_needs_approval(system_qty: Decimal, difference_qty: Decimal) -> bool:
    if difference_qty == 0:
        return False
    abs_diff = abs(difference_qty)
    if abs_diff <= _APPROVAL_MIN_UNITS:
        return False
    if system_qty <= 0:
        return abs_diff > _APPROVAL_MIN_UNITS
    pct = abs_diff / system_qty
    return pct > _APPROVAL_PCT


def _line_status_for_diff(system_qty: Decimal, difference_qty: Decimal) -> str:
    if difference_qty == 0:
        return "matched"
    if variance_needs_approval(system_qty, difference_qty):
        return "pending_approval"
    return "mismatch"


async def _get_catalog_item(
    db: AsyncSession,
    business_id: uuid.UUID,
    item_id: uuid.UUID,
) -> CatalogItem:
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
    return item


async def get_audit_for_business(
    db: AsyncSession,
    business_id: uuid.UUID,
    audit_id: uuid.UUID,
) -> StockAudit:
    r = await db.execute(
        select(StockAudit)
        .where(StockAudit.id == audit_id, StockAudit.business_id == business_id)
        .options(selectinload(StockAudit.items))
    )
    audit = r.scalar_one_or_none()
    if not audit:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Stock audit not found")
    return audit


async def apply_audit_line_to_stock(
    db: AsyncSession,
    *,
    business_id: uuid.UUID,
    user: User,
    item: CatalogItem,
    counted_qty: Decimal,
    adjustment_type: str,
    reason: str,
    audit_id: uuid.UUID | None = None,
) -> StockAdjustmentLog:
    old_qty = catalog_stock_qty(item)
    if counted_qty < 0:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="Stock cannot be negative")
    display = _user_display(user)
    prefix = f"Audit {audit_id}: " if audit_id else ""
    log = StockAdjustmentLog(
        business_id=business_id,
        item_id=item.id,
        old_qty=old_qty,
        new_qty=counted_qty,
        adjustment_type=adjustment_type,
        reason=f"{prefix}{reason}".strip(),
        updated_by=user.id,
        updated_by_name=display,
    )
    item.current_stock = counted_qty
    item.last_stock_updated_at = datetime.now(timezone.utc)
    item.last_stock_updated_by = display
    item.updated_by_user_id = user.id
    db.add(log)
    return log


async def upsert_audit_line(
    db: AsyncSession,
    *,
    business_id: uuid.UUID,
    audit: StockAudit,
    user: User,
    item_id: uuid.UUID,
    counted_qty: Decimal,
    adjustment_type: str | None = None,
    reason: str | None = None,
    notes: str | None = None,
    apply_immediately: bool = False,
) -> StockAuditItem:
    if audit.status not in ("draft", "pending_review"):
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            detail="Audit is not open for new lines",
        )
    item = await _get_catalog_item(db, business_id, item_id)
    system_qty = catalog_stock_qty(item)
    difference_qty = system_qty - counted_qty
    if difference_qty != 0 and not (reason and reason.strip()):
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            detail="Reason required when counted stock differs from system",
        )
    line_status = _line_status_for_diff(system_qty, difference_qty)
    adj_type = adjustment_type or ("verification" if difference_qty == 0 else "correction")

    existing = next((ln for ln in audit.items if ln.item_id == item_id), None)
    if existing:
        existing.system_qty = system_qty
        existing.counted_qty = counted_qty
        existing.difference_qty = difference_qty
        existing.line_status = line_status
        existing.adjustment_type = adj_type
        existing.reason = reason
        existing.notes = notes
        line = existing
    else:
        line = StockAuditItem(
            audit_id=audit.id,
            item_id=item_id,
            system_qty=system_qty,
            counted_qty=counted_qty,
            difference_qty=difference_qty,
            line_status=line_status,
            adjustment_type=adj_type,
            reason=reason,
            notes=notes,
        )
        audit.items.append(line)
        db.add(line)

    if apply_immediately and line_status != "pending_approval" and difference_qty != 0:
        await apply_audit_line_to_stock(
            db,
            business_id=business_id,
            user=user,
            item=item,
            counted_qty=counted_qty,
            adjustment_type=adj_type,
            reason=reason or "Physical count",
            audit_id=audit.id,
        )
        line.line_status = "applied"
        await log_staff_activity(
            db,
            business_id=business_id,
            user=user,
            action_type="STOCK_AUDIT_LINE",
            item_id=item_id,
            item_name=item.name,
            after_data={
                "audit_id": str(audit.id),
                "system_qty": float(system_qty),
                "counted_qty": float(counted_qty),
            },
        )
    return line


async def complete_stock_audit(
    db: AsyncSession,
    *,
    business_id: uuid.UUID,
    audit: StockAudit,
    user: User,
) -> StockAudit:
    if audit.status == "completed":
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="Audit already completed")
    if audit.status not in ("draft", "pending_review"):
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="Audit cannot be completed")

    pending = 0
    applied = 0
    for line in audit.items:
        if line.line_status == "pending_approval":
            pending += 1
            continue
        if line.difference_qty == 0 or line.line_status == "applied":
            if line.difference_qty == 0:
                line.line_status = "matched"
            continue
        item = await _get_catalog_item(db, business_id, line.item_id)
        await apply_audit_line_to_stock(
            db,
            business_id=business_id,
            user=user,
            item=item,
            counted_qty=line.counted_qty,
            adjustment_type=line.adjustment_type or "verification",
            reason=line.reason or "Stock audit complete",
            audit_id=audit.id,
        )
        line.line_status = "applied"
        applied += 1

    audit.status = "pending_review" if pending else "completed"
    await log_staff_activity(
        db,
        business_id=business_id,
        user=user,
        action_type="STOCK_AUDIT_COMPLETE",
        details={
            "audit_id": str(audit.id),
            "applied_lines": applied,
            "pending_approval": pending,
        },
    )
    return audit


async def approve_audit_line(
    db: AsyncSession,
    *,
    business_id: uuid.UUID,
    audit: StockAudit,
    line_id: uuid.UUID,
    user: User,
) -> StockAuditItem:
    line = next((ln for ln in audit.items if ln.id == line_id), None)
    if not line:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Audit line not found")
    if line.line_status != "pending_approval":
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="Line is not pending approval")
    item = await _get_catalog_item(db, business_id, line.item_id)
    await apply_audit_line_to_stock(
        db,
        business_id=business_id,
        user=user,
        item=item,
        counted_qty=line.counted_qty,
        adjustment_type=line.adjustment_type or "correction",
        reason=line.reason or "Approved audit correction",
        audit_id=audit.id,
    )
    line.line_status = "applied"
    if audit.status == "pending_review":
        if not any(ln.line_status == "pending_approval" for ln in audit.items):
            audit.status = "completed"
    return line
