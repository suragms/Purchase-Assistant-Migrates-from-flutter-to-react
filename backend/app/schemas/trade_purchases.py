"""Pydantic contracts for wholesale trade purchases (new tables)."""

from __future__ import annotations

import uuid
from datetime import date, datetime
from decimal import Decimal
from typing import Any

from pydantic import BaseModel, ConfigDict, Field, model_validator

from app.services import decimal_precision as dp


_LINE_NUMERIC_INPUTS = {
    "qty",
    "landing_cost",
    "purchase_rate",
    "kg_per_unit",
    "weight_per_unit",
    "landing_cost_per_kg",
    "selling_cost",
    "selling_rate",
    "freight_value",
    "freight_amount",
    "delivered_rate",
    "billty_rate",
    "items_per_box",
    "weight_per_item",
    "kg_per_box",
    "weight_per_tin",
    "discount",
    "tax_percent",
}

_HEADER_NUMERIC_INPUTS = {
    "discount",
    "header_discount",
    "commission_percent",
    "commission_money",
    "delivered_rate",
    "billty_rate",
    "freight_amount",
    "freight_value",
    "paid_amount",
    "total_amount",
}


def _reject_float_inputs(data: dict[str, Any], keys: set[str]) -> None:
    bad = sorted(k for k in keys if isinstance(data.get(k), float))
    if bad:
        raise ValueError(
            "Decimal values must be sent as strings, not JSON floats: " + ", ".join(bad)
        )


class DecimalModel(BaseModel):
    model_config = ConfigDict(
        populate_by_name=True,
        json_encoders={Decimal: lambda v: format(v, "f")},
    )


