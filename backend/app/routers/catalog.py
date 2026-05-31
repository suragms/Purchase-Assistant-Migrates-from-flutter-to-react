import logging
import re
import time
import uuid
from datetime import date
from collections.abc import Sequence
from typing import Annotated, Any

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field, field_validator, model_validator
from sqlalchemy import and_, case, delete, desc, exists, func, select
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import load_only

from app.database import get_db
from app.db_resilience import execute_with_retry
from app.db_schema_compat import catalog_items_has_type_id_column
from app.deps import require_membership, require_owner_membership, require_permission
from app.models import (
    CatalogItem,
    CatalogVariant,
    CategoryType,
    EntryLineItem,
    ItemCategory,
    Membership,
    TradePurchase,
    TradePurchaseLine,
)
from app.models.catalog import CatalogItemDefaultBroker, CatalogItemDefaultSupplier
from app.models.contacts import Broker, Supplier
from app.models.supplier_item_default import SupplierItemDefault
from app.services import trade_query as tq
from app.services.fuzzy_catalog import rank_ids_by_token_sort
from app.services.staff_view import (
    redact_catalog_item_out_model,
    redact_catalog_line_row_model,
    should_redact_financials,
)
from app.services.unit_resolution_service import (
    merge_unit_resolution_into_catalog_row,
    resolve_for_catalog_item,
    resolve_from_text,
)

router = APIRouter(prefix="/v1/businesses/{business_id}", tags=["catalog"])

logger = logging.getLogger(__name__)

GENERAL_TYPE_NAME = "General"


def _norm_name(s: str) -> str:
    return " ".join(s.lower().strip().split())


class ItemCategoryCreate(BaseModel):
    name: str = Field(min_length=1, max_length=255)


class ItemCategoryUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=255)


class ItemCategoryOut(BaseModel):
    id: uuid.UUID
    name: str

    model_config = {"from_attributes": True}


class CategoryTypeCreate(BaseModel):
    name: str = Field(min_length=1, max_length=255)


class CategoryTypeUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=255)


class CategoryTypeOut(BaseModel):
    id: uuid.UUID
    category_id: uuid.UUID
    name: str

    model_config = {"from_attributes": True}


class CategoryTypeIndexOut(BaseModel):
    """Flat list of category types with parent category name (quick-add / search UIs)."""

    id: uuid.UUID
    category_id: uuid.UUID
    category_name: str
    name: str


class CatalogFuzzyCheckHitOut(BaseModel):
    id: uuid.UUID
    name: str
    score: float = Field(..., ge=0, le=1, description="RapidFuzz token_sort_ratio / 100")


class CatalogFuzzyCheckOut(BaseModel):
    hits: list[CatalogFuzzyCheckHitOut]


class DuplicatePairOut(BaseModel):
    id_a: uuid.UUID
    name_a: str
    id_b: uuid.UUID
    name_b: str
    score: float = Field(..., ge=0, le=1)


class BulkItemIdsIn(BaseModel):
    item_ids: list[uuid.UUID] = Field(min_length=1, max_length=200)


class BulkReorderIn(BaseModel):
    item_ids: list[uuid.UUID] = Field(min_length=1, max_length=200)
    reorder_level: float = Field(ge=0)


_UNIT_PATTERN = "^(kg|box|piece|bag|tin)$"


def _dedupe_preserve_order(ids: list[uuid.UUID]) -> list[uuid.UUID]:
    seen: set[uuid.UUID] = set()
    out: list[uuid.UUID] = []
    for x in ids:
        if x not in seen:
            seen.add(x)
            out.append(x)
    return out


def _normalize_package_type(v: str | None) -> str | None:
    if not v:
        return None
    m = v.strip().upper()
    alias = {
        "RETAIL_PACKET": "RETAIL_PACKET",
        "WHOLESALE_BAG": "SACK",
        "SACK": "SACK",
        "LOOSE_KG": "LOOSE",
        "LOOSE": "LOOSE",
        "BOX": "BOX",
        "TIN": "TIN",
        "PIECE": "PIECE",
    }
    return alias.get(m, m)


class CatalogItemCreate(BaseModel):
    category_id: uuid.UUID
    type_id: uuid.UUID | None = None
    name: str = Field(min_length=1, max_length=512)
    default_unit: str = Field(pattern=_UNIT_PATTERN)
    default_kg_per_bag: float | None = Field(default=None, gt=0)
    default_items_per_box: float | None = Field(default=None, gt=0)
    default_weight_per_tin: float | None = Field(default=None, gt=0)
    default_purchase_unit: str | None = Field(default=None, pattern=_UNIT_PATTERN)
    default_sale_unit: str | None = Field(default=None, pattern=_UNIT_PATTERN)
    hsn_code: str | None = Field(default=None, max_length=32)
    item_code: str | None = Field(default=None, max_length=64)
    barcode: str | None = Field(default=None, max_length=64)
    tax_percent: float | None = Field(default=None, ge=0, le=100)
    default_landing_cost: float | None = Field(default=None, ge=0)
    default_selling_cost: float | None = Field(default=None, ge=0)
    default_supplier_ids: list[uuid.UUID] = Field(min_length=1)
    default_broker_ids: list[uuid.UUID] | None = None
    package_type: str | None = Field(default=None, max_length=32)

    @field_validator("name", mode="before")
    @classmethod
    def _strip_required_str(cls, v: object) -> object:
        if isinstance(v, str):
            return v.strip()
        return v

    @field_validator("name")
    @classmethod
    def _name_nonempty(cls, v: str) -> str:
        if not v or not v.strip():
            raise ValueError("name must not be empty or whitespace")
        return " ".join(v.split())

    @field_validator("hsn_code", "item_code", mode="before")
    @classmethod
    def _hsn_optional(cls, v: object) -> object:
        if v is None:
            return None
        if isinstance(v, str):
            t = v.strip()
            return t if t else None
        return v

    @model_validator(mode="after")
    def _unit_conditional(self) -> "CatalogItemCreate":
        u = self.default_unit
        if u == "bag":
            if self.default_kg_per_bag is None:
                raise ValueError("default_kg_per_bag is required when default_unit is bag")
        elif u == "piece" and self.default_kg_per_bag is not None:
            if self.default_kg_per_bag <= 0:
                raise ValueError("weight per packet must be positive")
        elif u == "box":
            if self.default_items_per_box is None:
                raise ValueError("default_items_per_box is required when default_unit is box")
        return self


class CatalogBatchItemIn(BaseModel):
    """One row for POST /catalog-items/batch (category inferred from type_id)."""

    name: str = Field(min_length=1, max_length=512)
    type_id: uuid.UUID
    default_unit: str = Field(pattern=_UNIT_PATTERN)
    default_kg_per_bag: float | None = Field(default=None, gt=0)
    default_items_per_box: float | None = Field(default=None, gt=0)
    default_weight_per_tin: float | None = Field(default=None, gt=0)
    default_supplier_ids: list[uuid.UUID] = Field(min_length=1)
    package_type: str | None = Field(default=None, max_length=32)

    @field_validator("name", mode="before")
    @classmethod
    def _strip_batch_name(cls, v: object) -> object:
        if isinstance(v, str):
            return v.strip()
        return v

    @field_validator("name")
    @classmethod
    def _name_nonempty_batch(cls, v: str) -> str:
        if not v or not v.strip():
            raise ValueError("name must not be empty or whitespace")
        return " ".join(v.split())

    @model_validator(mode="after")
    def _unit_conditional_batch(self) -> "CatalogBatchItemIn":
        u = self.default_unit
        if u == "bag":
            if self.default_kg_per_bag is None:
                raise ValueError("default_kg_per_bag is required when default_unit is bag")
        elif u == "box":
            if self.default_items_per_box is None:
                raise ValueError("default_items_per_box is required when default_unit is box")
        return self


class CatalogBatchCreate(BaseModel):
    items: list[CatalogBatchItemIn] = Field(min_length=1, max_length=80)


class CatalogItemUpdate(BaseModel):
    category_id: uuid.UUID | None = None
    type_id: uuid.UUID | None = None
    name: str | None = Field(default=None, min_length=1, max_length=512)
    default_unit: str | None = Field(default=None, pattern=_UNIT_PATTERN)
    default_kg_per_bag: float | None = Field(default=None, gt=0)
    default_items_per_box: float | None = Field(default=None, gt=0)
    default_weight_per_tin: float | None = Field(default=None, gt=0)
    default_purchase_unit: str | None = Field(default=None, pattern=_UNIT_PATTERN)
    default_sale_unit: str | None = Field(default=None, pattern=_UNIT_PATTERN)
    hsn_code: str | None = Field(default=None, max_length=32)
    item_code: str | None = Field(default=None, max_length=64)
    tax_percent: float | None = Field(default=None, ge=0, le=100)
    default_landing_cost: float | None = Field(default=None, ge=0)
    default_selling_cost: float | None = Field(default=None, ge=0)
    default_supplier_ids: list[uuid.UUID] | None = None
    default_broker_ids: list[uuid.UUID] | None = None
    reorder_level: float | None = Field(default=None, ge=0)

    @field_validator("name", "hsn_code", "item_code", mode="before")
    @classmethod
    def _strip_update_str(cls, v: object) -> object:
        if v is None:
            return v
        if isinstance(v, str):
            t = v.strip()
            return t if t else None
        return v

    @field_validator("name")
    @classmethod
    def _name_if_set(cls, v: str | None) -> str | None:
        if v is None:
            return v
        if not v.strip():
            raise ValueError("name must not be empty or whitespace")
        return " ".join(v.split())


class CatalogItemOut(BaseModel):
    id: uuid.UUID
    category_id: uuid.UUID
    type_id: uuid.UUID | None = None
    type_name: str | None = None
    name: str
    default_unit: str | None
    default_kg_per_bag: float | None = None
    default_items_per_box: float | None = None
    default_weight_per_tin: float | None = None
    default_purchase_unit: str | None = None
    default_sale_unit: str | None = None
    hsn_code: str | None = None
    item_code: str | None = None
    barcode: str | None = None
    public_token: str | None = None
    tax_percent: float | None = None
    default_landing_cost: float | None = None
    default_selling_cost: float | None = None
    last_purchase_price: float | None = None
    last_selling_rate: float | None = None
    last_supplier_id: uuid.UUID | None = None
    last_broker_id: uuid.UUID | None = None
    last_trade_purchase_id: uuid.UUID | None = None
    last_line_qty: float | None = None
    last_line_unit: str | None = None
    last_line_weight_kg: float | None = None
    last_supplier_name: str | None = None
    last_broker_name: str | None = None
    default_supplier_ids: list[uuid.UUID] = Field(default_factory=list)
    default_broker_ids: list[uuid.UUID] = Field(default_factory=list)
    last_purchase_date: date | None = Field(
        default=None,
        description="Latest trade purchase date for this item (non-deleted/cancelled), if any.",
    )
    last_purchase_delivered: bool | None = Field(
        default=None,
        description="is_delivered on the snapshot last trade purchase (last_trade_purchase_id), if any.",
    )
    unit_resolution: dict[str, Any] | None = Field(
        default=None,
        description="Read-only smart-unit / package labels from unit_resolution_service (no DB writes).",
    )

    model_config = {"from_attributes": True}


class CatalogBatchOut(BaseModel):
    created: int
    skipped: int
    items: list[CatalogItemOut]


class SupplierPurchaseDefaultsOut(BaseModel):
    catalog_item_id: uuid.UUID
    supplier_id: uuid.UUID
    last_price: float | None = None
    last_discount: float | None = None
    last_payment_days: int | None = None
    purchase_count: int = 0
    item_hsn_code: str | None = None
    item_tax_percent: float | None = None
    item_default_unit: str | None = None
    item_default_kg_per_bag: float | None = None
    item_default_landing_cost: float | None = None
    item_default_purchase_unit: str | None = None


class CatalogVariantCreate(BaseModel):
    name: str = Field(min_length=1, max_length=512)
    default_kg_per_bag: float | None = Field(default=None, gt=0)


class CatalogVariantUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=512)
    default_kg_per_bag: float | None = Field(default=None, gt=0)


class CatalogVariantOut(BaseModel):
    id: uuid.UUID
    catalog_item_id: uuid.UUID
    name: str
    default_kg_per_bag: float | None

    model_config = {"from_attributes": True}


class CatalogItemInsightsOut(BaseModel):
    line_count: int
    entry_count: int
    total_profit: float
    avg_landing: float | None
    avg_selling: float | None
    last_entry_date: date | None
    profit_margin_pct: float | None


class CategoryInsightsOut(BaseModel):
    item_count: int
    linked_line_count: int
    total_profit: float
    top_item_name: str | None
    top_item_profit: float | None
    worst_item_name: str | None
    worst_item_profit: float | None


class CategoryTradeItemRow(BaseModel):
    catalog_item_id: uuid.UUID
    name: str
    period_line_total: float = 0.0
    period_qty_bags: float = 0.0
    period_weight_kg: float = 0.0
    last_purchase_price: float | None = None
    last_selling_rate: float | None = None
    last_supplier_name: str | None = None
    last_broker_name: str | None = None
    last_trade_human_id: str | None = None


