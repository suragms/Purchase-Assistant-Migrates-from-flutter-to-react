"""Normalize purchase line quantities into each catalog item's stock unit (SSOT)."""

from __future__ import annotations

import logging
import uuid
from decimal import Decimal, ROUND_HALF_UP
from typing import Any

from app.models.catalog import CatalogItem
from app.services.stock_tracking_profile import profile_from_catalog_item
from app.services.trade_unit_type import derive_trade_unit_type, parse_kg_per_bag_from_name

logger = logging.getLogger(__name__)

_QTY_QUANT = Decimal("0.001")


def _dec(x: Any) -> Decimal:
    if x is None:
        return Decimal(0)
    return Decimal(str(x))


def _round_qty(v: Decimal) -> Decimal:
    if v <= 0:
        return Decimal(0)
    return v.quantize(_QTY_QUANT, rounding=ROUND_HALF_UP)


def catalog_stock_unit(item: CatalogItem | Any) -> str:
    """Primary warehouse unit from stock-tracking profile."""
    return profile_from_catalog_item(item).primary_unit


def catalog_kg_per_bag(item: CatalogItem | Any, line: Any | None = None) -> Decimal | None:
    """Kg per bag OR kg per retail piece (profile-aware)."""
    profile = profile_from_catalog_item(item)
    if profile.weight_per_primary and profile.weight_per_primary > 0:
        if profile.mode in ("wholesale_bag", "retail_packet"):
            return profile.weight_per_primary
    candidates: list[Any] = []
    if line is not None:
        candidates.extend(
            [
                getattr(line, "kg_per_unit", None),
                getattr(line, "weight_per_unit", None),
            ]
        )
    candidates.extend(
        [
            getattr(item, "default_kg_per_bag", None),
            getattr(item, "conversion_factor", None),
            getattr(item, "package_size", None)
            if (getattr(item, "package_measurement", None) or "").upper() == "KG"
            else None,
        ]
    )
    name = (
        getattr(line, "item_name", None)
        if line is not None
        else None
    ) or getattr(item, "name", None)
    parsed = parse_kg_per_bag_from_name(name)
    if parsed is not None and profile.mode == "wholesale_bag":
        candidates.append(parsed)
    for raw in candidates:
        if raw is None:
            continue
        v = _dec(raw)
        if v > 0:
            return v
    return None


def line_kg_qty(line: Any, item: CatalogItem | Any) -> Decimal:
    """Total kg represented by a purchase line."""
    tw = getattr(line, "total_weight", None)
    if tw is not None:
        w = _dec(tw)
        if w > 0:
            return w
    ut = derive_trade_unit_type(getattr(line, "unit", None))
    qty = _dec(getattr(line, "qty", 0))
    if qty <= 0:
        return Decimal(0)
    if ut == "kg":
        return qty
    if ut == "bag":
        kpb = catalog_kg_per_bag(item, line)
        if kpb and kpb > 0:
            return qty * kpb
    return Decimal(0)


def current_stock_kg(item: CatalogItem | Any, qty_in_stock_unit: Decimal | None = None) -> Decimal | None:
    """Kg equivalent for bag-primary or retail-piece items."""
    qty = qty_in_stock_unit if qty_in_stock_unit is not None else _dec(getattr(item, "current_stock", 0))
    profile = profile_from_catalog_item(item)
    if profile.base_unit == "kg" and profile.primary_unit == "kg":
        return _round_qty(qty) if qty > 0 else None
    w = profile.weight_per_primary or catalog_kg_per_bag(item, None)
    if w and w > 0 and qty > 0 and profile.mode in ("wholesale_bag", "retail_packet"):
        return _round_qty(qty * w)
    return None


def line_qty_in_stock_unit(line: Any, item: CatalogItem | Any) -> Decimal:
    """
    Convert a purchase line qty into the catalog item's stock unit.

    Uses persisted ``qty_in_stock_unit`` when set (audit snapshot).
    """
    snap = getattr(line, "qty_in_stock_unit", None)
    if snap is not None:
        return _round_qty(_dec(snap))

    qty = _dec(getattr(line, "qty", 0))
    if qty <= 0:
        return Decimal(0)

    stock_type = derive_trade_unit_type(catalog_stock_unit(item))
    line_type = derive_trade_unit_type(getattr(line, "unit", None))

    if line_type == stock_type:
        return _round_qty(qty)

    profile = profile_from_catalog_item(item)

    if stock_type == "bag" or profile.mode == "wholesale_bag":
        if line_type == "bag":
            return _round_qty(qty)
        if line_type == "kg":
            kg = line_kg_qty(line, item)
            kpb = catalog_kg_per_bag(item, line)
            if kpb and kpb > 0 and kg > 0:
                return _round_qty(kg / kpb)
            logger.warning(
                "Cannot convert kg line to bags for item %s (kg=%s, kpb=%s)",
                getattr(item, "id", None),
                kg,
                kpb,
            )
            return Decimal(0)

    if stock_type in ("pcs", "other") and profile.mode == "retail_packet":
        if line_type in ("pcs", "other"):
            lu = (getattr(line, "unit", None) or "").strip().lower()
            if lu in ("piece", "pieces", "pcs", "pkt", "packet", ""):
                return _round_qty(qty)
        if line_type == "kg":
            kg = line_kg_qty(line, item)
            wpp = catalog_kg_per_bag(item, line)
            if wpp and wpp > 0 and kg > 0:
                return _round_qty(kg / wpp)
            return Decimal(0)
        if line_type == "bag":
            return Decimal(0)

    if stock_type == "kg":
        if line_type == "kg":
            return _round_qty(qty)
        if line_type == "bag":
            kpb = catalog_kg_per_bag(item, line)
            if kpb and kpb > 0:
                return _round_qty(qty * kpb)
            return Decimal(0)

    if stock_type in ("pcs", "other") and line_type in ("pcs", "other"):
        return _round_qty(qty)

    if stock_type == "box" and line_type == "box":
        return _round_qty(qty)

    # Retail rows named "* BOX" purchased in boxes — 1 box = 1 unit until owner sets box default_unit.
    if line_type == "box" and stock_type in ("pcs", "other"):
        name = (getattr(item, "name", None) or "").upper()
        pt = (getattr(item, "package_type", None) or "").strip().upper()
        if "BOX" in name or pt == "BOX":
            return _round_qty(qty)

    if stock_type == "tin" and line_type == "tin":
        return _round_qty(qty)

    # Same generic unit string (e.g. litre) — use qty as entered
    su = catalog_stock_unit(item)
    lu = (getattr(line, "unit", None) or "").strip().lower()
    if su and lu and su == lu:
        return _round_qty(qty)

    logger.warning(
        "Unmapped unit pair stock=%s line=%s item=%s — qty not applied",
        stock_type,
        line_type,
        getattr(item, "id", None),
    )
    return Decimal(0)


async def fetch_catalog_items_map(
    db,
    business_id: uuid.UUID,
    item_ids: set[uuid.UUID],
) -> dict[uuid.UUID, CatalogItem]:
    if not item_ids:
        return {}
    from sqlalchemy import select

    from app.models import CatalogItem as CI

    r = await db.execute(
        select(CI).where(
            CI.business_id == business_id,
            CI.id.in_(item_ids),
            CI.deleted_at.is_(None),
        )
    )
    return {i.id: i for i in r.scalars().all()}