class TradePurchaseLineIn(DecimalModel):
    """Catalog-linked purchase line.

    Phase 6 contract: every line must reference a `catalog_item_id`. This
    matches the strict client-side rule in `purchaseLineIsValidForSave` so
    server-only callers cannot slip free-typed items past the Flutter
    validation and break category/item analytics.
    """

    catalog_item_id: uuid.UUID
    item_name: str = Field(..., min_length=1, max_length=512)
    qty: Decimal = Field(..., gt=0)
    unit: str = Field(..., min_length=1, max_length=32)
    landing_cost: Decimal = Field(..., gt=0)
    purchase_rate: Decimal | None = Field(None, gt=0)
    """For bag/sack + per-kg pricing: weight per line unit (e.g. 50 for a 50 kg bag)."""
    kg_per_unit: Decimal | None = Field(None, gt=0)
    weight_per_unit: Decimal | None = Field(None, gt=0)
    """Rupee cost per kilogram; line gross = qty * kg_per_unit * landing_cost_per_kg when both set."""
    landing_cost_per_kg: Decimal | None = Field(None, gt=0)
    selling_cost: Decimal | None = Field(None, ge=0)
    selling_rate: Decimal | None = Field(None, ge=0)
    freight_type: str | None = Field(default=None, pattern="^(included|separate)$")
    freight_value: Decimal | None = Field(None, ge=0)
    delivered_rate: Decimal | None = Field(None, ge=0)
    billty_rate: Decimal | None = Field(None, ge=0)
    box_mode: str | None = Field(default=None, pattern="^(items_per_box|fixed_weight_box)$")
    items_per_box: Decimal | None = Field(None, gt=0)
    weight_per_item: Decimal | None = Field(None, gt=0)
    kg_per_box: Decimal | None = Field(None, gt=0)
    weight_per_tin: Decimal | None = Field(None, gt=0)
    discount: Decimal | None = Field(None, ge=0)
    tax_percent: Decimal | None = Field(None, ge=0)
    tax_mode: str | None = Field(default="exclusive", pattern="^(exclusive|inclusive|none)$")
    payment_days: int | None = Field(None, ge=0, le=3650)
    hsn_code: str | None = Field(None, max_length=32)
    item_code: str | None = Field(None, max_length=64)
    description: str | None = Field(None, max_length=512)

    @model_validator(mode="before")
    @classmethod
    def _accept_business_aliases(cls, data: Any) -> Any:
        if not isinstance(data, dict):
            return data
        out = dict(data)
        _reject_float_inputs(out, _LINE_NUMERIC_INPUTS)
        if "landing_cost" not in out and "purchase_rate" in out:
            out["landing_cost"] = out["purchase_rate"]
        if "purchase_rate" not in out and "landing_cost" in out:
            out["purchase_rate"] = out["landing_cost"]
        if "selling_cost" not in out and "selling_rate" in out:
            out["selling_cost"] = out["selling_rate"]
        if "selling_rate" not in out and "selling_cost" in out:
            out["selling_rate"] = out["selling_cost"]
        if "kg_per_unit" not in out and "weight_per_unit" in out:
            out["kg_per_unit"] = out["weight_per_unit"]
        if "weight_per_unit" not in out and "kg_per_unit" in out:
            out["weight_per_unit"] = out["kg_per_unit"]
        if "freight_value" not in out and "freight_amount" in out:
            out["freight_value"] = out["freight_amount"]
        return out

    @model_validator(mode="after")
    def _normalize_decimal_precision(self) -> "TradePurchaseLineIn":
        self.qty = dp.qty(self.qty)
        self.purchase_rate = dp.rate(self.purchase_rate) if self.purchase_rate is not None else dp.rate(self.landing_cost)
        self.landing_cost = self.purchase_rate
        self.kg_per_unit = dp.weight(self.kg_per_unit) if self.kg_per_unit is not None else None
        self.weight_per_unit = (
            dp.weight(self.weight_per_unit)
            if self.weight_per_unit is not None
            else self.kg_per_unit
        )
        self.kg_per_unit = self.weight_per_unit
        self.landing_cost_per_kg = (
            dp.rate(self.landing_cost_per_kg) if self.landing_cost_per_kg is not None else None
        )
        self.selling_rate = dp.rate(self.selling_rate) if self.selling_rate is not None else (
            dp.rate(self.selling_cost) if self.selling_cost is not None else None
        )
        self.selling_cost = self.selling_rate
        self.freight_value = dp.money(self.freight_value) if self.freight_value is not None else None
        self.delivered_rate = dp.money(self.delivered_rate) if self.delivered_rate is not None else None
        self.billty_rate = dp.money(self.billty_rate) if self.billty_rate is not None else None
        self.items_per_box = dp.qty(self.items_per_box) if self.items_per_box is not None else None
        self.weight_per_item = dp.weight(self.weight_per_item) if self.weight_per_item is not None else None
        self.kg_per_box = dp.weight(self.kg_per_box) if self.kg_per_box is not None else None
        self.weight_per_tin = dp.weight(self.weight_per_tin) if self.weight_per_tin is not None else None
        self.discount = dp.percent(self.discount) if self.discount is not None else None
        self.tax_percent = dp.percent(self.tax_percent) if self.tax_percent is not None else None
        a, b = self.kg_per_unit, self.landing_cost_per_kg
        if (a is None) != (b is None):
            raise ValueError("kg_per_unit and landing_cost_per_kg must both be set or both omitted")
        unit = (self.unit or "").strip().upper()
        if unit == "BAG" and self.weight_per_unit is None:
            raise ValueError("kg_per_bag is required for BAG")
        # Master rebuild: default wholesale mode treats BOX/TIN as count-only units.
        # Weight fields are optional; kg totals for these units are not tracked unless
        # an explicit future \"advanced inventory\" mode is added.
        return self


