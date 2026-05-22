from __future__ import annotations

import uuid
from datetime import date, datetime
from decimal import Decimal

from pydantic import BaseModel, Field


class StockAuditItemBase(BaseModel):
    item_id: uuid.UUID
    system_qty: Decimal | None = Field(default=None, max_digits=10, decimal_places=2)
    counted_qty: Decimal = Field(..., max_digits=10, decimal_places=2)


class StockAuditItemCreate(StockAuditItemBase):
    adjustment_type: str | None = None
    reason: str | None = None
    notes: str | None = None


class StockAuditLineUpsert(BaseModel):
    item_id: uuid.UUID
    counted_qty: Decimal = Field(..., max_digits=10, decimal_places=2)
    adjustment_type: str | None = None
    reason: str | None = None
    notes: str | None = None
    apply_immediately: bool = False


class StockAuditItemOut(BaseModel):
    id: uuid.UUID
    audit_id: uuid.UUID
    item_id: uuid.UUID
    system_qty: Decimal = Field(..., max_digits=10, decimal_places=2)
    counted_qty: Decimal = Field(..., max_digits=10, decimal_places=2)
    difference_qty: Decimal = Field(..., max_digits=10, decimal_places=2)
    line_status: str = "recorded"
    adjustment_type: str | None = None
    reason: str | None = None
    notes: str | None = None

    model_config = {"from_attributes": True}


class StockAuditBase(BaseModel):
    notes: str | None = None


class StockAuditCreate(StockAuditBase):
    audit_date: date | None = None
    items: list[StockAuditItemCreate] = Field(default_factory=list)


class StockAuditUpdate(BaseModel):
    notes: str | None = None
    status: str | None = None
    items: list[StockAuditItemCreate] | None = None


class StockAuditOut(BaseModel):
    id: uuid.UUID
    business_id: uuid.UUID | None = None
    audit_date: date
    auditor_id: uuid.UUID | None
    status: str
    notes: str | None
    created_at: datetime
    updated_at: datetime
    items: list[StockAuditItemOut] = Field(default_factory=list)

    model_config = {"from_attributes": True}


class StockVerifyCountIn(BaseModel):
    counted_qty: Decimal = Field(..., max_digits=10, decimal_places=2)
    adjustment_type: str = "verification"
    reason: str = Field(..., min_length=1, max_length=500)
    notes: str | None = None


class StockAuditKpisOut(BaseModel):
    items_audited_today: int = 0
    mismatch_lines_today: int = 0
    pending_approval_count: int = 0
    open_draft_sessions: int = 0
