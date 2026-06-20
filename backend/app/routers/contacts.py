import logging
import re
import time
import uuid
from collections import defaultdict
from datetime import date
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field, field_validator
from sqlalchemy import delete, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import load_only

from app.database import get_db
from app.services.trade_query import trade_purchase_status_in_reports
from app.services import trade_query as tq
from app.db_resilience import execute_with_retry
from app.deps import require_membership, require_owner_membership
from app.models import (
    Broker,
    BrokerSupplierLink,
    CatalogItem,
    CategoryType,
    ItemCategory,
    Membership,
    Supplier,
    TradePurchase,
    TradePurchaseLine,
)

router = APIRouter(prefix="/v1/businesses/{business_id}", tags=["contacts"])
logger = logging.getLogger(__name__)


def _norm_name(s: str) -> str:
    return s.strip().lower()


async def _last_trade_purchase_date_for_supplier(
    db: AsyncSession, business_id: uuid.UUID, supplier_id: uuid.UUID
) -> date | None:
    r = await db.execute(
        select(func.max(TradePurchase.purchase_date)).where(
            TradePurchase.business_id == business_id,
            TradePurchase.supplier_id == supplier_id,
            TradePurchase.status.notin_(("deleted", "cancelled")),
        )
    )
    return r.scalar_one_or_none()


async def _last_trade_purchase_date_for_broker(
    db: AsyncSession, business_id: uuid.UUID, broker_id: uuid.UUID
) -> date | None:
    r = await db.execute(
        select(func.max(TradePurchase.purchase_date)).where(
            TradePurchase.business_id == business_id,
            TradePurchase.broker_id == broker_id,
            TradePurchase.status.notin_(("deleted", "cancelled")),
        )
    )
    return r.scalar_one_or_none()


class SupplierPrefsIn(BaseModel):
    """Preferred categories, subcategory (type) ids, and catalog item ids for search / AI."""

    category_ids: list[uuid.UUID] = Field(default_factory=list)
    type_ids: list[uuid.UUID] = Field(default_factory=list)
    item_ids: list[uuid.UUID] = Field(default_factory=list)


_PHONE_RE = re.compile(r"^\+?\d{10,15}$")
_GST_IN_RE = re.compile(r"^[0-9A-Z]{15}$")


class SupplierCreate(BaseModel):
    name: str = Field(min_length=1, max_length=255)
    phone: str | None = None
    location: str | None = None
    broker_id: uuid.UUID | None = None
    broker_ids: list[uuid.UUID] | None = None
    gst_number: str | None = Field(default=None, max_length=15)
    address: str | None = None
    notes: str | None = None
    default_payment_days: int | None = Field(default=None, ge=0, le=3650)
    default_discount: float | None = Field(default=None, ge=0)
    default_delivered_rate: float | None = Field(default=None, ge=0)
    default_billty_rate: float | None = Field(default=None, ge=0)
    freight_type: str | None = Field(default=None, max_length=16)
    ai_memory_enabled: bool = False
    preferences: SupplierPrefsIn | None = None

    @field_validator("name", mode="before")
    @classmethod
    def _strip_name(cls, v: object) -> object:
        if isinstance(v, str):
            return v.strip()
        return v

    @field_validator("name")
    @classmethod
    def _name_nonempty(cls, v: str) -> str:
        if not v or not v.strip():
            raise ValueError("name must not be empty or whitespace")
        return " ".join(v.split())

    @field_validator("phone", mode="before")
    @classmethod
    def _strip_phoneish(cls, v: object) -> object:
        if v is None or (isinstance(v, str) and not v.strip()):
            return None
        if isinstance(v, str):
            s = re.sub(r"[\s-]", "", v.strip())
            return s or None
        return v

    @field_validator("phone")
    @classmethod
    def _phone_format(cls, v: str | None) -> str | None:
        if v is None:
            return None
        if not _PHONE_RE.match(v):
            raise ValueError("must be 10-15 digits, optional + prefix")
        return v

    @field_validator("gst_number", mode="before")
    @classmethod
    def _strip_gst(cls, v: object) -> object:
        if v is None or (isinstance(v, str) and not v.strip()):
            return None
        if isinstance(v, str):
            return re.sub(r"\s+", "", v.strip().upper())
        return v

    @field_validator("gst_number")
    @classmethod
    def _gst_format(cls, v: str | None) -> str | None:
        if v is None:
            return None
        if not _GST_IN_RE.match(v):
            raise ValueError("gst_number must be 15 character GSTIN (alphanumeric, upper-case)")
        return v


class SupplierOut(BaseModel):
    id: uuid.UUID
    name: str
    phone: str | None = None
    location: str | None = None
    broker_id: uuid.UUID | None = None
    broker_ids: list[uuid.UUID] = Field(default_factory=list)
    gst_number: str | None = None
    address: str | None = None
    notes: str | None = None
    default_payment_days: int | None = None
    default_discount: float | None = None
    default_delivered_rate: float | None = None
    default_billty_rate: float | None = None
    freight_type: str | None = None
    ai_memory_enabled: bool = False
    preferences_json: str | None = None
    last_purchase_date: date | None = None

    model_config = {"from_attributes": True}


class SupplierOutCompact(BaseModel):
    """List/picker payload without large `address` / `notes` blobs (still includes preferences_json)."""

    id: uuid.UUID
    name: str
    phone: str | None = None
    location: str | None = None
    broker_id: uuid.UUID | None = None
    broker_ids: list[uuid.UUID] = Field(default_factory=list)
    gst_number: str | None = None
    default_payment_days: int | None = None
    default_discount: float | None = None
    default_delivered_rate: float | None = None
    default_billty_rate: float | None = None
    freight_type: str | None = None
    ai_memory_enabled: bool = False
    preferences_json: str | None = None
    last_purchase_date: date | None = None

    model_config = {"from_attributes": True}


class SupplierUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=255)
    phone: str | None = None
    location: str | None = None
    broker_id: uuid.UUID | None = None
    broker_ids: list[uuid.UUID] | None = None
    gst_number: str | None = Field(default=None, max_length=15)
    address: str | None = None
    notes: str | None = None
    default_payment_days: int | None = Field(default=None, ge=0, le=3650)
    default_discount: float | None = Field(default=None, ge=0)
    default_delivered_rate: float | None = Field(default=None, ge=0)
    default_billty_rate: float | None = Field(default=None, ge=0)
    freight_type: str | None = Field(default=None, max_length=16)
    ai_memory_enabled: bool | None = None
    preferences: SupplierPrefsIn | None = None

    @field_validator("name", mode="before")
    @classmethod
    def _strip_name_opt(cls, v: object) -> object:
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

    @field_validator("phone", mode="before")
    @classmethod
    def _strip_phoneish_u(cls, v: object) -> object:
        if v is None or (isinstance(v, str) and not v.strip()):
            return None
        if isinstance(v, str):
            s = re.sub(r"[\s-]", "", v.strip())
            return s or None
        return v

    @field_validator("phone")
    @classmethod
    def _phone_format_u(cls, v: str | None) -> str | None:
        if v is None:
            return None
        if not _PHONE_RE.match(v):
            raise ValueError("must be 10-15 digits, optional + prefix")
        return v

    @field_validator("gst_number", mode="before")
    @classmethod
    def _strip_gst_u(cls, v: object) -> object:
        if v is None or (isinstance(v, str) and not v.strip()):
            return None
        if isinstance(v, str):
            return re.sub(r"\s+", "", v.strip().upper())
        return v

    @field_validator("gst_number")
    @classmethod
    def _gst_format_u(cls, v: str | None) -> str | None:
        if v is None:
            return v
        if not _GST_IN_RE.match(v):
            raise ValueError("gst_number must be 15 character GSTIN (alphanumeric, upper-case)")
        return v


async def _supplier_dup(
    db: AsyncSession, business_id: uuid.UUID, name: str, exclude_id: uuid.UUID | None = None
) -> bool:
    q = select(Supplier.id).where(
        Supplier.business_id == business_id,
        func.lower(Supplier.name) == _norm_name(name),
    )
    if exclude_id is not None:
        q = q.where(Supplier.id != exclude_id)
    r = await db.execute(q)
    return r.first() is not None


async def _supplier_out(db: AsyncSession, s: Supplier) -> SupplierOut:
    base = SupplierOut.model_validate(s).model_dump()
    rb = await db.execute(
        select(BrokerSupplierLink.broker_id).where(BrokerSupplierLink.supplier_id == s.id)
    )
    base["broker_ids"] = list(rb.scalars().all())
    base["last_purchase_date"] = await _last_trade_purchase_date_for_supplier(
        db, s.business_id, s.id
    )
    return SupplierOut.model_validate(base)


@router.get(
    "/suppliers",
    response_model=list[SupplierOut] | list[SupplierOutCompact],
    summary="List suppliers (optional compact wire + limit)",
)
async def list_suppliers(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    compact: Annotated[
        bool,
        Query(
            description="Omit address/notes; skips loading those DB columns when true.",
        ),
    ] = False,
    limit: Annotated[
        int | None,
        Query(
            ge=1,
            le=5000,
            description="Max rows (only applied when compact=true).",
        ),
    ] = None,
):
    del _m
    t0 = time.perf_counter()

    async def _read_full() -> list[SupplierOut]:
        r = await db.execute(select(Supplier).where(Supplier.business_id == business_id))
        rows = r.scalars().all()
        if not rows:
            return []

        supplier_ids = [s.id for s in rows]
        rb = await db.execute(
            select(BrokerSupplierLink.supplier_id, BrokerSupplierLink.broker_id).where(
                BrokerSupplierLink.supplier_id.in_(supplier_ids)
            )
        )
        broker_map: dict[uuid.UUID, list[uuid.UUID]] = defaultdict(list)
        for sid, bid in rb.all():
            broker_map[sid].append(bid)

        out: list[SupplierOut] = []
        for s in rows:
            base = SupplierOut.model_validate(s).model_dump()
            base["broker_ids"] = list(broker_map.get(s.id, []))
            out.append(SupplierOut.model_validate(base))
        return out

    async def _read_compact() -> list[SupplierOutCompact]:
        stmt = (
            select(Supplier)
            .options(
                load_only(
                    Supplier.id,
                    Supplier.name,
                    Supplier.phone,
                    Supplier.gst_number,
                    Supplier.default_payment_days,
                    Supplier.default_discount,
                    Supplier.default_delivered_rate,
                    Supplier.default_billty_rate,
                    Supplier.location,
                    Supplier.freight_type,
                    Supplier.ai_memory_enabled,
                    Supplier.preferences_json,
                    Supplier.broker_id,
                )
            )
            .where(Supplier.business_id == business_id)
            .order_by(Supplier.name.asc())
        )
        if limit is not None:
            stmt = stmt.limit(limit)
        r = await db.execute(stmt)
        rows = r.scalars().all()
        if not rows:
            return []

        supplier_ids = [s.id for s in rows]
        rb = await db.execute(
            select(BrokerSupplierLink.supplier_id, BrokerSupplierLink.broker_id).where(
                BrokerSupplierLink.supplier_id.in_(supplier_ids)
            )
        )
        broker_map: dict[uuid.UUID, list[uuid.UUID]] = defaultdict(list)
        for sid, bid in rb.all():
            broker_map[sid].append(bid)

        out: list[SupplierOutCompact] = []
        for s in rows:
            out.append(
                SupplierOutCompact(
                    id=s.id,
                    name=s.name,
                    phone=s.phone,
                    location=s.location,
                    broker_id=s.broker_id,
                    broker_ids=list(broker_map.get(s.id, [])),
                    gst_number=s.gst_number,
                    default_payment_days=s.default_payment_days,
                    default_discount=float(s.default_discount)
                    if s.default_discount is not None
                    else None,
                    default_delivered_rate=float(s.default_delivered_rate)
                    if s.default_delivered_rate is not None
                    else None,
                    default_billty_rate=float(s.default_billty_rate)
                    if s.default_billty_rate is not None
                    else None,
                    freight_type=s.freight_type,
                    ai_memory_enabled=bool(s.ai_memory_enabled),
                    preferences_json=s.preferences_json,
                    last_purchase_date=None,
                )
            )
        return out

    if compact:
        out = await execute_with_retry(_read_compact)
    else:
        out = await execute_with_retry(_read_full)
    ms = int((time.perf_counter() - t0) * 1000)
    logger.info(
        "list_suppliers ok business_id=%s compact=%s limit=%s count=%s ms=%s",
        business_id,
        compact,
        limit,
        len(out),
        ms,
    )
    return out