class TradePurchaseCreateRequest(DecimalModel):
    purchase_date: date
    invoice_number: str | None = Field(None, max_length=64)
    supplier_id: uuid.UUID
    broker_id: uuid.UUID | None = None
    force_duplicate: bool = Field(
        False,
        description="When true, skip server-side duplicate detection (user confirmed).",
    )
    status: str = Field(default="confirmed", pattern="^(draft|saved|confirmed)$")
    payment_days: int | None = Field(None, ge=0, le=3650)
    discount: Decimal | None = Field(None, ge=0)
    commission_percent: Decimal | None = Field(None, ge=0)
    commission_mode: str = Field(
        default="percent",
        pattern="^(percent|flat_invoice|flat_kg|flat_bag|flat_box|flat_tin)$",
    )
    commission_money: Decimal | None = Field(None, ge=0)
    delivered_rate: Decimal | None = Field(None, ge=0)
    billty_rate: Decimal | None = Field(None, ge=0)
    freight_amount: Decimal | None = Field(None, ge=0)
    freight_type: str | None = Field(default=None, pattern="^(included|separate)$")
    lines: list[TradePurchaseLineIn] = Field(default_factory=list)

    @model_validator(mode="before")
    @classmethod
    def _accept_business_aliases(cls, data: Any) -> Any:
        if not isinstance(data, dict):
            return data
        out = dict(data)
        _reject_float_inputs(out, _HEADER_NUMERIC_INPUTS)
        if "freight_amount" not in out and "freight_value" in out:
            out["freight_amount"] = out["freight_value"]
        if "discount" not in out and "header_discount" in out:
            out["discount"] = out["header_discount"]
        return out

    @model_validator(mode="after")
    def _normalize_decimal_precision(self) -> "TradePurchaseCreateRequest":
        self.discount = dp.percent(self.discount) if self.discount is not None else None
        mode = self.commission_mode.strip().lower()
        if mode not in ("percent", "flat_invoice", "flat_kg", "flat_bag", "flat_box", "flat_tin"):
            mode = "percent"
        self.commission_mode = mode
        if mode == "percent":
            self.commission_money = None
            self.commission_percent = (
                dp.percent(self.commission_percent) if self.commission_percent is not None else None
            )
        else:
            self.commission_percent = None
            self.commission_money = (
                dp.money(self.commission_money) if self.commission_money is not None else None
            )
        self.delivered_rate = dp.money(self.delivered_rate) if self.delivered_rate is not None else None
        self.billty_rate = dp.money(self.billty_rate) if self.billty_rate is not None else None
        self.freight_amount = dp.money(self.freight_amount) if self.freight_amount is not None else None
        return self


class TradePurchaseLineOut(DecimalModel):
    id: uuid.UUID
    catalog_item_id: uuid.UUID
    item_name: str
    qty: Decimal
    unit: str
    unit_type: str | None = None
    landing_cost: Decimal
    purchase_rate: Decimal | None = None
    kg_per_unit: Decimal | None = None
    weight_per_unit: Decimal | None = None
    landing_cost_per_kg: Decimal | None = None
    selling_cost: Decimal | None
    selling_rate: Decimal | None = None
    freight_type: str | None = None
    freight_value: Decimal | None = None
    delivered_rate: Decimal | None = None
    billty_rate: Decimal | None = None
    total_weight: Decimal | None = None
    line_total: Decimal | None = Field(
        default=None,
        description="Tax/discount-inclusive line purchase amount (matches persisted line_total / line_money).",
    )
    profit: Decimal | None = None
    box_mode: str | None = None
    items_per_box: Decimal | None = None
    weight_per_item: Decimal | None = None
    kg_per_box: Decimal | None = None
    weight_per_tin: Decimal | None = None
    discount: Decimal | None
    tax_percent: Decimal | None
    payment_days: int | None = None
    hsn_code: str | None = None
    item_code: str | None = None
    description: str | None = None
    # From linked catalog item (for BAG/kg math in clients; omitted when no catalog row).
    default_unit: str | None = None
    default_kg_per_bag: Decimal | None = None
    default_purchase_unit: str | None = None
    line_landing_gross: Decimal = Field(
        default=Decimal("0"),
        description="Pre-discount / pre-tax landing gross (line_gross_base); not interchangeable with line_total.",
    )
    line_selling_gross: Decimal = Decimal("0")
    line_profit: Decimal | None = None
    rate_context: dict[str, Any] = Field(
        default_factory=dict,
        description="Display hints for DynamicUnitLabelEngine (not authoritative money).",
    )


