"""Warehouse stock-tracking modes — wholesale bag vs retail packet vs loose kg."""

from __future__ import annotations

import re
from dataclasses import dataclass
from decimal import Decimal
from typing import Any

from app.services.trade_unit_type import derive_trade_unit_type, parse_kg_per_bag_from_name

_WHOLESALE_KG = frozenset({25, 30, 40, 45, 50, 55})
_RETAIL_KG = frozenset({1, 2, 5, 10})
_BULK_CATEGORIES = frozenset(
    {
        "RICE",
        "SUGAR",
        "FLOUR",
        "GRAIN",
        "PULSES",
        "MAIDA",
        "ATTA",
        "SOOJI",
        "DAL",
    }
)
_KG_TOKEN = re.compile(r"(\d+(?:\.\d+)?)\s*KG\b", re.IGNORECASE)
_BAG_WORDS = re.compile(r"\b(BAG|SACK|BAGS|SACKS)\b", re.IGNORECASE)
_BOX_WORDS = re.compile(r"\b(BOX|CTN|CARTON)\b", re.IGNORECASE)


def _name_looks_like_retail_box(name: str | None) -> bool:
    if not name:
        return False
    upper = name.strip().upper()
    return bool(_BOX_WORDS.search(upper))


@dataclass(frozen=True)
class StockTrackingProfile:
    mode: str
    primary_unit: str
    base_unit: str
    weight_per_primary: Decimal | None = None
    pieces_per_box: Decimal | None = None
    liters_per_tin: Decimal | None = None
    allowed_line_units: frozenset[str] = frozenset()

    def as_dict(self) -> dict[str, Any]:
        return {
            "mode": self.mode,
            "primary_unit": self.primary_unit,
            "base_unit": self.base_unit,
            "weight_per_primary": float(self.weight_per_primary)
            if self.weight_per_primary is not None
            else None,
            "pieces_per_box": float(self.pieces_per_box)
            if self.pieces_per_box is not None
            else None,
            "liters_per_tin": float(self.liters_per_tin)
            if self.liters_per_tin is not None
            else None,
            "allowed_line_units": sorted(self.allowed_line_units),
        }


def _dec(x: Any) -> Decimal | None:
    if x is None:
        return None
    v = Decimal(str(x))
    return v if v > 0 else None


def _kg_from_name(name: str | None) -> Decimal | None:
    if not name:
        return None
    m = _KG_TOKEN.search(name)
    if not m:
        return None
    try:
        v = Decimal(m.group(1))
    except Exception:
        return None
    return v if v > 0 else None


def suggest_mode_from_name(
    item_name: str,
    *,
    category_name: str | None = None,
) -> str | None:
    """
  Suggest packaging mode from name — never auto-map 5KG/10KG to wholesale bag.

  Returns: wholesale_bag | retail_packet | loose_kg | box | tin | piece | None
  """
    upper = (item_name or "").upper()
    cat = (category_name or "").upper()
    if "LOOSE" in upper:
        return "loose_kg"
    if _BAG_WORDS.search(upper):
        return "wholesale_bag"
    if "TIN" in upper or re.search(r"\d+\s*LTR", upper):
        return "tin"
    if "BOX" in upper or "CTN" in upper or "CARTON" in upper:
        return "box"
    kg = _kg_from_name(upper)
    if kg is not None:
        kg_i = int(kg) if kg == kg.to_integral_value() else None
        if kg_i in _WHOLESALE_KG:
            if any(tok in cat for tok in _BULK_CATEGORIES) and kg_i >= 25:
                return "wholesale_bag"
            return "wholesale_bag" if kg_i >= 25 else "retail_packet"
        if kg_i in _RETAIL_KG or (kg is not None and kg <= Decimal("10")):
            return "retail_packet"
    if re.search(r"\d+\s*GM\b", upper):
        return "retail_packet"
    return None


