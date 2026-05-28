import uuid
from datetime import datetime
from decimal import Decimal
from typing import Any, Literal

from pydantic import BaseModel, Field


class StockPatchIn(BaseModel):
    new_qty: Decimal = Field(ge=0)
    adjustment_type: str = Field(
        default="verification",
        pattern=(
            "^(purchase|sale|usage|transfer|manual|damaged|expired|correction|"
            "verification|opening_stock)$"
        ),
    )
    reason: str | None = None


class StockPhysicalUpdateIn(BaseModel):
    counted_qty: Decimal = Field(ge=0, max_digits=12, decimal_places=3)
    adjustment_type: Literal["verification", "damaged", "correction", "sale"] = "verification"
    reason: str = Field(min_length=1, max_length=255)
    notes: str | None = Field(default=None, max_length=500)
    last_seen_stock_version: int | None = Field(default=None, ge=0)
    idempotency_key: str | None = Field(default=None, max_length=120)
    period_start: str | None = None
    period_end: str | None = None


class StockMovementOut(BaseModel):
    id: uuid.UUID
    item_id: uuid.UUID
    item_name: str | None = None
    movement_kind: str
    delta_qty: Decimal
    qty_before: Decimal
    qty_after: Decimal
    stock_unit: str | None = None
    reason: str | None = None
    notes: str | None = None
    source_type: str | None = None
    source_id: uuid.UUID | None = None
    idempotency_key: str
    actor_id: uuid.UUID | None = None
    actor_name: str | None = None
    created_at: datetime
    metadata_json: dict[str, Any] | None = None
    duplicate: bool = False

    model_config = {"from_attributes": True}


class StockPhysicalUpdateOut(BaseModel):
    item: "StockDetailOut"
    movement: StockMovementOut


class QuickPurchaseIn(BaseModel):
    qty: Decimal = Field(gt=0, max_digits=12, decimal_places=3)
    supplier_id: uuid.UUID
    broker_id: uuid.UUID | None = None
    notes: str | None = Field(default=None, max_length=500)
    idempotency_key: str | None = Field(default=None, max_length=120)


class QuickPurchaseOut(BaseModel):
    purchase_log: "StaffPurchaseLogOut"
    movement: StockMovementOut
    item: "StockDetailOut"


class StockActivityEventOut(BaseModel):
    id: str
    kind: str
    title: str
    qty_before: Decimal | None = None
    qty_after: Decimal | None = None
    delta_qty: Decimal | None = None
    unit: str | None = None
    reason: str | None = None
    notes: str | None = None
    actor_name: str | None = None
    supplier_name: str | None = None
    broker_name: str | None = None
    created_at: datetime
    source_type: str | None = None
    source_id: str | None = None


class StockItemActivityOut(BaseModel):
    item: "StockDetailOut"
    movements: list[StockMovementOut] = Field(default_factory=list)
    purchases: list["StaffPurchaseLogOut"] = Field(default_factory=list)
    activity: list[StockActivityEventOut] = Field(default_factory=list)


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
    period_usage_qty: Decimal | None = None
    period_variance_qty: Decimal | None = None
    ledger_variance_qty: Decimal | None = None
    stock_unit: str | None = None
    current_stock_kg: Decimal | None = None
    needs_verification: bool = False
    purchased_today_qty: Decimal | None = None
    usage_today_qty: Decimal | None = None
    days_since_last_purchase: int | None = None
    needs_eviction: bool = False
    is_perishable: bool = False
    missing_barcode: bool = False
    missing_item_code: bool = False
    barcode: str | None = None
    last_purchase_human_id: str | None = None
    last_purchase_delivered: bool | None = None
    has_pending_order: bool = False
    pending_order_days: int | None = None
    pending_delivery_qty: Decimal | None = None
    physical_stock_qty: Decimal | None = None
    physical_stock_difference_qty: Decimal | None = None
    physical_stock_counted_at: datetime | None = None
    physical_stock_counted_by: str | None = None
    warehouse_diff_qty: Decimal | None = None
    opening_stock_qty: Decimal | None = None
    opening_stock_set_at: datetime | None = None
    opening_stock_set_by: str | None = None
    opening_stock_locked: bool = False
    stock_version: int = 0


class StockListOut(BaseModel):
    items: list[StockListItemOut]
    total: int
    page: int
    per_page: int


class StockAlertsSummaryOut(BaseModel):
    low_stock: int = 0
    critical_stock: int = 0
    out_of_stock: int = 0
    active_out_of_stock: int = 0
    missing_barcode: int = 0
    missing_item_code: int = 0
    missing_usage_logs: int = 0
    eviction_count: int = 0
    total_items: int = 0


