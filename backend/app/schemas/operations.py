import uuid
from datetime import date, datetime
from decimal import Decimal

from pydantic import BaseModel, Field


class ChecklistTaskOut(BaseModel):
    slot: str
    task_key: str
    label: str
    completed: bool = False
    completed_at: datetime | None = None
    notes: str | None = None


class ChecklistTodayOut(BaseModel):
    checklist_date: date
    tasks: list[ChecklistTaskOut] = Field(default_factory=list)
    completion_pct: float = 0.0


class ChecklistCompleteIn(BaseModel):
    task_key: str = Field(min_length=1, max_length=64)
    notes: str | None = None


class UsageLineOut(BaseModel):
    item_id: uuid.UUID
    item_name: str
    item_code: str | None
    unit: str | None
    opening_qty: Decimal
    purchased_qty: Decimal
    used_qty: Decimal
    closing_qty: Decimal
    logged: bool = False


class UsageTodayOut(BaseModel):
    usage_date: date
    lines: list[UsageLineOut] = Field(default_factory=list)
    missing_count: int = 0


class UsageLineIn(BaseModel):
    item_id: uuid.UUID
    used_qty: Decimal = Field(ge=0)
    notes: str | None = None


class UsageSubmitIn(BaseModel):
    lines: list[UsageLineIn] = Field(min_length=1)


class UsageSummaryOut(BaseModel):
    usage_date: date
    items_logged: int
    items_missing: int
    total_used_qty: Decimal


class DailySnapshotOut(BaseModel):
    item_id: uuid.UUID
    item_name: str
    usage_date: date
    opening_qty: Decimal
    purchased_qty: Decimal
    used_qty: Decimal
    closing_qty: Decimal


class ChecklistSummaryOut(BaseModel):
    checklist_date: date
    completion_pct: float = 0.0
    tasks_total: int = 0
    tasks_completed: int = 0


class ChecklistTemplateOut(BaseModel):
    id: uuid.UUID
    slot: str
    task_key: str
    label: str
    sort_order: int = 0


class ChecklistTemplateItemIn(BaseModel):
    slot: str = Field(pattern="^(morning|midday|evening)$")
    task_key: str | None = Field(default=None, max_length=64)
    label: str = Field(min_length=1, max_length=255)
    sort_order: int = 0


class ChecklistTemplatesPutIn(BaseModel):
    tasks: list[ChecklistTemplateItemIn] = Field(min_length=1, max_length=30)