class CategoryTradeSummaryOut(BaseModel):
    """Aggregates for catalog items in a category (confirmed trade lines only)."""

    item_count: int
    total_line_amount: float
    total_qty_bags: float
    total_weight_kg: float
    items: list[CategoryTradeItemRow]


class CatalogItemLineRow(BaseModel):
    """One line for a catalog item on a wholesale trade purchase.

    ``entry_id`` is ``trade_purchase_lines.id`` (stable row id for the list).
    """

    entry_id: uuid.UUID
    entry_date: date
    qty: float
    unit: str
    landing_cost: float
    selling_price: float | None = None
    profit: float | None = None
    supplier_name: str | None = None
    supplier_phone: str | None = None
    broker_name: str | None = None
    broker_phone: str | None = None
    purchase_human_id: str | None = None
    kg_per_unit: float | None = None
    landing_cost_per_kg: float | None = None
    unit_resolution: dict[str, Any] | None = Field(
        default=None,
        description="Read-only labels from unit_resolution_service for the line item name.",
    )


class TradeSupplierPriceRow(BaseModel):
    supplier_id: uuid.UUID
    supplier_name: str
    landing_cost: float
    unit: str
    last_purchase_date: date
    is_best: bool = False
    deals: int = 0
    volume_weighted_landing: float | None = None


class CatalogItemTradeSupplierPricesOut(BaseModel):
    """Latest trade purchase line per supplier + last five landed prices (any supplier)."""

    catalog_item_id: uuid.UUID
    suppliers: list[TradeSupplierPriceRow] = Field(default_factory=list)
    last_five_landing_prices: list[float] = Field(default_factory=list)
    avg_landing_from_trade: float | None = None


def _trade_purchase_date_filter(business_id: uuid.UUID, from_date: date, to_date: date):
    return tq.trade_purchase_date_filter(business_id, from_date, to_date)


async def _max_purchase_date_for_catalog_item(
    db: AsyncSession,
    business_id: uuid.UUID,
    catalog_item_id: uuid.UUID,
) -> date | None:
    """Latest purchase_date for this catalog item from report-eligible trade purchases."""
    r = await db.execute(
        select(func.max(TradePurchase.purchase_date))
        .select_from(TradePurchaseLine)
        .join(TradePurchase, TradePurchase.id == TradePurchaseLine.trade_purchase_id)
        .where(
            TradePurchase.business_id == business_id,
            TradePurchaseLine.catalog_item_id == catalog_item_id,
            tq.trade_purchase_status_in_reports(),
        )
    )
    return r.scalar_one_or_none()


async def _max_purchase_dates_for_catalog_items_bulk(
    db: AsyncSession,
    business_id: uuid.UUID,
    catalog_item_ids: list[uuid.UUID],
) -> dict[uuid.UUID, date]:
    """Latest purchase_date per catalog item (report-eligible trade lines)."""
    if not catalog_item_ids:
        return {}
    r = await db.execute(
        select(
            TradePurchaseLine.catalog_item_id,
            func.max(TradePurchase.purchase_date),
        )
        .select_from(TradePurchaseLine)
        .join(TradePurchase, TradePurchase.id == TradePurchaseLine.trade_purchase_id)
        .where(
            TradePurchase.business_id == business_id,
            TradePurchaseLine.catalog_item_id.in_(catalog_item_ids),
            tq.trade_purchase_status_in_reports(),
        )
        .group_by(TradePurchaseLine.catalog_item_id)
    )
    return {row[0]: row[1] for row in r.all() if row[1] is not None}


async def _is_delivered_for_trade_purchase_ids(
    db: AsyncSession,
    business_id: uuid.UUID,
    purchase_ids: list[uuid.UUID],
) -> dict[uuid.UUID, bool]:
    if not purchase_ids:
        return {}
    r = await db.execute(
        select(TradePurchase.id, TradePurchase.delivery_status).where(
            TradePurchase.business_id == business_id,
            TradePurchase.id.in_(purchase_ids),
            TradePurchase.status.notin_(("deleted", "cancelled")),
        )
    )
    return {
        row[0]: (row[1] or "").strip().lower() == "stock_committed"
        for row in r.all()
    }


async def _last_purchase_delivered_for_snapshot(
    db: AsyncSession,
    business_id: uuid.UUID,
    last_trade_purchase_id: uuid.UUID | None,
) -> bool | None:
    if last_trade_purchase_id is None:
        return None
    m = await _is_delivered_for_trade_purchase_ids(db, business_id, [last_trade_purchase_id])
    return m.get(last_trade_purchase_id)


async def _category_dup(
    db: AsyncSession, business_id: uuid.UUID, name: str, exclude_id: uuid.UUID | None = None
) -> bool:
    q = select(ItemCategory.id).where(
        ItemCategory.business_id == business_id,
        func.lower(ItemCategory.name) == _norm_name(name),
    )
    if exclude_id is not None:
        q = q.where(ItemCategory.id != exclude_id)
    r = await db.execute(q)
    return r.first() is not None


async def _item_dup(
    db: AsyncSession,
    business_id: uuid.UUID,
    category_id: uuid.UUID,
    type_id: uuid.UUID | None,
    name: str,
    exclude_id: uuid.UUID | None = None,
    *,
    has_type_col: bool = True,
) -> bool:
    q = select(CatalogItem.id).where(
        CatalogItem.business_id == business_id,
        CatalogItem.category_id == category_id,
        func.lower(CatalogItem.name) == _norm_name(name),
    )
    if has_type_col:
        if type_id is not None:
            q = q.where(CatalogItem.type_id == type_id)
        else:
            q = q.where(CatalogItem.type_id.is_(None))
    if exclude_id is not None:
        q = q.where(CatalogItem.id != exclude_id)
    r = await db.execute(q)
    return r.first() is not None


async def _type_name_dup(
    db: AsyncSession,
    category_id: uuid.UUID,
    name: str,
    exclude_id: uuid.UUID | None = None,
) -> bool:
    q = select(CategoryType.id).where(
        CategoryType.category_id == category_id,
        func.lower(CategoryType.name) == _norm_name(name),
    )
    if exclude_id is not None:
        q = q.where(CategoryType.id != exclude_id)
    r = await db.execute(q)
    return r.first() is not None


async def _get_or_create_general_type_id(
    db: AsyncSession, business_id: uuid.UUID, category_id: uuid.UUID
) -> uuid.UUID:
    r = await db.execute(
        select(CategoryType.id).where(
            CategoryType.category_id == category_id,
            func.lower(CategoryType.name) == _norm_name(GENERAL_TYPE_NAME),
        )
    )
    row = r.first()
    if row is not None:
        return row[0]
    cr = await db.execute(
        select(ItemCategory.id).where(
            ItemCategory.id == category_id,
            ItemCategory.business_id == business_id,
        )
    )
    if cr.first() is None:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="category_id not found in this business")
    ct = CategoryType(category_id=category_id, name=GENERAL_TYPE_NAME)
    db.add(ct)
    await db.flush()
    return ct.id


class _UnsetSentinel:
    __slots__ = ()


_UNSET = _UnsetSentinel()

# Columns safe to load when catalog_items.type_id is missing (older DBs).
_CATALOG_ITEM_CORE = (
    CatalogItem.id,
    CatalogItem.business_id,
    CatalogItem.category_id,
    CatalogItem.name,
    CatalogItem.default_unit,
    CatalogItem.default_kg_per_bag,
    CatalogItem.default_items_per_box,
    CatalogItem.default_weight_per_tin,
    CatalogItem.hsn_code,
    CatalogItem.item_code,
    CatalogItem.tax_percent,
    CatalogItem.default_landing_cost,
    CatalogItem.default_selling_cost,
    CatalogItem.default_purchase_unit,
    CatalogItem.default_sale_unit,
    CatalogItem.last_purchase_price,
    CatalogItem.last_selling_rate,
    CatalogItem.last_supplier_id,
    CatalogItem.last_broker_id,
    CatalogItem.last_trade_purchase_id,
    CatalogItem.last_line_qty,
    CatalogItem.last_line_unit,
    CatalogItem.last_line_weight_kg,
    CatalogItem.created_at,
)


def _catalog_item_out(
    i: CatalogItem,
    type_name: str | None = None,
    *,
    type_id: uuid.UUID | None | _UnsetSentinel = _UNSET,
    default_supplier_ids: list[uuid.UUID] | None = None,
    default_broker_ids: list[uuid.UUID] | None = None,
    last_supplier_name: str | None = None,
    last_broker_name: str | None = None,
    category_name: str | None = None,
    last_purchase_date: date | None = None,
    last_purchase_delivered: bool | None = None,
) -> CatalogItemOut:
    tid = i.type_id if type_id is _UNSET else type_id
    dipb = getattr(i, "default_items_per_box", None)
    dwt = getattr(i, "default_weight_per_tin", None)
    unit_res = resolve_for_catalog_item(i, item_name=i.name, category_name=category_name).as_dict()
    return CatalogItemOut(
        id=i.id,
        category_id=i.category_id,
        type_id=tid,
        type_name=type_name,
        name=i.name,
        default_unit=i.default_unit,
        default_kg_per_bag=float(i.default_kg_per_bag) if i.default_kg_per_bag is not None else None,
        default_items_per_box=float(dipb) if dipb is not None else None,
        default_weight_per_tin=float(dwt) if dwt is not None else None,
        default_purchase_unit=getattr(i, "default_purchase_unit", None),
        default_sale_unit=getattr(i, "default_sale_unit", None),
        hsn_code=getattr(i, "hsn_code", None),
        item_code=getattr(i, "item_code", None),
        barcode=getattr(i, "barcode", None),
        public_token=getattr(i, "public_token", None),
        tax_percent=float(i.tax_percent) if getattr(i, "tax_percent", None) is not None else None,
        default_landing_cost=float(i.default_landing_cost)
        if getattr(i, "default_landing_cost", None) is not None
        else None,
        default_selling_cost=float(i.default_selling_cost)
        if getattr(i, "default_selling_cost", None) is not None
        else None,
        last_purchase_price=float(i.last_purchase_price)
        if getattr(i, "last_purchase_price", None) is not None
        else None,
        last_selling_rate=float(ls)
        if (ls := getattr(i, "last_selling_rate", None)) is not None
        else None,
        last_supplier_id=getattr(i, "last_supplier_id", None),
        last_broker_id=getattr(i, "last_broker_id", None),
        last_trade_purchase_id=getattr(i, "last_trade_purchase_id", None),
        last_line_qty=float(lq) if (lq := getattr(i, "last_line_qty", None)) is not None else None,
        last_line_unit=getattr(i, "last_line_unit", None),
        last_line_weight_kg=float(lw)
        if (lw := getattr(i, "last_line_weight_kg", None)) is not None
        else None,
        last_supplier_name=last_supplier_name,
        last_broker_name=last_broker_name,
        default_supplier_ids=list(default_supplier_ids or ()),
        default_broker_ids=list(default_broker_ids or ()),
        last_purchase_date=last_purchase_date,
        last_purchase_delivered=last_purchase_delivered,
        unit_resolution=unit_res,
    )


def _maybe_redact_catalog_out(out: CatalogItemOut, role: str) -> CatalogItemOut:
    if should_redact_financials(role):
        return redact_catalog_item_out_model(out)
    return out


async def _assert_supplier_ids_in_business(
    db: AsyncSession,
    business_id: uuid.UUID,
    supplier_ids: list[uuid.UUID],
) -> None:
    if not supplier_ids:
        return
    r = await db.execute(
        select(func.count(Supplier.id)).where(
            Supplier.business_id == business_id,
            Supplier.id.in_(supplier_ids),
        )
    )
    if int(r.scalar() or 0) != len(supplier_ids):
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            detail="One or more default_supplier_ids are invalid for this business",
        )


async def _supplier_broker_name_maps_by_ids(
    db: AsyncSession,
    business_id: uuid.UUID,
    supplier_ids: set[uuid.UUID],
    broker_ids: set[uuid.UUID],
) -> tuple[dict[uuid.UUID, str], dict[uuid.UUID, str]]:
    sm: dict[uuid.UUID, str] = {}
    bm: dict[uuid.UUID, str] = {}
    if supplier_ids:
        sr = await db.execute(
            select(Supplier.id, Supplier.name).where(
                Supplier.business_id == business_id,
                Supplier.id.in_(supplier_ids),
            )
        )
        sm = {row[0]: row[1] for row in sr.all()}
    if broker_ids:
        br = await db.execute(
            select(Broker.id, Broker.name).where(
                Broker.business_id == business_id,
                Broker.id.in_(broker_ids),
            )
        )
        bm = {row[0]: row[1] for row in br.all()}
    return sm, bm


async def _last_party_names_for_catalog_items(
    db: AsyncSession,
    business_id: uuid.UUID,
    items: Sequence[CatalogItem],
) -> tuple[dict[uuid.UUID, str], dict[uuid.UUID, str]]:
    """Resolve last_supplier_id / last_broker_id to display names for API consumers."""
    s_ids = {i.last_supplier_id for i in items if getattr(i, "last_supplier_id", None) is not None}
    b_ids = {i.last_broker_id for i in items if getattr(i, "last_broker_id", None) is not None}
    return await _supplier_broker_name_maps_by_ids(db, business_id, s_ids, b_ids)


