"""Validate purchase line units against catalog stock-tracking profile."""

from __future__ import annotations

from typing import Any

from app.models.catalog import CatalogItem
from app.services.stock_tracking_profile import line_unit_allowed, profile_from_catalog_item


def validate_purchase_line_unit(
    item: CatalogItem | Any,
    line_unit: str | None,
) -> str | None:
    """Return error message when unit is not allowed; None when OK."""
    profile = profile_from_catalog_item(item)
    ok, msg = line_unit_allowed(profile, line_unit)
    if ok:
        return None
    item_name = (getattr(item, "name", None) or "item").strip()
    unit = (line_unit or "").strip().upper() or "UNKNOWN"
    stock_unit = (
        getattr(item, "stock_unit", None)
        or getattr(item, "default_unit", None)
        or getattr(item, "selling_unit", None)
        or ""
    )
    stock_unit = stock_unit.strip().upper() or "UNKNOWN"
    return (
        msg
        or f"Unit mismatch for {item_name}: {unit} is incompatible with stock unit {stock_unit}. "
        "Add/verify conversion factor before saving."
    )