@router.post("/suppliers", response_model=SupplierOut, status_code=status.HTTP_201_CREATED)
async def create_supplier(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    body: SupplierCreate,
):
    del _m
    if await _supplier_dup(db, business_id, body.name):
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            detail="A supplier with this name already exists",
        )
    ft = body.freight_type
    if ft is not None and ft not in ("included", "separate"):
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            detail="freight_type must be 'included' or 'separate'",
        )

    merged_broker_ids: list[uuid.UUID] = []
    if body.broker_ids:
        merged_broker_ids.extend(body.broker_ids)
    if body.broker_id and body.broker_id not in merged_broker_ids:
        merged_broker_ids.insert(0, body.broker_id)
    dedup_brokers: list[uuid.UUID] = []
    for bid in merged_broker_ids:
        if bid not in dedup_brokers:
            dedup_brokers.append(bid)

    prefs_json: str | None = None
    if body.preferences is not None:
        prefs_json = body.preferences.model_dump_json()

    s = Supplier(
        business_id=business_id,
        name=body.name.strip(),
        phone=body.phone,
        location=body.location,
        broker_id=dedup_brokers[0] if dedup_brokers else body.broker_id,
        gst_number=body.gst_number,
        address=body.address,
        notes=body.notes,
        default_payment_days=body.default_payment_days,
        default_discount=body.default_discount,
        default_delivered_rate=body.default_delivered_rate,
        default_billty_rate=body.default_billty_rate,
        freight_type=ft,
        ai_memory_enabled=body.ai_memory_enabled,
        preferences_json=prefs_json,
    )
    db.add(s)
    await db.flush()

    for bid in dedup_brokers:
        ok = await db.scalar(
            select(Broker.id).where(Broker.id == bid, Broker.business_id == business_id)
        )
        if ok is None:
            raise HTTPException(
                status.HTTP_400_BAD_REQUEST,
                detail=f"Broker not in this business: {bid}",
            )
        db.add(BrokerSupplierLink(broker_id=bid, supplier_id=s.id))

    await db.commit()
    await db.refresh(s)
    return await _supplier_out(db, s)


@router.patch("/suppliers/{supplier_id}", response_model=SupplierOut)
async def update_supplier(
    business_id: uuid.UUID,
    supplier_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    body: SupplierUpdate,
):
    del _m
    r = await db.execute(
        select(Supplier).where(Supplier.id == supplier_id, Supplier.business_id == business_id)
    )
    s = r.scalar_one_or_none()
    if s is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Supplier not found")
    data = body.model_dump(exclude_unset=True)
    if "name" in data and data["name"] is not None:
        if await _supplier_dup(db, business_id, data["name"], exclude_id=supplier_id):
            raise HTTPException(
                status.HTTP_409_CONFLICT,
                detail="A supplier with this name already exists",
            )
        s.name = data["name"].strip()
    if "phone" in data:
        s.phone = data["phone"]
    if "location" in data:
        s.location = data["location"]
    if "address" in data:
        s.address = data["address"]
    if "notes" in data:
        s.notes = data["notes"]
    if "freight_type" in data:
        fv = data["freight_type"]
        if fv is not None and fv not in ("included", "separate"):
            raise HTTPException(
                status.HTTP_400_BAD_REQUEST,
                detail="freight_type must be 'included' or 'separate'",
            )
        s.freight_type = fv
    if "ai_memory_enabled" in data and data["ai_memory_enabled"] is not None:
        s.ai_memory_enabled = bool(data["ai_memory_enabled"])
    if "preferences" in data and data["preferences"] is not None:
        s.preferences_json = SupplierPrefsIn.model_validate(data["preferences"]).model_dump_json()
    if "broker_ids" in data or "broker_id" in data:
        merged_broker_ids: list[uuid.UUID] = []
        incoming_ids = data.get("broker_ids")
        if incoming_ids:
            merged_broker_ids.extend(incoming_ids)
        if "broker_id" in data and data.get("broker_id") is not None:
            bid_single = data["broker_id"]
            if bid_single not in merged_broker_ids:
                merged_broker_ids.insert(0, bid_single)
        dedup_brokers: list[uuid.UUID] = []
        for bid in merged_broker_ids:
            if bid not in dedup_brokers:
                dedup_brokers.append(bid)
        if "broker_id" in data and data.get("broker_id") is None and "broker_ids" not in data:
            dedup_brokers = []
        for bid in dedup_brokers:
            ok = await db.scalar(
                select(Broker.id).where(Broker.id == bid, Broker.business_id == business_id)
            )
            if ok is None:
                raise HTTPException(
                    status.HTTP_400_BAD_REQUEST,
                    detail=f"Broker not in this business: {bid}",
                )
        await db.execute(delete(BrokerSupplierLink).where(BrokerSupplierLink.supplier_id == s.id))
        for bid in dedup_brokers:
            db.add(BrokerSupplierLink(broker_id=bid, supplier_id=s.id))
        s.broker_id = dedup_brokers[0] if dedup_brokers else data.get("broker_id")
    for k in (
        "gst_number",
        "default_payment_days",
        "default_discount",
        "default_delivered_rate",
        "default_billty_rate",
    ):
        if k in data:
            setattr(s, k, data[k])
    await db.commit()
    await db.refresh(s)
    return await _supplier_out(db, s)


