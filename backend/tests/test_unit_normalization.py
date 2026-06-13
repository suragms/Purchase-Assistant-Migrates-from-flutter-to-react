"""Unit normalization for mixed bag/kg purchase lines."""

import uuid
from decimal import Decimal
from types import SimpleNamespace

import pytest

from app.services.unit_normalization import line_qty_in_stock_unit


def _item(*, unit="bag", kg_per_bag=50, name="SUGAR 50 KG"):
    return SimpleNamespace(
        id=uuid.uuid4(),
        stock_unit=unit,
        default_unit=unit,
        default_kg_per_bag=Decimal(str(kg_per_bag)),
        conversion_factor=None,
        name=name,
    )


def _line(*, qty, unit, total_weight=None, kg_per_unit=None):
    return SimpleNamespace(
        qty=Decimal(str(qty)),
        unit=unit,
        total_weight=Decimal(str(total_weight)) if total_weight is not None else None,
        kg_per_unit=Decimal(str(kg_per_unit)) if kg_per_unit is not None else None,
        weight_per_unit=None,
        qty_in_stock_unit=None,
        item_name="SUGAR 50 KG",
    )


def test_bag_line_stays_bags():
    item = _item()
    assert line_qty_in_stock_unit(_line(qty=100, unit="bag"), item) == Decimal("100.000")


def test_kg_line_converts_to_bags():
    item = _item()
    assert line_qty_in_stock_unit(_line(qty=5000, unit="kg"), item) == Decimal("100.000")


def test_mixed_period_sum_equivalent():
    item = _item()
    bag = line_qty_in_stock_unit(_line(qty=100, unit="bag"), item)
    kg = line_qty_in_stock_unit(_line(qty=5000, unit="kg"), item)
    assert bag + kg == Decimal("200.000")


def test_uses_persisted_snapshot():
    item = _item()
    line = _line(qty=5000, unit="kg")
    line.qty_in_stock_unit = Decimal("99")
    assert line_qty_in_stock_unit(line, item) == Decimal("99.000")


def test_zero_snapshot_falls_through_to_conversion():
    item = _item()
    line = _line(qty=5000, unit="kg")
    line.qty_in_stock_unit = Decimal("0")
    assert line_qty_in_stock_unit(line, item) == Decimal("100.000")