def profile_from_catalog_item(item: Any) -> StockTrackingProfile:
    """Build profile from persisted catalog row (default_unit is SSOT)."""
    du = (getattr(item, "default_unit", None) or "piece").strip().lower()
    pt = (getattr(item, "package_type", None) or "").strip().upper()
    kpb = _dec(getattr(item, "default_kg_per_bag", None))
    ipb = _dec(getattr(item, "default_items_per_box", None))
    wpt = _dec(getattr(item, "default_weight_per_tin", None))
    psize = _dec(getattr(item, "package_size", None))
    pmeas = (getattr(item, "package_measurement", None) or "").strip().upper()

    if pt in ("LOOSE", "LOOSE_KG") or du == "kg":
        return StockTrackingProfile(
            mode="loose_kg",
            primary_unit="kg",
            base_unit="kg",
            allowed_line_units=frozenset({"kg", "other"}),
        )

    # Owner-set default_unit wins over legacy smart package_type (e.g. 400GM BOX rows).
    if du == "box":
        return StockTrackingProfile(
            mode="box",
            primary_unit="box",
            base_unit="box",
            pieces_per_box=ipb or Decimal("1"),
            allowed_line_units=frozenset({"box", "other"}),
        )

    # Retail single-unit boxes (e.g. "400GM BOX") — treat as box even if default_unit still piece.
    item_name = getattr(item, "name", None)
    if du not in ("bag", "kg", "tin") and (
        pt == "BOX" or _name_looks_like_retail_box(item_name)
    ):
        return StockTrackingProfile(
            mode="box",
            primary_unit="box",
            base_unit="box",
            pieces_per_box=ipb or Decimal("1"),
            allowed_line_units=frozenset({"box", "other"}),
        )

    if du == "tin":
        return StockTrackingProfile(
            mode="tin",
            primary_unit="tin",
            base_unit="tin",
            liters_per_tin=wpt or psize,
            allowed_line_units=frozenset({"tin", "kg", "other"}),
        )

    if du == "bag" or pt in ("SACK", "WHOLESALE_BAG", "BAG"):
        w = kpb or psize or parse_kg_per_bag_from_name(getattr(item, "name", None))
        return StockTrackingProfile(
            mode="wholesale_bag",
            primary_unit="bag",
            base_unit="kg",
            weight_per_primary=w,
            allowed_line_units=frozenset({"bag", "kg", "other"}),
        )

    if pt in ("RETAIL_PACKET", "PACKET", "PKT") or (
        du == "piece" and (kpb or (psize and pmeas == "KG"))
    ):
        w = kpb or psize or _kg_from_name(getattr(item, "name", None))
        return StockTrackingProfile(
            mode="retail_packet",
            primary_unit="piece",
            base_unit="kg",
            weight_per_primary=w,
            allowed_line_units=frozenset({"piece", "pcs", "kg", "other"}),
        )

    if pt == "BOX":
        return StockTrackingProfile(
            mode="box",
            primary_unit="box",
            base_unit="box",
            pieces_per_box=ipb or Decimal("1"),
            allowed_line_units=frozenset({"box", "other"}),
        )

    if pt == "TIN":
        return StockTrackingProfile(
            mode="tin",
            primary_unit="tin",
            base_unit="tin",
            liters_per_tin=wpt or psize,
            allowed_line_units=frozenset({"tin", "kg", "other"}),
        )

    return StockTrackingProfile(
        mode="piece",
        primary_unit=du if du else "piece",
        base_unit=du if du else "piece",
        weight_per_primary=kpb,
        allowed_line_units=frozenset({du, "piece", "pcs", "other"}),
    )


def line_unit_allowed(profile: StockTrackingProfile, line_unit: str | None) -> tuple[bool, str | None]:
    """Return (ok, user_message)."""
    lt = derive_trade_unit_type(line_unit)
    if lt in profile.allowed_line_units:
        return True, None
  # Strict blocks
    if profile.mode == "retail_packet" and lt == "bag":
        return False, "This item uses PIECE tracking (retail packet). Use piece or kg, not bag."
    if profile.mode == "wholesale_bag" and lt in ("pcs", "other") and line_unit:
        lu = (line_unit or "").strip().lower()
        if lu in ("piece", "pieces", "pcs", "pkt", "packet"):
            return False, "This item uses BAG tracking (wholesale). Use bag or kg, not piece."
    if profile.mode == "loose_kg" and lt == "bag":
        return False, "This item is loose KG. Enter quantity in kg only."
    if profile.mode == "box" and lt not in ("box", "other"):
        return False, "This item uses BOX tracking only."
    if profile.mode == "tin" and lt not in ("tin", "kg", "other"):
        return False, "This item uses TIN tracking only."
    return True, None