async def _assert_broker_ids_in_business(
    db: AsyncSession,
    business_id: uuid.UUID,
    broker_ids: list[uuid.UUID],
) -> None:
    if not broker_ids:
        return
    r = await db.execute(
        select(func.count(Broker.id)).where(
            Broker.business_id == business_id,
            Broker.id.in_(broker_ids),
        )
    )
    if int(r.scalar() or 0) != len(broker_ids):
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            detail="One or more default_broker_ids are invalid for this business",
        )


async def _default_supplier_broker_ids_for_items(
    db: AsyncSession,
    business_id: uuid.UUID,
    item_ids: list[uuid.UUID],
) -> tuple[dict[uuid.UUID, list[uuid.UUID]], dict[uuid.UUID, list[uuid.UUID]]]:
    if not item_ids:
        return {}, {}
    sup_map: dict[uuid.UUID, list[uuid.UUID]] = {i: [] for i in item_ids}
    brok_map: dict[uuid.UUID, list[uuid.UUID]] = {i: [] for i in item_ids}
    sr = await db.execute(
        select(
            CatalogItemDefaultSupplier.catalog_item_id,
            CatalogItemDefaultSupplier.supplier_id,
            CatalogItemDefaultSupplier.sort_order,
        )
        .where(
            CatalogItemDefaultSupplier.business_id == business_id,
            CatalogItemDefaultSupplier.catalog_item_id.in_(item_ids),
        )
        .order_by(
            CatalogItemDefaultSupplier.catalog_item_id,
            CatalogItemDefaultSupplier.sort_order,
            CatalogItemDefaultSupplier.supplier_id,
        )
    )
    for cid, sid, _ord in sr.all():
        sup_map[cid].append(sid)
    br = await db.execute(
        select(
            CatalogItemDefaultBroker.catalog_item_id,
            CatalogItemDefaultBroker.broker_id,
            CatalogItemDefaultBroker.sort_order,
        )
        .where(
            CatalogItemDefaultBroker.business_id == business_id,
            CatalogItemDefaultBroker.catalog_item_id.in_(item_ids),
        )
        .order_by(
            CatalogItemDefaultBroker.catalog_item_id,
            CatalogItemDefaultBroker.sort_order,
            CatalogItemDefaultBroker.broker_id,
        )
    )
    for cid, bid, _ord in br.all():
        brok_map[cid].append(bid)
    return sup_map, brok_map


async def _replace_default_supplier_rows(
    db: AsyncSession,
    business_id: uuid.UUID,
    catalog_item_id: uuid.UUID,
    supplier_ids: list[uuid.UUID],
) -> None:
    await db.execute(
        delete(CatalogItemDefaultSupplier).where(
            CatalogItemDefaultSupplier.business_id == business_id,
            CatalogItemDefaultSupplier.catalog_item_id == catalog_item_id,
        )
    )
    for order, sid in enumerate(supplier_ids):
        db.add(
            CatalogItemDefaultSupplier(
                business_id=business_id,
                catalog_item_id=catalog_item_id,
                supplier_id=sid,
                sort_order=order,
            )
        )


async def _replace_default_broker_rows(
    db: AsyncSession,
    business_id: uuid.UUID,
    catalog_item_id: uuid.UUID,
    broker_ids: list[uuid.UUID],
) -> None:
    await db.execute(
        delete(CatalogItemDefaultBroker).where(
            CatalogItemDefaultBroker.business_id == business_id,
            CatalogItemDefaultBroker.catalog_item_id == catalog_item_id,
        )
    )
    for order, bid in enumerate(broker_ids):
        db.add(
            CatalogItemDefaultBroker(
                business_id=business_id,
                catalog_item_id=catalog_item_id,
                broker_id=bid,
                sort_order=order,
            )
        )


async def _seed_supplier_item_defaults(
    db: AsyncSession,
    business_id: uuid.UUID,
    catalog_item_id: uuid.UUID,
    supplier_ids: list[uuid.UUID],
) -> None:
    for sid in supplier_ids:
        ex = await db.execute(
            select(SupplierItemDefault.id).where(
                SupplierItemDefault.business_id == business_id,
                SupplierItemDefault.catalog_item_id == catalog_item_id,
                SupplierItemDefault.supplier_id == sid,
            )
        )
        if ex.first() is None:
            db.add(
                SupplierItemDefault(
                    business_id=business_id,
                    catalog_item_id=catalog_item_id,
                    supplier_id=sid,
                    purchase_count=0,
                )
            )


def _sync_item_unit_extras(i: CatalogItem) -> None:
    u = i.default_unit
    if u != "bag":
        i.default_kg_per_bag = None
    if u != "box":
        i.default_items_per_box = None
    if u != "tin":
        i.default_weight_per_tin = None


def _validate_item_unit_constraints(i: CatalogItem) -> None:
    u = i.default_unit
    if u == "bag":
        if i.default_kg_per_bag is None or float(i.default_kg_per_bag) <= 0:
            raise HTTPException(
                status.HTTP_400_BAD_REQUEST,
                detail="default_kg_per_bag is required and must be positive when default_unit is bag",
            )
    elif u == "box":
        if i.default_items_per_box is None or float(i.default_items_per_box) <= 0:
            raise HTTPException(
                status.HTTP_400_BAD_REQUEST,
                detail="default_items_per_box is required and must be positive when default_unit is box",
            )
    elif u == "tin" and i.default_weight_per_tin is not None and float(i.default_weight_per_tin) <= 0:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            detail="default_weight_per_tin must be positive when set",
        )


async def _verify_type_in_category(
    db: AsyncSession,
    business_id: uuid.UUID,
    category_id: uuid.UUID,
    type_id: uuid.UUID,
) -> None:
    r = await db.execute(
        select(CategoryType.id)
        .join(ItemCategory, ItemCategory.id == CategoryType.category_id)
        .where(
            CategoryType.id == type_id,
            CategoryType.category_id == category_id,
            ItemCategory.business_id == business_id,
        )
    )
    if r.first() is None:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="type_id not found for this category")


async def _variant_dup(
    db: AsyncSession,
    business_id: uuid.UUID,
    catalog_item_id: uuid.UUID,
    name: str,
    exclude_id: uuid.UUID | None = None,
) -> bool:
    q = select(CatalogVariant.id).where(
        CatalogVariant.business_id == business_id,
        CatalogVariant.catalog_item_id == catalog_item_id,
        func.lower(CatalogVariant.name) == _norm_name(name),
    )
    if exclude_id is not None:
        q = q.where(CatalogVariant.id != exclude_id)
    r = await db.execute(q)
    return r.first() is not None


