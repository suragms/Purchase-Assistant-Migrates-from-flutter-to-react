import uuid
from datetime import datetime

from pydantic import BaseModel, Field


class NotificationOut(BaseModel):
    id: uuid.UUID
    kind: str
    title: str
    body: str | None
    priority: str = "medium"
    category: str = "system"
    action_route: str | None = None
    triggered_by_user_id: uuid.UUID | None = None
    triggered_by_name: str | None = None
    related_item_id: uuid.UUID | None = None
    related_purchase_id: uuid.UUID | None = None
    related_supplier_id: uuid.UUID | None = None
    payload: dict | None
    metadata: dict | None = Field(default=None, validation_alias="alert_metadata")
    read_at: datetime | None
    created_at: datetime

    model_config = {"from_attributes": True, "populate_by_name": True}


class NotificationReadPatch(BaseModel):
    read: bool = Field(default=True)


class UnreadCountOut(BaseModel):
    unread: int


class NotificationBulkActionOut(BaseModel):
    updated: int


class NotificationSummaryOut(BaseModel):
    unread: int
    by_category: dict[str, int] = Field(default_factory=dict)
    by_priority: dict[str, int] = Field(default_factory=dict)


class ClientNotificationEventIn(BaseModel):
    kind: str = Field(max_length=64)
    title: str = Field(max_length=500)
    body: str | None = Field(default=None, max_length=4000)
    priority: str = Field(default="medium", max_length=16)
    category: str = Field(default="system", max_length=32)
    action_route: str | None = Field(default=None, max_length=256)
    related_item_id: uuid.UUID | None = None
    related_purchase_id: uuid.UUID | None = None
    dedupe_key: str | None = Field(default=None, max_length=220)