@router.delete("/suppliers/{supplier_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_supplier(
    business_id: uuid.UUID,
    supplier_id: uuid.UUID,
    _owner: Annotated[Membership, Depends(require_owner_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    del _owner
    r = await db.execute(
        select(Supplier).where(Supplier.id == supplier_id, Supplier.business_id == business_id)
    )
    s = r.scalar_one_or_none()
    if s is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Supplier not found")
    ec = await db.execute(
        select(func.count(TradePurchase.id)).where(
            TradePurchase.business_id == business_id,
            TradePurchase.supplier_id == supplier_id,
            TradePurchase.status.notin_(("deleted", "cancelled")),
        )
    )
    if int(ec.scalar() or 0) > 0:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            detail="Cannot delete a supplier that has purchase entries",
        )
    await db.delete(s)
    await db.commit()


class LinkedSupplierOut(BaseModel):
    """Suppliers that appear on confirmed-scope trade purchases with this broker."""

    id: uuid.UUID
    name: str
    phone: str | None = None


class BrokerOut(BaseModel):
    id: uuid.UUID
    name: str
    phone: str | None = None
    location: str | None = None
    notes: str | None = None
    commission_type: str
    commission_value: float | None
    default_payment_days: int | None = None
    default_discount: float | None = None
    default_delivered_rate: float | None = None
    default_billty_rate: float | None = None
    freight_type: str | None = None
    image_url: str | None = None
    supplier_ids: list[uuid.UUID] = Field(default_factory=list)
    preferences_json: str | None = None
    last_purchase_date: date | None = None

    model_config = {"from_attributes": True}


class BrokerUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=255)
    phone: str | None = Field(default=None, max_length=15)
    location: str | None = None
    notes: str | None = None
    commission_type: str | None = Field(default=None, pattern="^(percent|flat)$")
    commission_value: float | None = Field(default=None, ge=0)
    default_payment_days: int | None = Field(default=None, ge=0)
    default_discount: float | None = Field(default=None, ge=0)
    default_delivered_rate: float | None = Field(default=None, ge=0)
    default_billty_rate: float | None = Field(default=None, ge=0)
    freight_type: str | None = Field(default=None, pattern="^(included|separate)$")
    image_url: str | None = Field(default=None, max_length=1024)
    supplier_ids: list[uuid.UUID] | None = None
    preferences: SupplierPrefsIn | None = None


async def _broker_dup(
    db: AsyncSession, business_id: uuid.UUID, name: str, exclude_id: uuid.UUID | None = None
) -> bool:
    q = select(Broker.id).where(
        Broker.business_id == business_id,
        func.lower(Broker.name) == _norm_name(name),
    )
    if exclude_id is not None:
        q = q.where(Broker.id != exclude_id)
    r = await db.execute(q)
    return r.first() is not None


async def _broker_out(db: AsyncSession, b: Broker) -> BrokerOut:
    base = BrokerOut.model_validate(b).model_dump()
    rs = await db.execute(
        select(BrokerSupplierLink.supplier_id).where(BrokerSupplierLink.broker_id == b.id)
    )
    base["supplier_ids"] = list(rs.scalars().all())
    base["last_purchase_date"] = await _last_trade_purchase_date_for_broker(
        db, b.business_id, b.id
    )
    return BrokerOut.model_validate(base)


@router.get("/brokers", response_model=list[BrokerOut])
async def list_brokers(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    del _m
    t0 = time.perf_counter()

    async def _read() -> list[BrokerOut]:
        r = await db.execute(select(Broker).where(Broker.business_id == business_id))
        rows = r.scalars().all()
        if not rows:
            return []
        broker_ids = [b.id for b in rows]
        rs = await db.execute(
            select(BrokerSupplierLink.broker_id, BrokerSupplierLink.supplier_id).where(
                BrokerSupplierLink.broker_id.in_(broker_ids)
            )
        )
        sup_map: dict[uuid.UUID, list[uuid.UUID]] = defaultdict(list)
        for bid, sid in rs.all():
            sup_map[bid].append(sid)
        out: list[BrokerOut] = []
        for b in rows:
            base = BrokerOut.model_validate(b).model_dump()
            base["supplier_ids"] = list(sup_map.get(b.id, []))
            out.append(BrokerOut.model_validate(base))
        return out

    out = await execute_with_retry(_read)
    ms = int((time.perf_counter() - t0) * 1000)
    logger.info(
        "list_brokers ok business_id=%s count=%s ms=%s",
        business_id,
        len(out),
        ms,
    )
    return out


class BrokerCreate(BaseModel):
    name: str = Field(min_length=1, max_length=255)
    phone: str | None = Field(default=None, max_length=15)
    location: str | None = None
    notes: str | None = None
    commission_type: str = Field(default="percent", pattern="^(percent|flat)$")
    commission_value: float | None = Field(default=None, ge=0)
    default_payment_days: int | None = Field(default=None, ge=0)
    default_discount: float | None = Field(default=None, ge=0)
    default_delivered_rate: float | None = Field(default=None, ge=0)
    default_billty_rate: float | None = Field(default=None, ge=0)
    freight_type: str | None = Field(default=None, pattern="^(included|separate)$")
    image_url: str | None = Field(default=None, max_length=1024)
    supplier_ids: list[uuid.UUID] | None = None
    preferences: SupplierPrefsIn | None = None


@router.post("/brokers", response_model=BrokerOut, status_code=status.HTTP_201_CREATED)
async def create_broker(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    body: BrokerCreate,
):
    del _m
    if await _broker_dup(db, business_id, body.name):
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            detail="A broker with this name already exists",
        )
    b = Broker(
        business_id=business_id,
        name=body.name.strip(),
        phone=body.phone,
        location=body.location,
        notes=body.notes,
        commission_type=body.commission_type,
        commission_value=body.commission_value,
        default_payment_days=body.default_payment_days,
        default_discount=body.default_discount,
        default_delivered_rate=body.default_delivered_rate,
        default_billty_rate=body.default_billty_rate,
        freight_type=body.freight_type,
        image_url=(body.image_url.strip() if body.image_url and body.image_url.strip() else None),
        preferences_json=body.preferences.model_dump_json() if body.preferences else None,
    )
    db.add(b)
    await db.flush()
    dedup_suppliers: list[uuid.UUID] = []
    for sid in body.supplier_ids or []:
        if sid not in dedup_suppliers:
            dedup_suppliers.append(sid)
    for sid in dedup_suppliers:
        ok = await db.scalar(
            select(Supplier.id).where(Supplier.id == sid, Supplier.business_id == business_id)
        )
        if ok is None:
            raise HTTPException(
                status.HTTP_400_BAD_REQUEST,
                detail=f"Supplier not in this business: {sid}",
            )
        db.add(BrokerSupplierLink(broker_id=b.id, supplier_id=sid))
        sup = await db.scalar(select(Supplier).where(Supplier.id == sid))
        if sup is not None:
            sup.broker_id = b.id
    await db.commit()
    await db.refresh(b)
    return await _broker_out(db, b)


@router.patch("/brokers/{broker_id}", response_model=BrokerOut)
async def update_broker(
    business_id: uuid.UUID,
    broker_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    body: BrokerUpdate,
):
    del _m
    r = await db.execute(
        select(Broker).where(Broker.id == broker_id, Broker.business_id == business_id)
    )
    b = r.scalar_one_or_none()
    if b is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Broker not found")
    data = body.model_dump(exclude_unset=True)
    if "name" in data and data["name"] is not None:
        if await _broker_dup(db, business_id, data["name"], exclude_id=broker_id):
            raise HTTPException(
                status.HTTP_409_CONFLICT,
                detail="A broker with this name already exists",
            )
        b.name = data["name"].strip()
    if "commission_type" in data and data["commission_type"] is not None:
        b.commission_type = data["commission_type"]
    if "commission_value" in data:
        b.commission_value = data["commission_value"]
    if "phone" in data:
        b.phone = data["phone"]
    if "location" in data:
        b.location = data["location"]
    if "notes" in data:
        b.notes = data["notes"]
    if "preferences" in data and data["preferences"] is not None:
        b.preferences_json = SupplierPrefsIn.model_validate(data["preferences"]).model_dump_json()
    if "default_payment_days" in data:
        b.default_payment_days = data["default_payment_days"]
    if "default_discount" in data:
        b.default_discount = data["default_discount"]
    if "default_delivered_rate" in data:
        b.default_delivered_rate = data["default_delivered_rate"]
    if "default_billty_rate" in data:
        b.default_billty_rate = data["default_billty_rate"]
    if "freight_type" in data:
        b.freight_type = data["freight_type"]
    if "image_url" in data:
        v = data["image_url"]
        b.image_url = v.strip() if isinstance(v, str) and v.strip() else v
    if "supplier_ids" in data:
        dedup_suppliers: list[uuid.UUID] = []
        for sid in data["supplier_ids"] or []:
            if sid not in dedup_suppliers:
                dedup_suppliers.append(sid)
        for sid in dedup_suppliers:
            ok = await db.scalar(
                select(Supplier.id).where(Supplier.id == sid, Supplier.business_id == business_id)
            )
            if ok is None:
                raise HTTPException(
                    status.HTTP_400_BAD_REQUEST,
                    detail=f"Supplier not in this business: {sid}",
                )
        await db.execute(delete(BrokerSupplierLink).where(BrokerSupplierLink.broker_id == b.id))
        for sid in dedup_suppliers:
            db.add(BrokerSupplierLink(broker_id=b.id, supplier_id=sid))
            sup = await db.scalar(select(Supplier).where(Supplier.id == sid))
            if sup is not None:
                sup.broker_id = b.id
    await db.commit()
    await db.refresh(b)
    return await _broker_out(db, b)


@router.delete("/brokers/{broker_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_broker(
    business_id: uuid.UUID,
    broker_id: uuid.UUID,
    _owner: Annotated[Membership, Depends(require_owner_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    del _owner
    r = await db.execute(
        select(Broker).where(Broker.id == broker_id, Broker.business_id == business_id)
    )
    b = r.scalar_one_or_none()
    if b is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Broker not found")
    ec = await db.execute(
        select(func.count(TradePurchase.id)).where(
            TradePurchase.business_id == business_id,
            TradePurchase.broker_id == broker_id,
            TradePurchase.status.notin_(("deleted", "cancelled")),
        )
    )
    if int(ec.scalar() or 0) > 0:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            detail="Cannot delete a broker linked to purchase entries",
        )
    sc = await db.execute(
        select(func.count(Supplier.id)).where(
            Supplier.business_id == business_id,
            Supplier.broker_id == broker_id,
        )
    )
    if int(sc.scalar() or 0) > 0:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            detail="Cannot delete a broker assigned to suppliers — reassign suppliers first",
        )
    await db.delete(b)
    await db.commit()


@router.get("/brokers/{broker_id}", response_model=BrokerOut)
async def get_broker(
    business_id: uuid.UUID,
    broker_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    del _m
    r = await db.execute(
        select(Broker).where(Broker.id == broker_id, Broker.business_id == business_id)
    )
    b = r.scalar_one_or_none()
    if b is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Broker not found")
    return await _broker_out(db, b)


@router.get("/brokers/{broker_id}/linked-suppliers", response_model=list[LinkedSupplierOut])
async def broker_linked_suppliers(
    business_id: uuid.UUID,
    broker_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    del _m
    br = await db.execute(
        select(Broker.id).where(Broker.id == broker_id, Broker.business_id == business_id)
    )
    if br.scalar_one_or_none() is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Broker not found")
    supplier_ids_subq = (
        select(TradePurchase.supplier_id)
        .where(
            TradePurchase.business_id == business_id,
            TradePurchase.broker_id == broker_id,
            trade_purchase_status_in_reports(),
        )
        .distinct()
    )
    q = (
        select(Supplier.id, Supplier.name, Supplier.phone)
        .where(Supplier.business_id == business_id, Supplier.id.in_(supplier_ids_subq))
        .order_by(func.lower(Supplier.name))
        .limit(200)
    )
    r2 = await execute_with_retry(lambda: db.execute(q))
    return [
        LinkedSupplierOut(
            id=row[0],
            name=row[1],
            phone=row[2],
        )
        for row in r2.all()
    ]


@router.get("/suppliers/{supplier_id}", response_model=SupplierOut)
async def get_supplier(
    business_id: uuid.UUID,
    supplier_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    del _m
    r = await db.execute(
        select(Supplier).where(Supplier.id == supplier_id, Supplier.business_id == business_id)
    )
    s = r.scalar_one_or_none()
    if s is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Supplier not found")
    return await _supplier_out(db, s)


def _trade_purchase_date_filter(business_id: uuid.UUID, from_date: date, to_date: date):
    return (
        TradePurchase.business_id == business_id,
        TradePurchase.purchase_date >= from_date,
        TradePurchase.purchase_date <= to_date,
        trade_purchase_status_in_reports(),
    )


class SupplierMetricsOut(BaseModel):
    deals: int
    total_qty: float
    avg_landing: float
    total_profit: float
    purchase_amount: float
    profit_margin_pct: float


@router.get("/suppliers/{supplier_id}/metrics", response_model=SupplierMetricsOut)
async def supplier_metrics(
    business_id: uuid.UUID,
    supplier_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    from_date: date = Query(..., alias="from"),
    to_date: date = Query(..., alias="to"),
):
    del _m
    r = await db.execute(
        select(Supplier).where(Supplier.id == supplier_id, Supplier.business_id == business_id)
    )
    if r.scalar_one_or_none() is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Supplier not found")
    bf = _trade_purchase_date_filter(business_id, from_date, to_date)
    amt = tq.trade_line_amount_expr()
    profit = tq.trade_line_profit_expr()
    q = (
        select(
            func.count(func.distinct(TradePurchase.id)).label("deals"),
            func.coalesce(func.sum(TradePurchaseLine.qty), 0).label("tq"),
            func.coalesce(func.avg(TradePurchaseLine.landing_cost), 0).label("al"),
            func.coalesce(func.sum(profit), 0).label("tp"),
            func.coalesce(func.sum(amt), 0).label("pam"),
        )
        .select_from(TradePurchaseLine)
        .join(TradePurchase, TradePurchase.id == TradePurchaseLine.trade_purchase_id)
        .where(*bf, TradePurchase.supplier_id == supplier_id)
    )
    row = (await db.execute(q)).one()
    deals = int(row[0] or 0)
    tq = float(row[1] or 0)
    al = float(row[2] or 0)
    tp = float(row[3] or 0)
    pam = float(row[4] or 0)
    margin = (tp / pam * 100.0) if pam > 0 else 0.0
    return SupplierMetricsOut(
        deals=deals,
        total_qty=tq,
        avg_landing=al,
        total_profit=tp,
        purchase_amount=pam,
        profit_margin_pct=margin,
    )


class BrokerMetricsOut(BaseModel):
    deals: int
    total_commission: float
    total_profit: float


@router.get("/brokers/{broker_id}/metrics", response_model=BrokerMetricsOut)
async def broker_metrics(
    business_id: uuid.UUID,
    broker_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    from_date: date = Query(..., alias="from"),
    to_date: date = Query(..., alias="to"),
):
    del _m
    r = await db.execute(
        select(Broker).where(Broker.id == broker_id, Broker.business_id == business_id)
    )
    if r.scalar_one_or_none() is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Broker not found")
    bf = _trade_purchase_date_filter(business_id, from_date, to_date)
    profit = tq.trade_line_profit_expr()
    deals = int(
        (
            await db.execute(
                select(func.count(func.distinct(TradePurchase.id)))
                .select_from(TradePurchase)
                .where(*bf, TradePurchase.broker_id == broker_id)
            )
        ).scalar()
        or 0
    )
    tc = float(
        (
            await db.execute(
                select(func.coalesce(func.sum(TradePurchase.commission_money), 0))
                .select_from(TradePurchase)
                .where(*bf, TradePurchase.broker_id == broker_id)
            )
        ).scalar()
        or 0
    )
    tp = float(
        (
            await db.execute(
                select(func.coalesce(func.sum(profit), 0))
                .select_from(TradePurchaseLine)
                .join(
                    TradePurchase,
                    TradePurchase.id == TradePurchaseLine.trade_purchase_id,
                )
                .where(*bf, TradePurchase.broker_id == broker_id)
            )
        ).scalar()
        or 0
    )
    return BrokerMetricsOut(
        deals=deals,
        total_commission=tc,
        total_profit=tp,
    )


class CatalogSubcategoryRow(BaseModel):
    """Catalog middle layer: type under category (subcategory)."""

    id: uuid.UUID
    name: str
    category_id: uuid.UUID
    category_name: str


class ItemSearchHitOut(BaseModel):
    """Item name plus catalog id when the row matches a catalog item."""

    name: str
    catalog_item_id: uuid.UUID | None = None


class SearchOut(BaseModel):
    suppliers: list[SupplierOut]
    brokers: list[BrokerOut]
    item_names: list[str]
    item_hits: list[ItemSearchHitOut] = Field(default_factory=list)
    categories: list[str]
    catalog_subcategories: list[CatalogSubcategoryRow] = Field(default_factory=list)


@router.get("/contacts/search", response_model=SearchOut)
async def contacts_search(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    q: str = Query("", max_length=200),
    limit: int = Query(15, ge=1, le=50),
    scope: str | None = Query(
        None,
        description="Optional: suppliers|brokers|categories|catalog_types|items — fetch only that bucket",
    ),
):
    del _m
    term = q.strip()
    scopes = scope.strip().lower() if scope and scope.strip() else None

    def bucket(name: str) -> bool:
        if scopes is None or scopes == "all":
            return True
        return scopes == name

    if not term:
        return SearchOut(
            suppliers=[],
            brokers=[],
            item_names=[],
            item_hits=[],
            categories=[],
            catalog_subcategories=[],
        )

    like_contains = f"%{_norm_name(term)}%"
    term_l = _norm_name(term)

    suppliers: list[SupplierOut] = []
    if bucket("suppliers"):
        rs = await db.execute(
            select(Supplier)
            .where(
                Supplier.business_id == business_id,
                func.lower(Supplier.name).like(like_contains),
            )
            .limit(limit)
        )
        rows = list(rs.scalars().all())
        rows.sort(
            key=lambda s: (
                not str(s.name).strip().lower().startswith(term_l),
                str(s.name).strip().lower(),
            )
        )
        for s in rows:
            suppliers.append(await _supplier_out(db, s))

    brokers: list[BrokerOut] = []
    if bucket("brokers"):
        rb = await db.execute(
            select(Broker)
            .where(
                Broker.business_id == business_id,
                func.lower(Broker.name).like(like_contains),
            )
            .limit(limit)
        )
        brows = list(rb.scalars().all())
        brows.sort(
            key=lambda b: (
                not str(b.name).strip().lower().startswith(term_l),
                str(b.name).strip().lower(),
            )
        )
        brokers = [BrokerOut.model_validate(b) for b in brows]

    item_names: list[str] = []
    item_hits: list[ItemSearchHitOut] = []
    if bucket("items"):
        ri = await db.execute(
            select(TradePurchaseLine.item_name)
            .distinct()
            .select_from(TradePurchaseLine)
            .join(TradePurchase, TradePurchase.id == TradePurchaseLine.trade_purchase_id)
            .where(
                TradePurchase.business_id == business_id,
                trade_purchase_status_in_reports(),
                func.lower(TradePurchaseLine.item_name).like(like_contains),
            )
            .limit(limit * 2)
        )
        line_by_norm: dict[str, str] = {}
        for row in ri.all():
            raw = str(row[0]).strip() if row[0] else ""
            if not raw:
                continue
            k = _norm_name(raw)
            if k not in line_by_norm:
                line_by_norm[k] = raw

        ric = await db.execute(
            select(CatalogItem.id, CatalogItem.name)
            .where(
                CatalogItem.business_id == business_id,
                func.lower(CatalogItem.name).like(like_contains),
            )
            .distinct()
            .limit(limit * 2)
        )
        cat_by_norm: dict[str, tuple[uuid.UUID, str]] = {}
        for row in ric.all():
            cid, raw_nm = row[0], str(row[1]).strip() if row[1] else ""
            if not raw_nm:
                continue
            k = _norm_name(raw_nm)
            if k not in cat_by_norm:
                cat_by_norm[k] = (cid, raw_nm)

        merged: dict[str, tuple[str, uuid.UUID | None]] = {}
        for k, display in line_by_norm.items():
            if k in cat_by_norm:
                cid, cname = cat_by_norm[k]
                merged[k] = (cname, cid)
            else:
                merged[k] = (display, None)
        for k, (cid, cname) in cat_by_norm.items():
            if k not in merged:
                merged[k] = (cname, cid)

        hits_sorted = sorted(
            merged.items(),
            key=lambda kv: (
                not kv[1][0].strip().lower().startswith(term_l),
                kv[1][0].strip().lower(),
            ),
        )[:limit]
        item_hits = [
            ItemSearchHitOut(name=pair[0], catalog_item_id=pair[1])
            for _, pair in hits_sorted
        ]
        missing = [h for h in item_hits if h.catalog_item_id is None and h.name.strip()]
        if missing:
            norms = {_norm_name(h.name) for h in missing}
            conds = [
                func.lower(func.trim(CatalogItem.name)) == n for n in norms if n
            ]
            if conds:
                r2 = await db.execute(
                    select(CatalogItem.id, CatalogItem.name).where(
                        CatalogItem.business_id == business_id,
                        or_(*conds),
                    )
                )
                id_by_norm: dict[str, uuid.UUID] = {}
                for cid, raw_nm in r2.all():
                    if raw_nm:
                        id_by_norm[_norm_name(str(raw_nm))] = cid
                item_hits = [
                    ItemSearchHitOut(
                        name=h.name,
                        catalog_item_id=h.catalog_item_id
                        or id_by_norm.get(_norm_name(h.name)),
                    )
                    for h in item_hits
                ]
        item_names = [h.name for h in item_hits]

    categories: list[str] = []
    if bucket("categories"):
        ricc = await db.execute(
            select(ItemCategory.name)
            .where(
                ItemCategory.business_id == business_id,
                func.lower(ItemCategory.name).like(like_contains),
            )
            .distinct()
            .limit(limit * 2)
        )
        cat_set: set[str] = set()
        for row in ricc.all():
            if row[0] and str(row[0]).strip():
                cat_set.add(str(row[0]).strip())
        categories = sorted(
            cat_set,
            key=lambda n: (
                not str(n).strip().lower().startswith(term_l),
                str(n).strip().lower(),
            ),
        )[:limit]

    catalog_subcategories: list[CatalogSubcategoryRow] = []
    if bucket("catalog_types"):
        rsub = await db.execute(
            select(CategoryType.id, CategoryType.name, ItemCategory.id, ItemCategory.name)
            .join(ItemCategory, ItemCategory.id == CategoryType.category_id)
            .where(
                ItemCategory.business_id == business_id,
                or_(
                    func.lower(CategoryType.name).like(like_contains),
                    func.lower(ItemCategory.name).like(like_contains),
                ),
            )
            .distinct()
            .limit(limit * 2)
        )
        sub_pairs: list[tuple[object, ...]] = list(rsub.all())
        sub_pairs.sort(
            key=lambda row: (
                not str(row[1]).strip().lower().startswith(term_l)
                and not str(row[3]).strip().lower().startswith(term_l),
                str(row[1]).strip().lower(),
            )
        )
        for row in sub_pairs[:limit]:
            catalog_subcategories.append(
                CatalogSubcategoryRow(
                    id=row[0],
                    name=row[1],
                    category_id=row[2],
                    category_name=row[3],
                )
            )

    return SearchOut(
        suppliers=suppliers,
        brokers=brokers,
        item_names=item_names,
        item_hits=item_hits,
        categories=categories,
        catalog_subcategories=catalog_subcategories,
    )


class CategoryItemRow(BaseModel):
    item_name: str
    line_count: int
    total_profit: float
    total_qty: float


@router.get("/contacts/category-items", response_model=list[CategoryItemRow])
async def category_items(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    category: str = Query(..., min_length=1, max_length=255),
    from_date: date = Query(..., alias="from"),
    to_date: date = Query(..., alias="to"),
):
    del _m
    tf = _trade_purchase_date_filter(business_id, from_date, to_date)
    if category != "Uncategorized":
        q = (
            select(
                TradePurchaseLine.item_name,
                func.count(TradePurchaseLine.id).label("lc"),
                func.coalesce(func.sum(TradePurchaseLine.profit), 0).label("tp"),
                func.coalesce(func.sum(TradePurchaseLine.qty), 0).label("tq"),
            )
            .select_from(TradePurchaseLine)
            .join(TradePurchase, TradePurchase.id == TradePurchaseLine.trade_purchase_id)
            .join(CatalogItem, CatalogItem.id == TradePurchaseLine.catalog_item_id)
            .join(ItemCategory, ItemCategory.id == CatalogItem.category_id)
            .where(*tf, ItemCategory.name == category)
            .group_by(TradePurchaseLine.item_name)
            .order_by(func.coalesce(func.sum(TradePurchaseLine.profit), 0).desc())
        )
    else:
        q = (
            select(
                TradePurchaseLine.item_name,
                func.count(TradePurchaseLine.id).label("lc"),
                func.coalesce(func.sum(TradePurchaseLine.profit), 0).label("tp"),
                func.coalesce(func.sum(TradePurchaseLine.qty), 0).label("tq"),
            )
            .select_from(TradePurchaseLine)
            .join(TradePurchase, TradePurchase.id == TradePurchaseLine.trade_purchase_id)
            .join(CatalogItem, CatalogItem.id == TradePurchaseLine.catalog_item_id)
            .outerjoin(ItemCategory, ItemCategory.id == CatalogItem.category_id)
            .where(*tf, ItemCategory.id.is_(None))
            .group_by(TradePurchaseLine.item_name)
            .order_by(func.coalesce(func.sum(TradePurchaseLine.profit), 0).desc())
        )

    r = await db.execute(q)
    return [
        CategoryItemRow(
            item_name=row[0],
            line_count=int(row[1] or 0),
            total_profit=float(row[2] or 0),
            total_qty=float(row[3] or 0),
        )
        for row in r.all()
    ]