@router.get("/item-categories", response_model=list[ItemCategoryOut])
async def list_item_categories(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    del _m
    r = await db.execute(
        select(ItemCategory)
        .where(ItemCategory.business_id == business_id)
        .order_by(func.lower(ItemCategory.name))
    )
    rows = r.scalars().all()
    return [ItemCategoryOut(id=c.id, name=c.name) for c in rows]


@router.get("/category-types-index", response_model=list[CategoryTypeIndexOut])
async def list_category_types_index(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """All subcategory (type) rows for the business with category name for disambiguation."""
    del _m
    r = await db.execute(
        select(
            CategoryType.id,
            CategoryType.category_id,
            ItemCategory.name,
            CategoryType.name,
        )
        .join(ItemCategory, ItemCategory.id == CategoryType.category_id)
        .where(ItemCategory.business_id == business_id)
        .order_by(func.lower(ItemCategory.name), func.lower(CategoryType.name))
    )
    return [
        CategoryTypeIndexOut(
            id=row[0],
            category_id=row[1],
            category_name=row[2],
            name=row[3],
        )
        for row in r.all()
    ]


@router.post("/item-categories", response_model=ItemCategoryOut, status_code=status.HTTP_201_CREATED)
async def create_item_category(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    body: ItemCategoryCreate,
):
    del _m
    if await _category_dup(db, business_id, body.name):
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            detail="A category with this name already exists",
        )
    c = ItemCategory(business_id=business_id, name=body.name.strip())
    db.add(c)
    await db.flush()
    db.add(CategoryType(category_id=c.id, name=GENERAL_TYPE_NAME))
    await db.commit()
    await db.refresh(c)
    return ItemCategoryOut(id=c.id, name=c.name)


@router.get("/item-categories/{category_id}", response_model=ItemCategoryOut)
async def get_item_category(
    business_id: uuid.UUID,
    category_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    del _m
    r = await db.execute(
        select(ItemCategory).where(
            ItemCategory.id == category_id,
            ItemCategory.business_id == business_id,
        )
    )
    c = r.scalar_one_or_none()
    if c is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Category not found")
    return ItemCategoryOut(id=c.id, name=c.name)


@router.get(
    "/item-categories/{category_id}/trade-summary",
    response_model=CategoryTradeSummaryOut,
)
async def category_trade_summary(
    business_id: uuid.UUID,
    category_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """Per-item and category totals from confirmed trade lines (mobile dashboard)."""
    del _m
    cr = await db.execute(
        select(ItemCategory.id).where(
            ItemCategory.id == category_id,
            ItemCategory.business_id == business_id,
        )
    )
    if cr.scalar_one_or_none() is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Category not found")

    in_confirmed = and_(
        TradePurchase.id.isnot(None),
        func.coalesce(func.lower(TradePurchase.status), "") == "confirmed",
    )
    bag_unit = func.lower(TradePurchaseLine.unit).in_(("bag", "sack", "box"))
    stmt = (
        select(
            CatalogItem.id,
            CatalogItem.name,
            func.coalesce(
                func.sum(case((in_confirmed, TradePurchaseLine.line_total), else_=0)),
                0,
            ).label("period_line_total"),
            func.coalesce(
                func.sum(
                    case(
                        (and_(in_confirmed, bag_unit), TradePurchaseLine.qty),
                        else_=0,
                    )
                ),
                0,
            ).label("period_qty_bags"),
            func.coalesce(
                func.sum(case((in_confirmed, TradePurchaseLine.total_weight), else_=0)),
                0,
            ).label("period_weight_kg"),
            CatalogItem.last_purchase_price,
            CatalogItem.last_selling_rate,
            CatalogItem.last_supplier_id,
            CatalogItem.last_broker_id,
            func.max(
                case(
                    (TradePurchase.id == CatalogItem.last_trade_purchase_id, TradePurchase.human_id),
                    else_=None,
                )
            ).label("last_trade_human_id"),
        )
        .select_from(CatalogItem)
        .outerjoin(TradePurchaseLine, TradePurchaseLine.catalog_item_id == CatalogItem.id)
        .outerjoin(
            TradePurchase,
            and_(
                TradePurchase.id == TradePurchaseLine.trade_purchase_id,
                TradePurchase.business_id == business_id,
            ),
        )
        .where(
            CatalogItem.business_id == business_id,
            CatalogItem.category_id == category_id,
        )
        .group_by(
            CatalogItem.id,
            CatalogItem.name,
            CatalogItem.last_purchase_price,
            CatalogItem.last_selling_rate,
            CatalogItem.last_supplier_id,
            CatalogItem.last_broker_id,
            CatalogItem.last_trade_purchase_id,
        )
        .order_by(func.lower(CatalogItem.name))
    )
    r = await execute_with_retry(lambda: db.execute(stmt))
    rows = r.all()
    s_ids: set[uuid.UUID] = {row[7] for row in rows if row[7] is not None}
    b_ids: set[uuid.UUID] = {row[8] for row in rows if row[8] is not None}
    lsn_map, lbn_map = await _supplier_broker_name_maps_by_ids(db, business_id, s_ids, b_ids)
    items_out: list[CategoryTradeItemRow] = []
    tot_amt = 0.0
    tot_bags = 0.0
    tot_kg = 0.0
    for row in rows:
        iid = row[0]
        nm = row[1]
        pamt = row[2]
        pbags = row[3]
        pkg = row[4]
        lpp = row[5]
        lsr = row[6]
        lsid = row[7]
        lbid = row[8]
        ltp_human = row[9]
        fa = float(pamt or 0)
        fb = float(pbags or 0)
        fk = float(pkg or 0)
        tot_amt += fa
        tot_bags += fb
        tot_kg += fk
        items_out.append(
            CategoryTradeItemRow(
                catalog_item_id=iid,
                name=nm,
                period_line_total=fa,
                period_qty_bags=fb,
                period_weight_kg=fk,
                last_purchase_price=float(lpp) if lpp is not None else None,
                last_selling_rate=float(lsr) if lsr is not None else None,
                last_supplier_name=lsn_map.get(lsid) if lsid else None,
                last_broker_name=lbn_map.get(lbid) if lbid else None,
                last_trade_human_id=str(ltp_human).strip() if ltp_human else None,
            )
        )
    return CategoryTradeSummaryOut(
        item_count=len(items_out),
        total_line_amount=tot_amt,
        total_qty_bags=tot_bags,
        total_weight_kg=tot_kg,
        items=items_out,
    )


@router.patch("/item-categories/{category_id}", response_model=ItemCategoryOut)
async def update_item_category(
    business_id: uuid.UUID,
    category_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    body: ItemCategoryUpdate,
):
    del _m
    r = await db.execute(
        select(ItemCategory).where(
            ItemCategory.id == category_id,
            ItemCategory.business_id == business_id,
        )
    )
    c = r.scalar_one_or_none()
    if c is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Category not found")
    data = body.model_dump(exclude_unset=True)
    if "name" in data and data["name"] is not None:
        if await _category_dup(db, business_id, data["name"], exclude_id=category_id):
            raise HTTPException(
                status.HTTP_409_CONFLICT,
                detail="A category with this name already exists",
            )
        c.name = data["name"].strip()
    await db.commit()
    await db.refresh(c)
    return ItemCategoryOut(id=c.id, name=c.name)


@router.delete("/item-categories/{category_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_item_category(
    business_id: uuid.UUID,
    category_id: uuid.UUID,
    _owner: Annotated[Membership, Depends(require_owner_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    del _owner
    r = await db.execute(
        select(ItemCategory).where(
            ItemCategory.id == category_id,
            ItemCategory.business_id == business_id,
        )
    )
    c = r.scalar_one_or_none()
    if c is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Category not found")
    ic = await db.execute(
        select(func.count(CatalogItem.id)).where(CatalogItem.category_id == category_id)
    )
    if int(ic.scalar() or 0) > 0:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            detail="Cannot delete a category that still has catalog items — delete or move items first",
        )
    await db.delete(c)
    await db.commit()


# --- Category types (Category → Type → item) ---


@router.get(
    "/item-categories/{category_id}/category-types",
    response_model=list[CategoryTypeOut],
)
async def list_category_types(
    business_id: uuid.UUID,
    category_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    del _m
    cr = await db.execute(
        select(ItemCategory.id).where(
            ItemCategory.id == category_id,
            ItemCategory.business_id == business_id,
        )
    )
    if cr.first() is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Category not found")
    r = await db.execute(
        select(CategoryType)
        .where(CategoryType.category_id == category_id)
        .order_by(func.lower(CategoryType.name))
    )
    rows = r.scalars().all()
    return [CategoryTypeOut(id=t.id, category_id=t.category_id, name=t.name) for t in rows]


@router.post(
    "/item-categories/{category_id}/category-types",
    response_model=CategoryTypeOut,
    status_code=status.HTTP_201_CREATED,
)
async def create_category_type(
    business_id: uuid.UUID,
    category_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    body: CategoryTypeCreate,
):
    del _m
    cr = await db.execute(
        select(ItemCategory.id).where(
            ItemCategory.id == category_id,
            ItemCategory.business_id == business_id,
        )
    )
    if cr.first() is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Category not found")
    if await _type_name_dup(db, category_id, body.name):
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            detail="A type with this name already exists in this category",
        )
    t = CategoryType(category_id=category_id, name=body.name.strip())
    db.add(t)
    await db.commit()
    await db.refresh(t)
    return CategoryTypeOut(id=t.id, category_id=t.category_id, name=t.name)


@router.patch(
    "/item-categories/{category_id}/category-types/{type_id}",
    response_model=CategoryTypeOut,
)
async def update_category_type(
    business_id: uuid.UUID,
    category_id: uuid.UUID,
    type_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    body: CategoryTypeUpdate,
):
    del _m
    r = await db.execute(
        select(CategoryType)
        .join(ItemCategory, ItemCategory.id == CategoryType.category_id)
        .where(
            CategoryType.id == type_id,
            CategoryType.category_id == category_id,
            ItemCategory.business_id == business_id,
        )
    )
    t = r.scalar_one_or_none()
    if t is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Type not found")
    data = body.model_dump(exclude_unset=True)
    if "name" in data and data["name"] is not None:
        if await _type_name_dup(db, category_id, data["name"], exclude_id=type_id):
            raise HTTPException(
                status.HTTP_409_CONFLICT,
                detail="A type with this name already exists in this category",
            )
        t.name = data["name"].strip()
    await db.commit()
    await db.refresh(t)
    return CategoryTypeOut(id=t.id, category_id=t.category_id, name=t.name)


@router.delete(
    "/item-categories/{category_id}/category-types/{type_id}",
    status_code=status.HTTP_204_NO_CONTENT,
)
async def delete_category_type(
    business_id: uuid.UUID,
    category_id: uuid.UUID,
    type_id: uuid.UUID,
    _owner: Annotated[Membership, Depends(require_owner_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    del _owner
    r = await db.execute(
        select(CategoryType)
        .join(ItemCategory, ItemCategory.id == CategoryType.category_id)
        .where(
            CategoryType.id == type_id,
            CategoryType.category_id == category_id,
            ItemCategory.business_id == business_id,
        )
    )
    t = r.scalar_one_or_none()
    if t is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Type not found")
    if await catalog_items_has_type_id_column(db):
        ic = await db.execute(
            select(func.count(CatalogItem.id)).where(CatalogItem.type_id == type_id)
        )
        if int(ic.scalar() or 0) > 0:
            raise HTTPException(
                status.HTTP_400_BAD_REQUEST,
                detail="Cannot delete a type that still has catalog items — move or delete items first",
            )
    await db.delete(t)
    await db.commit()


@router.get("/catalog/duplicate-clusters")
async def catalog_duplicate_clusters(
    business_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_owner_membership)],
    min_score: float = Query(0.85, ge=0.5, le=1.0),
):
    """Similar catalog item name pairs for owner duplicate review."""
    from rapidfuzz import fuzz

    r = await db.execute(
        select(CatalogItem.id, CatalogItem.name).where(
            CatalogItem.business_id == business_id,
            CatalogItem.deleted_at.is_(None),
        )
    )
    rows = [(i, str(n).strip()) for i, n in r.all() if n and str(n).strip()]
    pairs: list[DuplicatePairOut] = []
    cutoff = int(min_score * 100)
    for i in range(len(rows)):
        id_a, name_a = rows[i]
        for j in range(i + 1, len(rows)):
            id_b, name_b = rows[j]
            sc = int(fuzz.token_sort_ratio(name_a.lower(), name_b.lower()))
            if sc >= cutoff:
                pairs.append(
                    DuplicatePairOut(
                        id_a=id_a,
                        name_a=name_a,
                        id_b=id_b,
                        name_b=name_b,
                        score=round(sc / 100.0, 4),
                    )
                )
    pairs.sort(key=lambda p: p.score, reverse=True)
    return {"pairs": pairs[:80]}


@router.post("/catalog/items/bulk-archive", status_code=status.HTTP_204_NO_CONTENT)
async def bulk_archive_catalog_items(
    business_id: uuid.UUID,
    body: BulkItemIdsIn,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_owner_membership)],
):
    from datetime import datetime, timezone

    now = datetime.now(timezone.utc)
    r = await db.execute(
        select(CatalogItem).where(
            CatalogItem.business_id == business_id,
            CatalogItem.id.in_(body.item_ids),
            CatalogItem.deleted_at.is_(None),
        )
    )
    for item in r.scalars().all():
        item.deleted_at = now
    await db.commit()


@router.patch("/catalog/items/bulk-reorder")
async def bulk_reorder_catalog_items(
    business_id: uuid.UUID,
    body: BulkReorderIn,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_owner_membership)],
):
    from decimal import Decimal as D

    r = await db.execute(
        select(CatalogItem).where(
            CatalogItem.business_id == business_id,
            CatalogItem.id.in_(body.item_ids),
            CatalogItem.deleted_at.is_(None),
        )
    )
    updated = 0
    for item in r.scalars().all():
        item.reorder_level = D(str(body.reorder_level))
        updated += 1
    await db.commit()
    return {"updated": updated}


@router.get("/catalog/fuzzy-check", response_model=CatalogFuzzyCheckOut)
async def catalog_fuzzy_check(
    business_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
    name: Annotated[str, Query(min_length=1, max_length=512)],
    supplier_id: Annotated[uuid.UUID | None, Query()] = None,
    category_id: Annotated[uuid.UUID | None, Query()] = None,
    type_id: Annotated[uuid.UUID | None, Query()] = None,
):
    """Debounced duplicate hints for catalog item create UIs (token-sort fuzzy)."""
    del _m
    stmt = select(CatalogItem.id, CatalogItem.name).where(
        CatalogItem.business_id == business_id,
        CatalogItem.deleted_at.is_(None),
    )
    if category_id is not None:
        stmt = stmt.where(CatalogItem.category_id == category_id)
    if type_id is not None:
        stmt = stmt.where(CatalogItem.type_id == type_id)
    if supplier_id is not None:
        stmt = stmt.where(
            exists(
                select(1).where(
                    CatalogItemDefaultSupplier.catalog_item_id == CatalogItem.id,
                    CatalogItemDefaultSupplier.supplier_id == supplier_id,
                )
            )
        )
    r = await db.execute(stmt)
    pairs: list[tuple[uuid.UUID, str]] = []
    for iid, nm in r.all():
        if nm and str(nm).strip():
            pairs.append((iid, str(nm).strip()))
    ranked = rank_ids_by_token_sort(name.strip(), pairs, limit=12, score_cutoff=55)
    id_to_name = dict(pairs)
    hits: list[CatalogFuzzyCheckHitOut] = []
    for uid, sc in ranked:
        nm = id_to_name.get(uid)
        if nm is None:
            continue
        hits.append(CatalogFuzzyCheckHitOut(id=uid, name=nm, score=round(sc / 100.0, 4)))
    return CatalogFuzzyCheckOut(hits=hits)


@router.get("/catalog-items", response_model=list[CatalogItemOut])
async def list_catalog_items(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    category_id: uuid.UUID | None = Query(None, description="Filter by category"),
    type_id: uuid.UUID | None = Query(None, description="Filter by category type"),
):

    async def _read() -> list[CatalogItemOut]:
        has_type_col = await catalog_items_has_type_id_column(db)
        if has_type_col:
            q = (
                select(CatalogItem, CategoryType.name, ItemCategory.name)
                .join(ItemCategory, ItemCategory.id == CatalogItem.category_id)
                .outerjoin(CategoryType, CategoryType.id == CatalogItem.type_id)
                .where(CatalogItem.business_id == business_id)
            )
            if category_id is not None:
                q = q.where(CatalogItem.category_id == category_id)
            if type_id is not None:
                q = q.where(CatalogItem.type_id == type_id)
            q = q.order_by(func.lower(CatalogItem.name))
            r = await db.execute(q)
            rows = r.all()
            ids = [i.id for i, _, _ in rows]
            sup_m, br_m = await _default_supplier_broker_ids_for_items(db, business_id, ids)
            items_only = [i for i, _, _ in rows]
            lsn, lbn = await _last_party_names_for_catalog_items(db, business_id, items_only)
            date_map = await _max_purchase_dates_for_catalog_items_bulk(db, business_id, ids)
            tp_ids = _dedupe_preserve_order(
                [x for x in (it.last_trade_purchase_id for it in items_only) if x is not None]
            )
            del_map = await _is_delivered_for_trade_purchase_ids(db, business_id, tp_ids)
            return [
                _catalog_item_out(
                    i,
                    tn,
                    default_supplier_ids=sup_m.get(i.id, []),
                    default_broker_ids=br_m.get(i.id, []),
                    last_supplier_name=lsn.get(i.last_supplier_id) if i.last_supplier_id else None,
                    last_broker_name=lbn.get(i.last_broker_id) if i.last_broker_id else None,
                    category_name=str(cat_n) if cat_n else None,
                    last_purchase_date=date_map.get(i.id),
                    last_purchase_delivered=del_map.get(i.last_trade_purchase_id)
                    if i.last_trade_purchase_id
                    else None,
                )
                for i, tn, cat_n in rows
            ]

        q = (
            select(CatalogItem, ItemCategory.name)
            .join(ItemCategory, ItemCategory.id == CatalogItem.category_id)
            .where(CatalogItem.business_id == business_id)
        )
        if category_id is not None:
            q = q.where(CatalogItem.category_id == category_id)
        q = q.order_by(func.lower(CatalogItem.name))
        r = await db.execute(q)
        rows = r.all()
        ids = [i.id for i, _ in rows]
        sup_m, br_m = await _default_supplier_broker_ids_for_items(db, business_id, ids)
        items_only = [i for i, _ in rows]
        lsn, lbn = await _last_party_names_for_catalog_items(db, business_id, items_only)
        date_map = await _max_purchase_dates_for_catalog_items_bulk(db, business_id, ids)
        tp_ids = _dedupe_preserve_order(
            [x for x in (it.last_trade_purchase_id for it in items_only) if x is not None]
        )
        del_map = await _is_delivered_for_trade_purchase_ids(db, business_id, tp_ids)
        return [
            _catalog_item_out(
                i,
                None,
                type_id=None,
                default_supplier_ids=sup_m.get(i.id, []),
                default_broker_ids=br_m.get(i.id, []),
                last_supplier_name=lsn.get(i.last_supplier_id) if i.last_supplier_id else None,
                last_broker_name=lbn.get(i.last_broker_id) if i.last_broker_id else None,
                category_name=str(cat_n) if cat_n else None,
                last_purchase_date=date_map.get(i.id),
                last_purchase_delivered=del_map.get(i.last_trade_purchase_id)
                if i.last_trade_purchase_id
                else None,
            )
            for i, cat_n in rows
        ]

    t0 = time.perf_counter()
    try:
        out = await execute_with_retry(_read)
    except SQLAlchemyError:
        logger.exception(
            "list_catalog_items failed business_id=%s category_id=%s type_id=%s",
            business_id,
            category_id,
            type_id,
        )
        raise
    ms = int((time.perf_counter() - t0) * 1000)
    logger.info(
        "list_catalog_items ok business_id=%s count=%s ms=%s category_id=%s type_id=%s",
        business_id,
        len(out),
        ms,
        category_id,
        type_id,
    )
    if should_redact_financials(_m.role):
        return [_maybe_redact_catalog_out(x, _m.role) for x in out]
    return out


_ITM_CODE_RE = re.compile(r"^ITM-(\d+)$", re.IGNORECASE)
_ITEM_CODE_SLUG_RE = re.compile(r"^[A-Z0-9_-]+$")


def _normalize_item_code(raw: str) -> str:
    return re.sub(r"\s+", "", raw.strip().upper())


def _normalize_barcode(raw: str) -> str:
    return raw.strip()


async def _assert_unique_barcode(
    db: AsyncSession,
    business_id: uuid.UUID,
    barcode: str,
    *,
    exclude_id: uuid.UUID | None = None,
) -> None:
    stmt = select(CatalogItem.id).where(
        CatalogItem.business_id == business_id,
        CatalogItem.barcode == barcode,
        CatalogItem.deleted_at.is_(None),
    )
    if exclude_id is not None:
        stmt = stmt.where(CatalogItem.id != exclude_id)
    if (await db.execute(stmt)).first() is not None:
        raise HTTPException(status.HTTP_409_CONFLICT, detail="Barcode already exists")


async def _assert_unique_item_code(
    db: AsyncSession,
    business_id: uuid.UUID,
    item_code: str,
    *,
    exclude_id: uuid.UUID | None = None,
) -> None:
    stmt = select(CatalogItem.id).where(
        CatalogItem.business_id == business_id,
        func.upper(CatalogItem.item_code) == item_code,
        CatalogItem.deleted_at.is_(None),
    )
    if exclude_id is not None:
        stmt = stmt.where(CatalogItem.id != exclude_id)
    if (await db.execute(stmt)).first() is not None:
        raise HTTPException(status.HTTP_409_CONFLICT, detail="Item code already exists")


class CatalogItemFromScanIn(BaseModel):
    """Minimal create after unknown barcode scan — no auto ITM, no supplier."""

    barcode: str = Field(min_length=1, max_length=64)
    item_code: str = Field(min_length=1, max_length=64)
    name: str = Field(min_length=1, max_length=512)
    type_id: uuid.UUID
    default_unit: str = Field(pattern=_UNIT_PATTERN)
    default_kg_per_bag: float | None = Field(default=None, gt=0)

    @field_validator("name", mode="before")
    @classmethod
    def _strip_name(cls, v: object) -> object:
        if isinstance(v, str):
            return v.strip()
        return v

    @field_validator("item_code", mode="after")
    @classmethod
    def _validate_item_code(cls, v: str) -> str:
        n = _normalize_item_code(v)
        if not _ITEM_CODE_SLUG_RE.match(n):
            raise ValueError("Item code: use A-Z, 0-9, hyphen, underscore only")
        return n

    @field_validator("barcode", mode="after")
    @classmethod
    def _validate_barcode(cls, v: str) -> str:
        b = _normalize_barcode(v)
        if not b:
            raise ValueError("Barcode is required")
        return b

    @model_validator(mode="after")
    def _unit_conditional_scan(self) -> "CatalogItemFromScanIn":
        if self.default_unit == "bag" and self.default_kg_per_bag is None:
            raise ValueError("default_kg_per_bag is required when default_unit is bag")
        return self


class ItemCodePatchIn(BaseModel):
    item_code: str = Field(min_length=1, max_length=64)

    @field_validator("item_code", mode="after")
    @classmethod
    def _validate(cls, v: str) -> str:
        n = _normalize_item_code(v)
        if not _ITEM_CODE_SLUG_RE.match(n):
            raise ValueError("Item code: use A-Z, 0-9, hyphen, underscore only")
        return n


class BarcodePatchIn(BaseModel):
    barcode: str = Field(min_length=1, max_length=64)

    @field_validator("barcode", mode="after")
    @classmethod
    def _validate(cls, v: str) -> str:
        b = _normalize_barcode(v)
        if not b:
            raise ValueError("Barcode is required")
        return b


async def _next_item_code(db: AsyncSession, business_id: uuid.UUID) -> str:
    """Next sequential ITM-#### for this business (SQLite + Postgres safe)."""
    result = await db.execute(
        select(CatalogItem.item_code).where(
            CatalogItem.business_id == business_id,
            CatalogItem.item_code.isnot(None),
            CatalogItem.item_code.like("ITM-%"),
        )
    )
    max_n = 0
    for (code,) in result.all():
        raw = (code or "").strip()
        m = _ITM_CODE_RE.match(raw)
        if m:
            max_n = max(max_n, int(m.group(1)))
    return f"ITM-{max_n + 1:04d}"


@router.post(
    "/catalog-items/from-scan",
    response_model=CatalogItemOut,
    status_code=status.HTTP_201_CREATED,
)
async def create_catalog_item_from_scan(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    body: CatalogItemFromScanIn,
):
    del _m
    has_type_col = await catalog_items_has_type_id_column(db)
    tr = await db.execute(
        select(CategoryType.id, CategoryType.category_id)
        .join(ItemCategory, ItemCategory.id == CategoryType.category_id)
        .where(
            CategoryType.id == body.type_id,
            ItemCategory.business_id == business_id,
        )
    )
    row = tr.first()
    if row is None:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="type_id not found in this business")
    type_uuid, category_id = row[0], row[1]
    await _assert_unique_barcode(db, business_id, body.barcode)
    await _assert_unique_item_code(db, business_id, body.item_code)
    if await _item_dup(
        db, business_id, category_id, type_uuid, body.name, has_type_col=has_type_col
    ):
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            detail="An item with this name already exists for this subcategory",
        )
    u = body.default_unit
    dkg = body.default_kg_per_bag if u == "bag" else None
    i = CatalogItem(
        business_id=business_id,
        category_id=category_id,
        type_id=type_uuid,
        name=body.name.strip(),
        default_unit=u,
        default_kg_per_bag=dkg,
        barcode=body.barcode,
        item_code=body.item_code,
    )
    db.add(i)
    await db.flush()
    crn = await db.execute(
        select(ItemCategory.name).where(
            ItemCategory.id == category_id,
            ItemCategory.business_id == business_id,
        )
    )
    cat_n = crn.scalar_one_or_none()
    ur = resolve_for_catalog_item(
        i,
        item_name=i.name,
        category_name=str(cat_n) if cat_n else None,
        brand_detected=False,
    )
    merge_unit_resolution_into_catalog_row(i, ur)
    await db.commit()
    await db.refresh(i)
    tn = None
    if i.type_id is not None:
        trn = await db.execute(select(CategoryType.name).where(CategoryType.id == i.type_id))
        tn = trn.scalar_one_or_none()
    return _catalog_item_out(i, tn, category_name=str(cat_n) if cat_n else None)