class StockUpdateOut(DecimalModel):
    catalog_item_id: uuid.UUID
    name: str
    unit: str | None = None
    old_qty: Decimal
    new_qty: Decimal
    delta: Decimal
    needs_unit_setup: bool = False
    line_unit: str | None = None


class TradePurchaseOut(DecimalModel):
    id: uuid.UUID
    human_id: str
    invoice_number: str | None = None
    purchase_date: date
    supplier_id: uuid.UUID
    broker_id: uuid.UUID | None
    payment_days: int | None
    due_date: date | None = None
    paid_amount: Decimal = Decimal("0")
    paid_at: datetime | None = None
    discount: Decimal | None
    commission_percent: Decimal | None
    commission_mode: str = "percent"
    commission_money: Decimal | None = None
    delivered_rate: Decimal | None
    billty_rate: Decimal | None
    freight_amount: Decimal | None
    freight_type: str | None = None
    total_qty: Decimal | None
    total_amount: Decimal
    total_landing_subtotal: Decimal | None = None
    total_selling_subtotal: Decimal | None = None
    total_line_profit: Decimal | None = None
    status: str
    remaining: Decimal = Decimal("0")
    derived_status: str = "confirmed"
    items_count: int = 0
    supplier_name: str | None = None
    broker_name: str | None = None
    supplier_gst: str | None = None
    supplier_address: str | None = None
    supplier_phone: str | None = None
    supplier_whatsapp: str | None = None
    broker_phone: str | None = None
    broker_location: str | None = None
    broker_image_url: str | None = None
    created_at: datetime
    updated_at: datetime | None = None
    lines: list[TradePurchaseLineOut]
    header_discount: Decimal | None = None
    freight_value: Decimal | None = None
    has_missing_details: bool = False
    is_delivered: bool = False
    delivered_at: datetime | None = None
    delivery_notes: str | None = None
    delivery_status: str = "pending"
    dispatched_at: datetime | None = None
    arrived_at: datetime | None = None
    staff_verified_at: datetime | None = None
    staff_verified_by_name: str | None = None
    created_by_name: str | None = None
    stock_committed_at: datetime | None = None
    staff_verified_qty: Decimal | None = None
    delivered_qty_committed: Decimal | None = None
    truck_number: str | None = None
    driver_contact: str | None = None
    dispatch_note: str | None = None
    stock_updates: list[StockUpdateOut] = Field(default_factory=list)


class TradePurchaseDeliveryPatch(DecimalModel):
    is_delivered: bool
    delivered_at: datetime | None = None
    delivery_notes: str | None = Field(None, max_length=2000)


class TradePurchaseVerificationLineIn(DecimalModel):
    line_id: uuid.UUID
    received_qty: Decimal = Field(..., ge=0)
    damaged_qty: Decimal = Field(Decimal("0"), ge=0)
    return_qty: Decimal = Field(Decimal("0"), ge=0)


class TradePurchaseVerifyIn(DecimalModel):
    lines: list[TradePurchaseVerificationLineIn] = Field(default_factory=list)
    notes: str | None = Field(None, max_length=2000)


class TradePurchaseDispatchIn(DecimalModel):
    truck_number: str | None = Field(None, max_length=100)
    driver_contact: str | None = Field(None, max_length=100)
    dispatch_note: str | None = Field(None, max_length=2000)
    mark_in_transit: bool = False


class TradePurchaseArriveIn(DecimalModel):
    notes: str | None = Field(None, max_length=2000)
    truck_number: str | None = Field(None, max_length=100)
    driver_contact: str | None = Field(None, max_length=100)
    damage_qty: Decimal | None = None
    missing_qty: Decimal | None = None
    broker_confirmed: bool | None = None


class TradePurchaseDeliveryPipelineOut(DecimalModel):
    pending: int = 0
    dispatched: int = 0
    in_transit: int = 0
    arrived: int = 0
    staff_verifying: int = 0
    staff_verified: int = 0
    partial: int = 0
    stock_committed: int = 0
    cancelled: int = 0
    total_pending_amount: Decimal = Decimal("0")