class WarehouseAlertsSummaryOut(BaseModel):
    pending_deliveries: int = 0
    low_stock: int = 0
    critical_stock: int = 0
    pending_verifications: int = 0
    missing_barcode: int = 0
    missing_usage_logs: int = 0
    eviction_count: int = 0
    checklist_completion_pct: float = 100.0
    total_items: int = 0


class LowStockOpsSummaryOut(BaseModel):
    """Header KPI slice for the low-stock operations surface."""

    total_attention: int = 0
    out_of_stock: int = 0
    pending_purchase: int = 0
    delayed_supplier: int = 0
    mismatch_items: int = 0
    pending_verification: int = 0
    disputed_items: int = 0

    # P0/P1: units-based estimate (no valuation in this v1 endpoint).
    estimated_impact_units_per_day: float = 0.0


class LowStockOpsItemOut(StockListItemOut):
    priority_score: float = 0.0
    priority_band: str = "normal"

    is_delayed_supplier: bool = False
    has_mismatch: bool = False
    verification_state: str = "none"  # none | pending | verified
    lifecycle_stage: str = "attention"
    reorder_entry_status: str | None = None
    has_open_dispute: bool = False


class LowStockOpsOut(BaseModel):
    summary_slice: LowStockOpsSummaryOut
    items: list[LowStockOpsItemOut]
    total: int = 0
    page: int = 1
    per_page: int = 50


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
    entered_qty: Decimal | None = None
    entered_unit: str | None = None
    qty_in_stock_unit: Decimal | None = None
    stock_unit: str | None = None
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


class PhysicalStockCountIn(BaseModel):
    counted_qty: Decimal = Field(ge=0, max_digits=12, decimal_places=3)
    period_start: str | None = None
    period_end: str | None = None
    notes: str | None = Field(default=None, max_length=500)


class PhysicalStockCountOut(BaseModel):
    id: uuid.UUID
    item_id: uuid.UUID
    item_name: str | None = None
    system_qty: Decimal
    counted_qty: Decimal
    difference_qty: Decimal
    purchased_qty: Decimal | None = None
    stock_unit: str | None = None
    period_start: str | None = None
    period_end: str | None = None
    notes: str | None = None
    counted_by_name: str | None = None
    counted_at: datetime


class OpeningStockIn(BaseModel):
    qty: Decimal = Field(ge=0, max_digits=12, decimal_places=3)
    override: bool = False
    reason: str | None = Field(default=None, max_length=500)
    notes: str | None = Field(default=None, max_length=500)
    idempotency_key: str | None = Field(default=None, max_length=120)


class OpeningStockMissingOut(BaseModel):
    items: list[StockListItemOut]
    missing_count: int


class OpeningStockSetupSummaryOut(BaseModel):
    pending_count: int = 0
    completed_count: int = 0
    total_count: int = 0
    last_updated_at: datetime | None = None
    last_updated_by: str | None = None


class OpeningStockSetupItemOut(StockListItemOut):
    setup_status: Literal["pending", "completed"] = "pending"
    barcode_state: Literal["ok", "missing"] = "ok"


class OpeningStockSetupOut(BaseModel):
    summary: OpeningStockSetupSummaryOut
    items: list[OpeningStockSetupItemOut]
    total: int
    page: int
    per_page: int


class StaffPurchaseLogIn(BaseModel):
    item_id: uuid.UUID
    qty: Decimal = Field(gt=0, max_digits=12, decimal_places=3)
    amount: Decimal | None = Field(default=None, ge=0, max_digits=12, decimal_places=2)
    supplier_id: uuid.UUID | None = None
    supplier_name: str | None = Field(default=None, max_length=255)
    broker_id: uuid.UUID | None = None
    broker_name: str | None = Field(default=None, max_length=255)
    notes: str | None = Field(default=None, max_length=500)
    idempotency_key: str | None = Field(default=None, max_length=120)


class StaffPurchaseLogOut(BaseModel):
    id: uuid.UUID
    item_id: uuid.UUID
    item_name: str
    qty: Decimal
    unit: str | None = None
    amount: Decimal | None = None
    supplier_id: uuid.UUID | None = None
    supplier_name: str | None = None
    broker_id: uuid.UUID | None = None
    broker_name: str | None = None
    notes: str | None = None
    idempotency_key: str | None = None
    stock_movement_id: uuid.UUID | None = None
    created_by_name: str | None = None
    created_at: datetime


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
    period_usage_qty: Decimal = Decimal("0")
    period_variance_qty: Decimal | None = None
    ledger_variance_qty: Decimal | None = None
    stock_unit: str | None = None
    stock_tracking: dict | None = None
    current_stock_kg: Decimal | None = None
    default_kg_per_bag: Decimal | None = None
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
    last_purchase_date: datetime | None = None
    last_purchase_qty: Decimal | None = None
    last_purchase_unit: str | None = None
    last_purchase_rate: Decimal | None = None
    supplier_name: str | None = None


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