@router.patch("/catalog-items/{item_id}/item-code", response_model=CatalogItemOut)
async def patch_catalog_item_code(
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    body: ItemCodePatchIn,
):
    del _m
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
    await _assert_unique_item_code(db, business_id, body.item_code, exclude_id=item_id)
    item.item_code = body.item_code
    await db.commit()
    await db.refresh(item)
    tn = None
    if item.type_id:
        tr = await db.execute(select(CategoryType.name).where(CategoryType.id == item.type_id))
        tn = tr.scalar_one_or_none()
    return _catalog_item_out(item, tn)


@router.patch("/catalog-items/{item_id}/barcode", response_model=CatalogItemOut)
async def patch_catalog_item_barcode(
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_permission("stock_edit"))],
    db: Annotated[AsyncSession, Depends(get_db)],
    body: BarcodePatchIn,
):
    del _m
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
    await _assert_unique_barcode(db, business_id, body.barcode, exclude_id=item_id)
    item.barcode = body.barcode
    await db.commit()
    await db.refresh(item)
    tn = None
    if item.type_id:
        tr = await db.execute(select(CategoryType.name).where(CategoryType.id == item.type_id))
        tn = tr.scalar_one_or_none()
    return _catalog_item_out(item, tn)


@router.post("/catalog-items", response_model=CatalogItemOut, status_code=status.HTTP_201_CREATED)
async def create_catalog_item(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    body: CatalogItemCreate,
):
    del _m
    has_type_col = await catalog_items_has_type_id_column(db)
    rc = await db.execute(
        select(ItemCategory.id).where(
            ItemCategory.id == body.category_id,
            ItemCategory.business_id == business_id,
        )
    )
    if rc.first() is None:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="category_id not found in this business")
    resolved_type: uuid.UUID
    if body.type_id is not None:
        await _verify_type_in_category(db, business_id, body.category_id, body.type_id)
        resolved_type = body.type_id
    else:
        resolved_type = await _get_or_create_general_type_id(db, business_id, body.category_id)
    if await _item_dup(
        db, business_id, body.category_id, resolved_type, body.name, has_type_col=has_type_col
    ):
        dup_q = select(CatalogItem.id).where(
            CatalogItem.business_id == business_id,
            CatalogItem.category_id == body.category_id,
            func.lower(CatalogItem.name) == _norm_name(body.name),
        )
        if has_type_col:
            dup_q = dup_q.where(CatalogItem.type_id == resolved_type)
        er = await db.execute(dup_q)
        eid = er.scalar_one()
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            detail={
                "message": "An item with this name already exists for this category and type",
                "existing_item_id": str(eid),
            },
        )
    u = body.default_unit
    dkg = body.default_kg_per_bag if u in ("bag", "piece") else None
    dbox = body.default_items_per_box if u == "box" else None
    dwt = body.default_weight_per_tin if u == "tin" else None
    purchase_u = body.default_purchase_unit or body.default_unit
    supplier_ids = _dedupe_preserve_order(body.default_supplier_ids)
    broker_ids = _dedupe_preserve_order(list(body.default_broker_ids or ()))
    await _assert_supplier_ids_in_business(db, business_id, supplier_ids)
    await _assert_broker_ids_in_business(db, business_id, broker_ids)

    final_item_code = (body.item_code or "").strip() or None
    if final_item_code is None:
        final_item_code = await _next_item_code(db, business_id)

    i = CatalogItem(
        business_id=business_id,
        category_id=body.category_id,
        type_id=resolved_type,
        name=body.name.strip(),
        default_unit=body.default_unit,
        default_kg_per_bag=dkg,
        default_items_per_box=dbox,
        default_weight_per_tin=dwt,
        default_purchase_unit=purchase_u,
        default_sale_unit=body.default_sale_unit,
        hsn_code=(body.hsn_code or "").strip() or None,
        item_code=final_item_code,
        barcode=_normalize_barcode(body.barcode) if getattr(body, "barcode", None) else None,
        tax_percent=body.tax_percent,
        default_landing_cost=body.default_landing_cost,
        default_selling_cost=body.default_selling_cost,
    )
    normalized_pt = _normalize_package_type(body.package_type)
    if normalized_pt:
        i.package_type = normalized_pt
    if u == "piece" and dkg:
        from decimal import Decimal as _Dec

        i.package_type = "RETAIL_PACKET"
        i.package_size = _Dec(str(dkg))
        i.package_measurement = "KG"
        i.stock_unit = "PIECE"
        i.selling_unit = "PCS"
        i.validation_status = "unit_profile_verified"
    elif u == "bag" and dkg:
        from decimal import Decimal as _Dec

        i.package_type = "SACK"
        i.package_size = _Dec(str(dkg))
        i.package_measurement = "KG"
        i.stock_unit = "BAG"
        i.selling_unit = "BAG"
        i.validation_status = "unit_profile_verified"
    db.add(i)
    await db.flush()
    crn0 = await db.execute(
        select(ItemCategory.name).where(
            ItemCategory.id == i.category_id,
            ItemCategory.business_id == business_id,
        )
    )
    cat_n0 = crn0.scalar_one_or_none()
    parts0 = (i.name or "").split()
    brand_guess = len(parts0) >= 2 and parts0[0].isalpha() and len(parts0[0]) >= 2
    ur0 = resolve_for_catalog_item(
        i,
        item_name=i.name,
        category_name=str(cat_n0) if cat_n0 else None,
        brand_detected=brand_guess,
    )
    merge_unit_resolution_into_catalog_row(i, ur0)
    await db.flush()
    await _replace_default_supplier_rows(db, business_id, i.id, supplier_ids)
    await _replace_default_broker_rows(db, business_id, i.id, broker_ids)
    await _seed_supplier_item_defaults(db, business_id, i.id, supplier_ids)
    await db.commit()
    await db.refresh(i)
    tn = None
    if i.type_id is not None:
        tr = await db.execute(select(CategoryType.name).where(CategoryType.id == i.type_id))
        tn = tr.scalar_one_or_none()
    lsn, lbn = await _last_party_names_for_catalog_items(db, business_id, [i])
    crn = await db.execute(
        select(ItemCategory.name).where(
            ItemCategory.id == i.category_id,
            ItemCategory.business_id == business_id,
        )
    )
    cat_n = crn.scalar_one_or_none()
    lp = await _max_purchase_date_for_catalog_item(db, business_id, i.id)
    ld = await _last_purchase_delivered_for_snapshot(db, business_id, i.last_trade_purchase_id)
    return _catalog_item_out(
        i,
        tn,
        default_supplier_ids=supplier_ids,
        default_broker_ids=broker_ids,
        last_supplier_name=lsn.get(i.last_supplier_id) if i.last_supplier_id else None,
        last_broker_name=lbn.get(i.last_broker_id) if i.last_broker_id else None,
        category_name=str(cat_n) if cat_n else None,
        last_purchase_date=lp,
        last_purchase_delivered=ld,
    )