class TradePurchaseUpdateRequest(TradePurchaseCreateRequest):
    """Full replace of header + lines (wizard edit)."""


class TradePurchasePaymentPatch(DecimalModel):
    paid_amount: Decimal = Field(..., ge=0)
    paid_at: datetime | None = None

    @model_validator(mode="after")
    def _normalize_decimal_precision(self) -> "TradePurchasePaymentPatch":
        self.paid_amount = dp.money(self.paid_amount)
        return self


class TradeMarkPaidRequest(DecimalModel):
    """Optional partial payment; default pays remaining balance."""

    paid_amount: Decimal | None = Field(None, ge=0)
    paid_at: datetime | None = None

    @model_validator(mode="after")
    def _normalize_decimal_precision(self) -> "TradeMarkPaidRequest":
        self.paid_amount = dp.money(self.paid_amount) if self.paid_amount is not None else None
        return self


class TradeDuplicateCheckRequest(DecimalModel):
    supplier_id: uuid.UUID | None = None
    purchase_date: date
    total_amount: Decimal = Field(..., ge=0)
    lines: list[TradePurchaseLineIn] = Field(default_factory=list)

    @model_validator(mode="after")
    def _normalize_decimal_precision(self) -> "TradeDuplicateCheckRequest":
        self.total_amount = dp.total(self.total_amount)
        return self


class TradeDuplicateCheckResponse(DecimalModel):
    duplicate: bool
    message: str | None = None
    existing_id: uuid.UUID | None = None
    existing_human_id: str | None = None


class TradeNextHumanIdOut(DecimalModel):
    human_id: str


class TradeDraftUpsertRequest(DecimalModel):
    step: int = Field(0, ge=0, le=3)
    payload: dict[str, Any] = Field(default_factory=dict)


class TradeDraftOut(DecimalModel):
    step: int
    payload: dict[str, Any]
    updated_at: datetime


class TradePurchasePreviewLineOut(DecimalModel):
    """Per-line fiscal preview (matches persisted ``line_total`` / weight / profit math)."""

    index: int = Field(..., ge=0)
    line_total: Decimal
    line_landing_gross: Decimal
    line_profit: Decimal | None = None
    line_total_weight_kg: Decimal = Decimal("0")
    resolved_labels: dict[str, Any] = Field(
        default_factory=dict,
        description="``unit_resolution_service.resolve_from_text`` snapshot for labels.",
    )
    rate_context: dict[str, Any] = Field(
        default_factory=dict,
        description="Per-line display basis for rate/qty labels (Flutter DynamicUnitLabelEngine).",
    )


class TradePurchasePreviewOut(DecimalModel):
    lines: list[TradePurchasePreviewLineOut]
    total_qty: Decimal
    total_amount: Decimal
    total_landing_subtotal: Decimal | None = None
    total_selling_subtotal: Decimal | None = None
    total_line_profit: Decimal | None = None


class TradePurchaseValidateOut(DecimalModel):
    ok: bool
    errors: list[dict[str, Any]]
    warnings: list[dict[str, Any]] = Field(default_factory=list)


class PurchaseLifecycleTransitionIn(DecimalModel):
    to_status: str = Field(
        ...,
        pattern=(
            "^(draft|active|approved|ordered|supplier_confirmed|in_transit|arrived|"
            "verification_pending|verified|added_to_stock|completed|cancelled)$"
        ),
    )
    notes: str | None = Field(None, max_length=2000)
    metadata: dict[str, Any] = Field(default_factory=dict)


class PurchaseLifecycleEventOut(DecimalModel):
    id: uuid.UUID
    purchase_id: uuid.UUID
    business_id: uuid.UUID
    from_status: str | None = None
    to_status: str
    actor_id: uuid.UUID | None = None
    actor_name: str | None = None
    notes: str | None = None
    metadata: dict[str, Any] = Field(default_factory=dict)
    created_at: datetime
