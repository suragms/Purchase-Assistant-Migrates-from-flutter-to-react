import uuid
from datetime import datetime

from pydantic import BaseModel, Field


class UserCreateIn(BaseModel):
    full_name: str = Field(min_length=1, max_length=255)
    phone: str = Field(min_length=6, max_length=32)
    role: str = Field(pattern="^(manager|staff)$")
    password: str | None = None
    username: str | None = Field(default=None, max_length=64)
    notes: str | None = Field(default=None, max_length=2000)
    is_active: bool = True


class UserPatchIn(BaseModel):
    full_name: str | None = None
    phone: str | None = None
    role: str | None = Field(default=None, pattern="^(manager|staff|owner)$")
    is_active: bool | None = None
    notes: str | None = Field(default=None, max_length=2000)


class TodayStatsOut(BaseModel):
    scans: int = 0
    stock_updates: int = 0
    items_created: int = 0


class UserListOut(BaseModel):
    id: uuid.UUID
    name: str | None
    phone: str | None
    email: str
    username: str | None = None
    role: str
    is_active: bool
    last_login_at: datetime | None
    last_active_at: datetime | None
    today_stats: TodayStatsOut
    warehouse_name: str | None = None
    activity_count_7d: int = 0
    notes: str | None = None
    created_at: datetime | None = None


class UserProfileOut(UserListOut):
    login_email: str | None = None
    purchases_7d: int = 0
    stock_updates_7d: int = 0


class UserCreateOut(BaseModel):
    user: UserListOut
    generated_password: str | None = None
    login_username: str | None = None
    login_email: str | None = None


class ResetPasswordOut(BaseModel):
    new_password: str
    login_username: str | None = None


class ActivityLogIn(BaseModel):
    action_type: str
    item_id: uuid.UUID | None = None
    item_name: str | None = None
    details: dict | None = None


class ActivityLogOut(BaseModel):
    id: uuid.UUID
    user_name: str | None = None
    action_type: str
    item_id: uuid.UUID | None
    item_name: str | None
    details: dict | None
    created_at: datetime

    model_config = {"from_attributes": True}


class StockAdjustmentOut(BaseModel):
    id: uuid.UUID
    item_id: uuid.UUID
    item_name: str | None = None
    old_qty: float
    new_qty: float
    adjustment_type: str
    reason: str | None = None
    updated_at: datetime

    model_config = {"from_attributes": True}


class UserPurchaseBrief(BaseModel):
    id: uuid.UUID
    human_id: str | None = None
    purchase_date: datetime | None = None
    status: str | None = None
    total_amount: float | None = None


class LedgerEntryOut(BaseModel):
    kind: str
    at: datetime
    title: str
    subtitle: str | None = None
    details: dict | None = None


class PermissionsOut(BaseModel):
    role: str
    permissions: dict[str, bool]


class PermissionsPatchIn(BaseModel):
    permissions: dict[str, bool] = Field(default_factory=dict)