@router.post("/catalog-items/batch", response_model=CatalogBatchOut)
async def batch_create_catalog_items(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    body: CatalogBatchCreate,
):
    del _m
    has_type_col = await catalog_items_has_type_id_column(db)
    created_rows: list[CatalogItem] = []
    skipped = 0
    for line in body.items:
        tr = await db.execute(
            select(CategoryType.id, CategoryType.category_id)
            .join(ItemCategory, ItemCategory.id == CategoryType.category_id)
            .where(
                CategoryType.id == line.type_id,
                ItemCategory.business_id == business_id,
            )
        )
        row = tr.first()
        if row is None:
            skipped += 1
            continue
        type_uuid, category_id = row[0], row[1]
        try:
            await _verify_type_in_category(db, business_id, category_id, type_uuid)
        except HTTPException:
            skipped += 1
            continue
        if await _item_dup(
            db, business_id, category_id, type_uuid, line.name, has_type_col=has_type_col
        ):
            skipped += 1
            continue
        u = line.default_unit
        dkg = line.default_kg_per_bag if u == "bag" else None
        dbox = line.default_items_per_box if u == "box" else None
        dwt = line.default_weight_per_tin if u == "tin" else None
        purchase_u = line.default_unit
        supplier_ids = _dedupe_preserve_order(line.default_supplier_ids)
        broker_ids: list[uuid.UUID] = []
        try:
            await _assert_supplier_ids_in_business(db, business_id, supplier_ids)
            await _assert_broker_ids_in_business(db, business_id, broker_ids)
        except HTTPException:
            skipped += 1
            continue
        i = CatalogItem(
            business_id=business_id,
            category_id=category_id,
            type_id=type_uuid,
            name=line.name.strip(),
            default_unit=line.default_unit,
            default_kg_per_bag=dkg,
            default_items_per_box=dbox,
            default_weight_per_tin=dwt,
            default_purchase_unit=purchase_u,
            default_sale_unit=None,
            hsn_code=None,
            item_code=None,
            tax_percent=None,
            default_landing_cost=None,
            default_selling_cost=None,
        )
        normalized_pt = _normalize_package_type(line.package_type)
        if normalized_pt:
            i.package_type = normalized_pt
        db.add(i)
        await db.flush()
        crn0 = await db.execute(
            select(ItemCategory.name).where(
                ItemCategory.id == i.category_id,
                ItemCategory.business_id == business_id,
            )
        )
        cat_n0 = crn0.scalar_one_or_none()
        parts0 = (i.name or "").split()
        brand_guess = len(parts0) >= 2 and parts0[0].isalpha() and len(parts0[0]) >= 2
        ur0 = resolve_for_catalog_item(
            i,
            item_name=i.name,
            category_name=str(cat_n0) if cat_n0 else None,
            brand_detected=brand_guess,
        )
        merge_unit_resolution_into_catalog_row(i, ur0)
        await db.flush()
        await _replace_default_supplier_rows(db, business_id, i.id, supplier_ids)
        await _replace_default_broker_rows(db, business_id, i.id, broker_ids)
        await _seed_supplier_item_defaults(db, business_id, i.id, supplier_ids)
        created_rows.append(i)

    await db.commit()
    outs: list[CatalogItemOut] = []
    for i in created_rows:
        await db.refresh(i)
        tn = None
        if i.type_id is not None:
            tr = await db.execute(select(CategoryType.name).where(CategoryType.id == i.type_id))
            tn = tr.scalar_one_or_none()
        sup_m, br_m = await _default_supplier_broker_ids_for_items(db, business_id, [i.id])
        lsn, lbn = await _last_party_names_for_catalog_items(db, business_id, [i])
        crn = await db.execute(
            select(ItemCategory.name).where(
                ItemCategory.id == i.category_id,
                ItemCategory.business_id == business_id,
            )
        )
        cat_n = crn.scalar_one_or_none()
        lp = await _max_purchase_date_for_catalog_item(db, business_id, i.id)
        ld = await _last_purchase_delivered_for_snapshot(db, business_id, i.last_trade_purchase_id)
        outs.append(
            _catalog_item_out(
                i,
                tn,
                default_supplier_ids=sup_m.get(i.id, []),
                default_broker_ids=br_m.get(i.id, []),
                last_supplier_name=lsn.get(i.last_supplier_id) if i.last_supplier_id else None,
                last_broker_name=lbn.get(i.last_broker_id) if i.last_broker_id else None,
                category_name=str(cat_n) if cat_n else None,
                last_purchase_date=lp,
                last_purchase_delivered=ld,
            )
        )
    return CatalogBatchOut(created=len(outs), skipped=skipped, items=outs)


