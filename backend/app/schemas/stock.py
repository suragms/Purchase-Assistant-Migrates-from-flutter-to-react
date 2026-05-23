import uuid
from datetime import datetime
from decimal import Decimal

from pydantic import BaseModel, Field


class StockPatchIn(BaseModel):
    new_qty: Decimal = Field(ge=0)
    adjustment_type: str = Field(
        default="verification",
        pattern="^(purchase|sale|usage|transfer|manual|damaged|expired|correction|verification)$",
    )
    reason: str | None = None


class StockListItemOut(BaseModel):
    id: uuid.UUID
    item_code: str | None
    name: str
    category_name: str | None
    subcategory_name: str | None
    supplier_name: str | None = None
    broker_name: str | None = None
    barcode: str | None = None
    default_kg_per_bag: Decimal | None = None
    last_stock_updated_at: datetime | None = None
    last_stock_updated_by: str | None = None
    current_stock: Decimal
    reorder_level: Decimal
    unit: str | None
    rack_location: str | None
    supplier_name: str | None
    stock_status: str
    last_stock_updated_at: datetime | None
    last_stock_updated_by: str | None
    period_purchased_qty: Decimal | None = None
    period_variance_qty: Decimal | None = None
    needs_verification: bool = False
    purchased_today_qty: Decimal | None = None
    usage_today_qty: Decimal | None = None
    days_since_last_purchase: int | None = None
    needs_eviction: bool = False
    is_perishable: bool = False
    missing_barcode: bool = False
    missing_item_code: bool = False
    barcode: str | None = None


class StockListOut(BaseModel):
    items: list[StockListItemOut]
    total: int
    page: int
    per_page: int


class StockAlertsSummaryOut(BaseModel):
    low_stock: int = 0
    critical_stock: int = 0
    missing_barcode: int = 0
    missing_usage_logs: int = 0
    eviction_count: int = 0


class InventorySummaryOut(BaseModel):
    """On-hand warehouse valuation (landing-cost rates only)."""

    total_value_inr: float = 0.0
    bags: float = 0.0
    boxes: float = 0.0
    tins: float = 0.0
    kg: float = 0.0
    item_count: int = 0


class StockTotalsOut(BaseModel):
    """Aggregated on-hand quantities by default unit (warehouse movement view)."""

    total_bags: float = 0.0
    total_kg: float = 0.0
    total_boxes: float = 0.0
    total_tins: float = 0.0
    total_items: int = 0


class RecentPurchaseOut(BaseModel):
    id: uuid.UUID | None = None
    invoice_number: str | None = None
    human_id: str | None = None
    purchase_date: datetime | None
    qty: Decimal | None
    unit: str | None
    rate: Decimal | None
    supplier_name: str | None


class StockDetailOut(StockListItemOut):
    recent_purchases: list[RecentPurchaseOut] = Field(default_factory=list)


class StockAdjustmentOut(BaseModel):
    id: uuid.UUID
    item_id: uuid.UUID | None = None
    item_name: str | None = None
    item_code: str | None = None
    unit: str | None = None
    old_qty: Decimal
    new_qty: Decimal
    adjustment_type: str
    reason: str | None
    updated_by_name: str | None
    updated_at: datetime
    variance_expected_qty: Decimal | None = None
    variance_delta: Decimal | None = None

    model_config = {"from_attributes": True}


class StockIntelligenceOut(BaseModel):
    """Per-item warehouse intelligence for drill-down screens."""

    id: uuid.UUID
    item_code: str | None
    name: str
    category_name: str | None
    subcategory_name: str | None
    current_stock: Decimal
    reorder_level: Decimal
    unit: str | None
    stock_status: str
    period_purchased_qty: Decimal = Decimal("0")
    period_variance_qty: Decimal = Decimal("0")
    needs_verification: bool = False
    recent_purchases: list[RecentPurchaseOut] = Field(default_factory=list)
    recent_adjustments: list[StockAdjustmentOut] = Field(default_factory=list)


class StockVarianceOut(BaseModel):
    item_id: uuid.UUID
    item_name: str
    expected_qty: Decimal
    found_qty: Decimal
    variance_delta: Decimal
    unit: str | None = None
    updated_at: datetime | None = None


class BarcodeLookupOut(BaseModel):
    id: uuid.UUID
    name: str
    item_code: str | None
    barcode: str | None = None
    current_stock: Decimal
    reorder_level: Decimal
    unit: str | None


class BarcodeLabelOut(BaseModel):
    id: uuid.UUID
    barcode: str | None = None
    item_code: str | None
    item_name: str
    category_name: str | None = None
    unit: str | None
    current_stock: Decimal | None = None
    last_purchase_date: datetime | None = None
    last_purchase_qty: Decimal | None = None
    last_purchase_unit: str | None = None
    last_purchase_rate: Decimal | None = None
    supplier_name: str | None = None


class BarcodeBatchIn(BaseModel):
    item_ids: list[uuid.UUID] = Field(min_length=1, max_length=500)


class BarcodeBatchOut(BaseModel):
    labels: list[BarcodeLabelOut]


class ReorderListEntryOut(BaseModel):
    id: uuid.UUID
    item_id: uuid.UUID
    item_name: str
    item_code: str | None
    current_stock: Decimal
    reorder_level: Decimal
    unit: str | None
    status: str
    added_by_name: str | None
    supplier_name: str | None = None
    last_purchase_rate: Decimal | None = None
    created_at: datetime
    updated_at: datetime


class ReorderListOut(BaseModel):
    items: list[ReorderListEntryOut]
    total: int


class ReorderListPatchIn(BaseModel):
    status: str = Field(pattern="^(pending|ordered|done)$")