@router.get("/catalog-items/{item_id}", response_model=CatalogItemOut)
async def get_catalog_item(
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    try:
        has_type_col = await catalog_items_has_type_id_column(db)
        if has_type_col:
            r = await db.execute(
                select(CatalogItem, CategoryType.name, ItemCategory.name)
                .outerjoin(CategoryType, CategoryType.id == CatalogItem.type_id)
                .join(ItemCategory, ItemCategory.id == CatalogItem.category_id)
                .where(
                    CatalogItem.id == item_id,
                    CatalogItem.business_id == business_id,
                )
            )
            row = r.one_or_none()
            if row is None:
                raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Item not found")
            i, tn, cat_n = row
            sup_m, br_m = await _default_supplier_broker_ids_for_items(db, business_id, [i.id])
            lsn, lbn = await _last_party_names_for_catalog_items(db, business_id, [i])
            lp = await _max_purchase_date_for_catalog_item(db, business_id, i.id)
            ld = await _last_purchase_delivered_for_snapshot(db, business_id, i.last_trade_purchase_id)
            return _maybe_redact_catalog_out(
                _catalog_item_out(
                i,
                tn,
                default_supplier_ids=sup_m.get(i.id, []),
                default_broker_ids=br_m.get(i.id, []),
                last_supplier_name=lsn.get(i.last_supplier_id) if i.last_supplier_id else None,
                last_broker_name=lbn.get(i.last_broker_id) if i.last_broker_id else None,
                category_name=str(cat_n) if cat_n else None,
                last_purchase_date=lp,
                last_purchase_delivered=ld,
            ),
                _m.role,
            )

        r = await db.execute(
            select(CatalogItem)
            .options(load_only(*_CATALOG_ITEM_CORE))
            .where(
                CatalogItem.id == item_id,
                CatalogItem.business_id == business_id,
            )
        )
        i = r.scalar_one_or_none()
        if i is None:
            raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Item not found")
        crn = await db.execute(
            select(ItemCategory.name).where(
                ItemCategory.id == i.category_id,
                ItemCategory.business_id == business_id,
            )
        )
        cat_n = crn.scalar_one_or_none()
        sup_m, br_m = await _default_supplier_broker_ids_for_items(db, business_id, [i.id])
        lsn, lbn = await _last_party_names_for_catalog_items(db, business_id, [i])
        lp = await _max_purchase_date_for_catalog_item(db, business_id, i.id)
        ld = await _last_purchase_delivered_for_snapshot(db, business_id, i.last_trade_purchase_id)
        return _maybe_redact_catalog_out(
            _catalog_item_out(
            i,
            None,
            type_id=None,
            default_supplier_ids=sup_m.get(i.id, []),
            default_broker_ids=br_m.get(i.id, []),
            last_supplier_name=lsn.get(i.last_supplier_id) if i.last_supplier_id else None,
            last_broker_name=lbn.get(i.last_broker_id) if i.last_broker_id else None,
            category_name=str(cat_n) if cat_n else None,
            last_purchase_date=lp,
            last_purchase_delivered=ld,
        ),
            _m.role,
        )
    except SQLAlchemyError:
        logger.exception("get_catalog_item failed business_id=%s item_id=%s", business_id, item_id)
        raise


@router.post("/catalog-items/{item_id}/generate-code", response_model=CatalogItemOut)
async def generate_catalog_item_code(
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    r = await db.execute(
        select(CatalogItem).where(
            CatalogItem.id == item_id,
            CatalogItem.business_id == business_id,
        )
    )
    i = r.scalar_one_or_none()
    if i is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Item not found")
    existing = (i.item_code or "").strip()
    if existing:
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            detail={"message": "Item already has a code", "item_code": existing},
        )
    i.item_code = await _next_item_code(db, business_id)
    await db.commit()
    await db.refresh(i)
    tr = await db.execute(select(CategoryType.name).where(CategoryType.id == i.type_id))
    tn = tr.scalar_one_or_none()
    crn = await db.execute(
        select(ItemCategory.name).where(
            ItemCategory.id == i.category_id,
            ItemCategory.business_id == business_id,
        )
    )
    cat_n = crn.scalar_one_or_none()
    sup_m, br_m = await _default_supplier_broker_ids_for_items(db, business_id, [i.id])
    lsn, lbn = await _last_party_names_for_catalog_items(db, business_id, [i])
    lp = await _max_purchase_date_for_catalog_item(db, business_id, i.id)
    ld = await _last_purchase_delivered_for_snapshot(db, business_id, i.last_trade_purchase_id)
    return _maybe_redact_catalog_out(
        _catalog_item_out(
            i,
            tn,
            default_supplier_ids=sup_m.get(i.id, []),
            default_broker_ids=br_m.get(i.id, []),
            last_supplier_name=lsn.get(i.last_supplier_id) if i.last_supplier_id else None,
            last_broker_name=lbn.get(i.last_broker_id) if i.last_broker_id else None,
            category_name=str(cat_n) if cat_n else None,
            last_purchase_date=lp,
            last_purchase_delivered=ld,
        ),
        _m.role,
    )


@router.get(
    "/catalog-items/{item_id}/supplier-purchase-defaults",
    response_model=SupplierPurchaseDefaultsOut,
)
async def supplier_purchase_defaults(
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    supplier_id: uuid.UUID = Query(...),
):
    del _m
    ir = await db.execute(
        select(CatalogItem).where(CatalogItem.id == item_id, CatalogItem.business_id == business_id)
    )
    item = ir.scalar_one_or_none()
    if item is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Item not found")
    sr = await db.execute(
        select(Supplier.id).where(Supplier.id == supplier_id, Supplier.business_id == business_id)
    )
    if sr.first() is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Supplier not found")
    dr = await db.execute(
        select(SupplierItemDefault).where(
            SupplierItemDefault.business_id == business_id,
            SupplierItemDefault.supplier_id == supplier_id,
            SupplierItemDefault.catalog_item_id == item_id,
        )
    )
    d = dr.scalar_one_or_none()
    return SupplierPurchaseDefaultsOut(
        catalog_item_id=item.id,
        supplier_id=supplier_id,
        last_price=float(d.last_price) if d and d.last_price is not None else None,
        last_discount=float(d.last_discount) if d and d.last_discount is not None else None,
        last_payment_days=d.last_payment_days if d else None,
        purchase_count=int(d.purchase_count or 0) if d else 0,
        item_hsn_code=item.hsn_code,
        item_tax_percent=float(item.tax_percent) if item.tax_percent is not None else None,
        item_default_unit=item.default_unit,
        item_default_kg_per_bag=float(item.default_kg_per_bag) if item.default_kg_per_bag is not None else None,
        item_default_landing_cost=float(item.default_landing_cost)
        if item.default_landing_cost is not None
        else None,
        item_default_purchase_unit=item.default_purchase_unit or item.default_unit,
    )


@router.get(
    "/catalog-items/{item_id}/trade-supplier-prices",
    response_model=CatalogItemTradeSupplierPricesOut,
)
async def catalog_item_trade_supplier_prices(
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """Latest landed price per supplier from trade purchases; last five prices; trade-only average."""
    del _m
    ir = await db.execute(
        select(CatalogItem.id).where(CatalogItem.id == item_id, CatalogItem.business_id == business_id)
    )
    if ir.first() is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Item not found")

    line_amt = tq.trade_line_amount_expr()
    line_rows = (
        select(
            TradePurchase.id.label("tp_id"),
            TradePurchase.supplier_id,
            Supplier.name.label("supplier_name"),
            TradePurchaseLine.landing_cost,
            TradePurchaseLine.qty,
            TradePurchaseLine.unit,
            TradePurchase.purchase_date,
            TradePurchaseLine.id,
            line_amt.label("line_amt"),
        )
        .select_from(TradePurchaseLine)
        .join(TradePurchase, TradePurchaseLine.trade_purchase_id == TradePurchase.id)
        .join(Supplier, Supplier.id == TradePurchase.supplier_id)
        .where(
            TradePurchase.business_id == business_id,
            TradePurchaseLine.catalog_item_id == item_id,
            TradePurchase.supplier_id.isnot(None),
            tq.trade_purchase_status_in_reports(),
        )
        .order_by(desc(TradePurchase.purchase_date), desc(TradePurchaseLine.id))
    )
    lr = await db.execute(line_rows)
    all_rows = lr.mappings().all()

    seen_suppliers: set[uuid.UUID] = set()
    supplier_latest: list[tuple[uuid.UUID, str, float, str, date, uuid.UUID]] = []
    sum_amt: dict[uuid.UUID, float] = {}
    sum_qty: dict[uuid.UUID, float] = {}
    deals: dict[uuid.UUID, set[uuid.UUID]] = {}
    landing_for_avg: list[float] = []
    last_five_prices: list[float] = []

    for row in all_rows:
        sid = row["supplier_id"]
        sname = row["supplier_name"]
        lc = row["landing_cost"]
        qty = float(row["qty"] or 0)
        unit = row["unit"]
        pdate = row["purchase_date"]
        lid = row["id"]
        tp_id = row["tp_id"]
        la = float(row["line_amt"] or 0)
        lc_f = float(lc) if lc is not None else None
        if lc_f is None:
            continue
        sum_amt[sid] = sum_amt.get(sid, 0.0) + la
        sum_qty[sid] = sum_qty.get(sid, 0.0) + qty
        if sid not in deals:
            deals[sid] = set()
        deals[sid].add(tp_id)
        landing_for_avg.append(lc_f)
        if len(last_five_prices) < 5:
            last_five_prices.append(lc_f)
        if sid in seen_suppliers:
            continue
        seen_suppliers.add(sid)
        supplier_latest.append((sid, sname, lc_f, unit, pdate, lid))

    vwap: dict[uuid.UUID, float | None] = {}
    for sid in sum_amt:
        qn = sum_qty.get(sid, 0.0)
        vwap[sid] = (sum_amt[sid] / qn) if qn > 1e-12 else None

    best_supplier: uuid.UUID | None = None
    eligible = [
        sid
        for sid in sum_amt
        if len(deals.get(sid, ())) >= 2
        and vwap.get(sid) is not None
        and sum_qty.get(sid, 0) > 1e-12
    ]
    if eligible:
        best_supplier = min(
            eligible,
            key=lambda s: (vwap.get(s) if vwap.get(s) is not None else float("inf"), str(s)),
        )
    elif supplier_latest:
        best_supplier = min(supplier_latest, key=lambda r: (r[2], r[0]))[0]

    suppliers_out: list[TradeSupplierPriceRow] = []
    for sid, sname, lc_f, unit, pdate, _lid in sorted(
        supplier_latest, key=lambda r: (r[2], r[0].hex)
    ):
        ndeals = len(deals.get(sid, ()))
        vw = vwap.get(sid)
        is_b = best_supplier is not None and sid == best_supplier
        suppliers_out.append(
            TradeSupplierPriceRow(
                supplier_id=sid,
                supplier_name=sname,
                landing_cost=lc_f,
                unit=unit,
                last_purchase_date=pdate,
                is_best=is_b,
                deals=ndeals,
                volume_weighted_landing=vw,
            )
        )
    # Sort display: best first, then by price
    suppliers_out.sort(key=lambda s: (not s.is_best, s.landing_cost, s.supplier_name))

    avg_landing: float | None = None
    if landing_for_avg:
        avg_landing = sum(landing_for_avg) / len(landing_for_avg)

    return CatalogItemTradeSupplierPricesOut(
        catalog_item_id=item_id,
        suppliers=suppliers_out,
        last_five_landing_prices=last_five_prices,
        avg_landing_from_trade=avg_landing,
    )


@router.get("/catalog-items/{item_id}/insights", response_model=CatalogItemInsightsOut)
async def catalog_item_insights(
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    from_date: date = Query(..., alias="from"),
    to_date: date = Query(..., alias="to"),
):
    del _m
    ir = await db.execute(
        select(CatalogItem.id).where(CatalogItem.id == item_id, CatalogItem.business_id == business_id)
    )
    if ir.first() is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Item not found")
    bf = _trade_purchase_date_filter(business_id, from_date, to_date)
    profit_e = tq.trade_line_profit_expr()
    sell_e = func.coalesce(TradePurchaseLine.selling_rate, TradePurchaseLine.selling_cost)
    base = (
        select(
            func.count(TradePurchaseLine.id),
            func.count(func.distinct(TradePurchaseLine.trade_purchase_id)),
            func.coalesce(func.sum(profit_e), 0),
            func.avg(TradePurchaseLine.landing_cost),
            func.avg(sell_e),
            func.max(TradePurchase.purchase_date),
        )
        .select_from(TradePurchaseLine)
        .join(TradePurchase, TradePurchase.id == TradePurchaseLine.trade_purchase_id)
        .where(
            bf,
            TradePurchaseLine.catalog_item_id == item_id,
        )
    )
    r = await db.execute(base)
    row = r.one()
    line_count = int(row[0] or 0)
    entry_count = int(row[1] or 0)
    total_profit = float(row[2] or 0)
    avg_landing = float(row[3]) if row[3] is not None else None
    avg_selling = float(row[4]) if row[4] is not None else None
    last_entry_date = row[5]

    profit_margin_pct: float | None = None
    if line_count > 0:
        rev_r = await db.execute(
            select(
                func.coalesce(
                    func.sum(TradePurchaseLine.qty * sell_e),
                    0,
                )
            )
            .select_from(TradePurchaseLine)
            .join(TradePurchase, TradePurchase.id == TradePurchaseLine.trade_purchase_id)
            .where(
                bf,
                TradePurchaseLine.catalog_item_id == item_id,
                sell_e.isnot(None),
            )
        )
        total_rev = float(rev_r.scalar() or 0)
        if total_rev > 0:
            profit_margin_pct = (total_profit / total_rev) * 100.0

    return CatalogItemInsightsOut(
        line_count=line_count,
        entry_count=entry_count,
        total_profit=total_profit,
        avg_landing=avg_landing,
        avg_selling=avg_selling,
        last_entry_date=last_entry_date,
        profit_margin_pct=profit_margin_pct,
    )


@router.get("/catalog-items/{item_id}/lines", response_model=list[CatalogItemLineRow])
async def catalog_item_lines(
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    from_date: date = Query(..., alias="from"),
    to_date: date = Query(..., alias="to"),
    limit: int = Query(20, ge=1, le=50),
    offset: int = Query(0, ge=0),
):
    ir = await db.execute(
        select(CatalogItem.id).where(CatalogItem.id == item_id, CatalogItem.business_id == business_id)
    )
    if ir.first() is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Item not found")

    cap = min(500, max(limit + offset, 1) * 4 + 20)

    trade_bf = _trade_purchase_date_filter(business_id, from_date, to_date)
    profit_e = tq.trade_line_profit_expr()
    sell_disp = func.coalesce(TradePurchaseLine.selling_rate, TradePurchaseLine.selling_cost)
    trade_lines_q = (
        select(
            TradePurchaseLine.id,
            TradePurchase.purchase_date,
            TradePurchase.human_id,
            TradePurchaseLine.qty,
            TradePurchaseLine.unit,
            TradePurchaseLine.landing_cost,
            sell_disp,
            profit_e,
            TradePurchaseLine.kg_per_unit,
            TradePurchaseLine.landing_cost_per_kg,
            Supplier.name,
            Supplier.phone,
            Broker.name,
            Broker.phone,
            TradePurchaseLine.item_name,
        )
        .select_from(TradePurchaseLine)
        .join(TradePurchase, TradePurchaseLine.trade_purchase_id == TradePurchase.id)
        .outerjoin(Supplier, Supplier.id == TradePurchase.supplier_id)
        .outerjoin(Broker, Broker.id == TradePurchase.broker_id)
        .where(
            trade_bf,
            TradePurchaseLine.catalog_item_id == item_id,
        )
        .order_by(desc(TradePurchase.purchase_date), desc(TradePurchaseLine.id))
        .limit(cap)
    )
    tr = await db.execute(trade_lines_q)
    trade_rows: list[CatalogItemLineRow] = []
    for row in tr.all():
        (
            lid,
            pdate,
            human_id,
            qty,
            unit,
            lc,
            sell,
            line_profit,
            kpu,
            lcpk,
            sname,
            sphone,
            bname,
            bphone,
            iname,
        ) = row
        sell_f = float(sell) if sell is not None else None
        kpu_f = float(kpu) if kpu is not None else None
        lcpk_f = float(lcpk) if lcpk is not None else None
        trade_rows.append(
            CatalogItemLineRow(
                entry_id=lid,
                entry_date=pdate,
                qty=float(qty),
                unit=str(unit),
                landing_cost=float(lc),
                selling_price=sell_f,
                profit=float(line_profit) if line_profit is not None else None,
                supplier_name=str(sname) if sname else None,
                supplier_phone=str(sphone) if sphone else None,
                broker_name=str(bname) if bname else None,
                broker_phone=str(bphone) if bphone else None,
                purchase_human_id=str(human_id) if human_id else None,
                kg_per_unit=kpu_f,
                landing_cost_per_kg=lcpk_f,
                unit_resolution=resolve_from_text(str(iname or "")).as_dict(),
            )
        )

    trade_rows.sort(key=lambda r: (r.entry_date, r.entry_id), reverse=True)
    page = trade_rows[offset : offset + limit]
    if should_redact_financials(_m.role):
        return [redact_catalog_line_row_model(r) for r in page]
    return page


@router.get("/item-categories/{category_id}/insights", response_model=CategoryInsightsOut)
async def category_insights(
    business_id: uuid.UUID,
    category_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    from_date: date = Query(..., alias="from"),
    to_date: date = Query(..., alias="to"),
):
    del _m
    cr = await db.execute(
        select(ItemCategory.id).where(
            ItemCategory.id == category_id,
            ItemCategory.business_id == business_id,
        )
    )
    if cr.first() is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Category not found")

    ic = await db.execute(
        select(func.count(CatalogItem.id)).where(
            CatalogItem.business_id == business_id,
            CatalogItem.category_id == category_id,
        )
    )
    item_count = int(ic.scalar() or 0)

    bf = _trade_purchase_date_filter(business_id, from_date, to_date)
    profit_e = tq.trade_line_profit_expr()
    cat_item_ids = (
        select(CatalogItem.id)
        .where(
            CatalogItem.business_id == business_id,
            CatalogItem.category_id == category_id,
        )
        .scalar_subquery()
    )

    lc = await db.execute(
        select(func.count(TradePurchaseLine.id))
        .select_from(TradePurchaseLine)
        .join(TradePurchase, TradePurchase.id == TradePurchaseLine.trade_purchase_id)
        .where(
            bf,
            TradePurchaseLine.catalog_item_id.in_(cat_item_ids),
        )
    )
    linked_line_count = int(lc.scalar() or 0)

    tp = await db.execute(
        select(func.coalesce(func.sum(profit_e), 0))
        .select_from(TradePurchaseLine)
        .join(TradePurchase, TradePurchase.id == TradePurchaseLine.trade_purchase_id)
        .where(
            bf,
            TradePurchaseLine.catalog_item_id.in_(cat_item_ids),
        )
    )
    total_profit = float(tp.scalar() or 0)

    per_item = await db.execute(
        select(CatalogItem.id, CatalogItem.name, func.coalesce(func.sum(profit_e), 0))
        .select_from(CatalogItem)
        .join(
            TradePurchaseLine,
            and_(
                TradePurchaseLine.catalog_item_id == CatalogItem.id,
            ),
        )
        .join(TradePurchase, TradePurchase.id == TradePurchaseLine.trade_purchase_id)
        .where(
            bf,
            CatalogItem.category_id == category_id,
            CatalogItem.business_id == business_id,
        )
        .group_by(CatalogItem.id, CatalogItem.name)
    )
    agg = [(row[0], row[1], float(row[2] or 0)) for row in per_item.all()]
    top_name = top_profit = worst_name = worst_profit = None
    if agg:
        best = max(agg, key=lambda x: x[2])
        worst = min(agg, key=lambda x: x[2])
        top_name, top_profit = best[1], best[2]
        worst_name, worst_profit = worst[1], worst[2]

    return CategoryInsightsOut(
        item_count=item_count,
        linked_line_count=linked_line_count,
        total_profit=total_profit,
        top_item_name=top_name,
        top_item_profit=top_profit,
        worst_item_name=worst_name,
        worst_item_profit=worst_profit,
    )


@router.patch("/catalog-items/{item_id}", response_model=CatalogItemOut)
async def update_catalog_item(
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    body: CatalogItemUpdate,
):
    del _m
    has_type_col = await catalog_items_has_type_id_column(db)
    stmt = select(CatalogItem).where(
        CatalogItem.id == item_id,
        CatalogItem.business_id == business_id,
    )
    if not has_type_col:
        stmt = stmt.options(load_only(*_CATALOG_ITEM_CORE))
    r = await db.execute(stmt)
    i = r.scalar_one_or_none()
    if i is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Item not found")
    data = body.model_dump(exclude_unset=True)
    cid = i.category_id
    tid: uuid.UUID | None = i.type_id if has_type_col else None
    if "category_id" in data and data["category_id"] is not None:
        rc = await db.execute(
            select(ItemCategory.id).where(
                ItemCategory.id == data["category_id"],
                ItemCategory.business_id == business_id,
            )
        )
        if rc.first() is None:
            raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="category_id not found")
        i.category_id = data["category_id"]
        cid = i.category_id
        if has_type_col and "type_id" not in data:
            i.type_id = await _get_or_create_general_type_id(db, business_id, cid)
            tid = i.type_id
    if has_type_col and "type_id" in data:
        if data["type_id"] is None:
            i.type_id = await _get_or_create_general_type_id(db, business_id, cid)
        else:
            await _verify_type_in_category(db, business_id, cid, data["type_id"])
            i.type_id = data["type_id"]
        tid = i.type_id
    if "name" in data and data["name"] is not None:
        if await _item_dup(
            db, business_id, cid, tid, data["name"], exclude_id=item_id, has_type_col=has_type_col
        ):
            dup_q = select(CatalogItem.id).where(
                CatalogItem.business_id == business_id,
                CatalogItem.category_id == cid,
                func.lower(CatalogItem.name) == _norm_name(data["name"]),
                CatalogItem.id != item_id,
            )
            if has_type_col:
                dup_q = dup_q.where(CatalogItem.type_id == tid)
            er = await db.execute(dup_q)
            oid = er.scalar_one()
            raise HTTPException(
                status.HTTP_409_CONFLICT,
                detail={
                    "message": "An item with this name already exists for this category and type",
                    "existing_item_id": str(oid),
                },
            )
        i.name = data["name"].strip()
    if "default_unit" in data:
        i.default_unit = data["default_unit"]
        u = i.default_unit
        if u != "bag":
            i.default_kg_per_bag = None
        if u != "box":
            i.default_items_per_box = None
        if u != "tin":
            i.default_weight_per_tin = None
    if "default_kg_per_bag" in data:
        if i.default_unit == "bag":
            i.default_kg_per_bag = data["default_kg_per_bag"]
        else:
            i.default_kg_per_bag = None
    if "default_items_per_box" in data:
        if i.default_unit == "box":
            i.default_items_per_box = data["default_items_per_box"]
        else:
            i.default_items_per_box = None
    if "default_weight_per_tin" in data:
        if i.default_unit == "tin":
            i.default_weight_per_tin = data["default_weight_per_tin"]
        else:
            i.default_weight_per_tin = None
    if "default_purchase_unit" in data:
        i.default_purchase_unit = data["default_purchase_unit"]
    if "default_sale_unit" in data:
        i.default_sale_unit = data["default_sale_unit"]
    if "hsn_code" in data:
        i.hsn_code = data["hsn_code"].strip() if data["hsn_code"] else None
    if "item_code" in data:
        ic = data["item_code"]
        i.item_code = ic.strip() if ic else None
    if "tax_percent" in data:
        i.tax_percent = data["tax_percent"]
    if "default_landing_cost" in data:
        i.default_landing_cost = data["default_landing_cost"]
    if "default_selling_cost" in data:
        i.default_selling_cost = data["default_selling_cost"]
    if "reorder_level" in data:
        from decimal import Decimal as D

        rl = data["reorder_level"]
        i.reorder_level = D(str(rl)) if rl is not None else D("0")
    _sync_item_unit_extras(i)
    unit_touched = any(
        k in data
        for k in (
            "default_unit",
            "default_kg_per_bag",
            "default_items_per_box",
            "default_weight_per_tin",
        )
    )
    if unit_touched:
        _validate_item_unit_constraints(i)
    profile_keys = (
        "name",
        "category_id",
        "default_unit",
        "default_kg_per_bag",
        "default_items_per_box",
        "default_weight_per_tin",
    )
    if any(k in data for k in profile_keys):
        crnx = await db.execute(
            select(ItemCategory.name).where(
                ItemCategory.id == i.category_id,
                ItemCategory.business_id == business_id,
            )
        )
        cnx = crnx.scalar_one_or_none()
        partsx = (i.name or "").split()
        bg = len(partsx) >= 2 and partsx[0].isalpha() and len(partsx[0]) >= 2
        urx = resolve_for_catalog_item(
            i,
            item_name=i.name,
            category_name=str(cnx) if cnx else None,
            brand_detected=bg,
        )
        merge_unit_resolution_into_catalog_row(i, urx)
        if i.default_unit != "bag":
            i.default_kg_per_bag = None
        if i.default_unit != "box":
            i.default_items_per_box = None
        if i.default_unit != "tin":
            i.default_weight_per_tin = None
    if "default_supplier_ids" in data and data["default_supplier_ids"] is not None:
        sids = _dedupe_preserve_order(data["default_supplier_ids"])
        if not sids:
            raise HTTPException(
                status.HTTP_400_BAD_REQUEST,
                detail="At least one default_supplier_ids entry is required when updating defaults",
            )
        await _assert_supplier_ids_in_business(db, business_id, sids)
        await _replace_default_supplier_rows(db, business_id, item_id, sids)
        await _seed_supplier_item_defaults(db, business_id, item_id, sids)
    if "default_broker_ids" in data and data["default_broker_ids"] is not None:
        bids = _dedupe_preserve_order(data["default_broker_ids"] or [])
        await _assert_broker_ids_in_business(db, business_id, bids)
        await _replace_default_broker_rows(db, business_id, item_id, bids)
    await db.commit()
    if not has_type_col:
        rr = await db.execute(
            select(CatalogItem)
            .options(load_only(*_CATALOG_ITEM_CORE))
            .where(CatalogItem.id == item_id, CatalogItem.business_id == business_id)
        )
        i_out = rr.scalar_one()
        sup_m, br_m = await _default_supplier_broker_ids_for_items(db, business_id, [item_id])
        lsn, lbn = await _last_party_names_for_catalog_items(db, business_id, [i_out])
        crn = await db.execute(
            select(ItemCategory.name).where(
                ItemCategory.id == i_out.category_id,
                ItemCategory.business_id == business_id,
            )
        )
        cat_n = crn.scalar_one_or_none()
        lp = await _max_purchase_date_for_catalog_item(db, business_id, i_out.id)
        ld = await _last_purchase_delivered_for_snapshot(db, business_id, i_out.last_trade_purchase_id)
        return _catalog_item_out(
            i_out,
            None,
            type_id=None,
            default_supplier_ids=sup_m.get(item_id, []),
            default_broker_ids=br_m.get(item_id, []),
            last_supplier_name=lsn.get(i_out.last_supplier_id) if i_out.last_supplier_id else None,
            last_broker_name=lbn.get(i_out.last_broker_id) if i_out.last_broker_id else None,
            category_name=str(cat_n) if cat_n else None,
            last_purchase_date=lp,
            last_purchase_delivered=ld,
        )
    await db.refresh(i)
    tn = None
    if i.type_id is not None:
        tr = await db.execute(select(CategoryType.name).where(CategoryType.id == i.type_id))
        tn = tr.scalar_one_or_none()
    sup_m, br_m = await _default_supplier_broker_ids_for_items(db, business_id, [item_id])
    lsn, lbn = await _last_party_names_for_catalog_items(db, business_id, [i])
    crn = await db.execute(
        select(ItemCategory.name).where(
            ItemCategory.id == i.category_id,
            ItemCategory.business_id == business_id,
        )
    )
    cat_n = crn.scalar_one_or_none()
    lp = await _max_purchase_date_for_catalog_item(db, business_id, i.id)
    ld = await _last_purchase_delivered_for_snapshot(db, business_id, i.last_trade_purchase_id)
    return _catalog_item_out(
        i,
        tn,
        default_supplier_ids=sup_m.get(item_id, []),
        default_broker_ids=br_m.get(item_id, []),
        last_supplier_name=lsn.get(i.last_supplier_id) if i.last_supplier_id else None,
        last_broker_name=lbn.get(i.last_broker_id) if i.last_broker_id else None,
        category_name=str(cat_n) if cat_n else None,
        last_purchase_date=lp,
        last_purchase_delivered=ld,
    )


@router.delete("/catalog-items/{item_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_catalog_item(
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    _owner: Annotated[Membership, Depends(require_owner_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    del _owner
    has_type_col = await catalog_items_has_type_id_column(db)
    stmt = select(CatalogItem).where(
        CatalogItem.id == item_id,
        CatalogItem.business_id == business_id,
    )
    if not has_type_col:
        stmt = stmt.options(load_only(*_CATALOG_ITEM_CORE))
    r = await db.execute(stmt)
    i = r.scalar_one_or_none()
    if i is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Item not found")
    ec = await db.execute(
        select(func.count(TradePurchaseLine.id)).where(TradePurchaseLine.catalog_item_id == item_id)
    )
    if int(ec.scalar() or 0) > 0:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            detail="Cannot delete a catalog item that is linked to wholesale purchase lines",
        )
    vr = await db.execute(select(CatalogVariant.id).where(CatalogVariant.catalog_item_id == item_id))
    vids = [row[0] for row in vr.all()]
    if vids:
        ec2 = await db.execute(
            select(func.count(EntryLineItem.id)).where(EntryLineItem.catalog_variant_id.in_(vids))
        )
        if int(ec2.scalar() or 0) > 0:
            raise HTTPException(
                status.HTTP_400_BAD_REQUEST,
                detail="Cannot delete a catalog item whose variants are linked to legacy purchase entry lines",
            )
    await db.delete(i)
    await db.commit()


# --- Variants (Category → Item → Variant) ---


@router.get("/catalog-items/{item_id}/variants", response_model=list[CatalogVariantOut])
async def list_catalog_variants(
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    del _m
    r = await db.execute(
        select(CatalogVariant)
        .where(
            CatalogVariant.business_id == business_id,
            CatalogVariant.catalog_item_id == item_id,
        )
        .order_by(func.lower(CatalogVariant.name))
    )
    rows = r.scalars().all()
    return [
        CatalogVariantOut(
            id=v.id,
            catalog_item_id=v.catalog_item_id,
            name=v.name,
            default_kg_per_bag=float(v.default_kg_per_bag) if v.default_kg_per_bag is not None else None,
        )
        for v in rows
    ]


@router.post("/catalog-items/{item_id}/variants", response_model=CatalogVariantOut, status_code=status.HTTP_201_CREATED)
async def create_catalog_variant(
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    body: CatalogVariantCreate,
):
    del _m
    ir = await db.execute(
        select(CatalogItem.id).where(CatalogItem.id == item_id, CatalogItem.business_id == business_id)
    )
    if ir.first() is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Catalog item not found")
    if await _variant_dup(db, business_id, item_id, body.name):
        raise HTTPException(status.HTTP_409_CONFLICT, detail="A variant with this name already exists for this item")
    v = CatalogVariant(
        business_id=business_id,
        catalog_item_id=item_id,
        name=body.name.strip(),
        default_kg_per_bag=body.default_kg_per_bag,
    )
    db.add(v)
    await db.commit()
    await db.refresh(v)
    return CatalogVariantOut(
        id=v.id,
        catalog_item_id=v.catalog_item_id,
        name=v.name,
        default_kg_per_bag=float(v.default_kg_per_bag) if v.default_kg_per_bag is not None else None,
    )


@router.patch("/catalog-variants/{variant_id}", response_model=CatalogVariantOut)
async def update_catalog_variant(
    business_id: uuid.UUID,
    variant_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    body: CatalogVariantUpdate,
):
    del _m
    r = await db.execute(
        select(CatalogVariant).where(
            CatalogVariant.id == variant_id,
            CatalogVariant.business_id == business_id,
        )
    )
    v = r.scalar_one_or_none()
    if v is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Variant not found")
    data = body.model_dump(exclude_unset=True)
    if "name" in data and data["name"] is not None:
        if await _variant_dup(db, business_id, v.catalog_item_id, data["name"], exclude_id=variant_id):
            raise HTTPException(status.HTTP_409_CONFLICT, detail="A variant with this name already exists for this item")
        v.name = data["name"].strip()
    if "default_kg_per_bag" in data:
        v.default_kg_per_bag = data["default_kg_per_bag"]
    await db.commit()
    await db.refresh(v)
    return CatalogVariantOut(
        id=v.id,
        catalog_item_id=v.catalog_item_id,
        name=v.name,
        default_kg_per_bag=float(v.default_kg_per_bag) if v.default_kg_per_bag is not None else None,
    )


@router.delete("/catalog-variants/{variant_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_catalog_variant(
    business_id: uuid.UUID,
    variant_id: uuid.UUID,
    _owner: Annotated[Membership, Depends(require_owner_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    del _owner
    r = await db.execute(
        select(CatalogVariant).where(
            CatalogVariant.id == variant_id,
            CatalogVariant.business_id == business_id,
        )
    )
    v = r.scalar_one_or_none()
    if v is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Variant not found")
    ec = await db.execute(
        select(func.count(EntryLineItem.id)).where(EntryLineItem.catalog_variant_id == variant_id)
    )
    if int(ec.scalar() or 0) > 0:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            detail="Cannot delete a variant that is linked to purchase entry lines",
        )
    await db.delete(v)
    await db.commit()
