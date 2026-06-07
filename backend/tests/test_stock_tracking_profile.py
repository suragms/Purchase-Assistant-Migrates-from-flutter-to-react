"""Stock tracking profile — retail packet vs wholesale bag."""

import uuid
from decimal import Decimal
from types import SimpleNamespace

from app.services.purchase_line_unit_validation import validate_purchase_line_unit
from app.services.stock_tracking_profile import profile_from_catalog_item, suggest_mode_from_name
from app.services.unit_normalization import line_qty_in_stock_unit


def test_atta_5kg_suggests_retail_packet():
    assert suggest_mode_from_name("ATTA 5 KG") == "retail_packet"
    assert suggest_mode_from_name("SUGAR 50 KG") == "wholesale_bag"


def test_retail_piece_kg_line_converts():
    item = SimpleNamespace(
        id=uuid.uuid4(),
        default_unit="piece",
        package_type="RETAIL_PACKET",
        default_kg_per_bag=Decimal("5"),
        package_size=Decimal("5"),
        package_measurement="KG",
        name="ATTA 5 KG",
    )
    line = SimpleNamespace(qty=Decimal("500"), unit="kg", qty_in_stock_unit=None, item_name="ATTA 5 KG")
    assert line_qty_in_stock_unit(line, item) == Decimal("100.000")


def test_blocks_bag_on_retail_packet():
    item = SimpleNamespace(
        id=uuid.uuid4(),
        default_unit="piece",
        package_type="RETAIL_PACKET",
        default_kg_per_bag=Decimal("5"),
        name="ATTA 5 KG",
    )
    msg = validate_purchase_line_unit(item, "bag")
    assert msg is not None
    assert "PIECE" in msg


def test_wholesale_bag_profile():
    item = SimpleNamespace(
        id=uuid.uuid4(),
        default_unit="bag",
        package_type="SACK",
        default_kg_per_bag=Decimal("50"),
        name="SUGAR 50 KG",
    )
    p = profile_from_catalog_item(item)
    assert p.mode == "wholesale_bag"
    assert p.primary_unit == "bag"


def test_owner_box_unit_overrides_retail_packet_package_type():
    item = SimpleNamespace(
        id=uuid.uuid4(),
        default_unit="box",
        default_items_per_box=Decimal("1"),
        package_type="RETAIL_PACKET",
        package_size=Decimal("400"),
        package_measurement="GM",
        name="SUNRICH 400GM BOX",
    )
    p = profile_from_catalog_item(item)
    assert p.mode == "box"
    assert p.primary_unit == "box"
    assert p.pieces_per_box == Decimal("1")


def test_box_name_overrides_piece_default_unit():
    """Legacy rows: piece + RETAIL_PACKET but name ends with BOX → box profile."""
    item = SimpleNamespace(
        id=uuid.uuid4(),
        default_unit="piece",
        default_items_per_box=None,
        package_type="RETAIL_PACKET",
        package_size=Decimal("400"),
        package_measurement="GM",
        name="SUNRICH 400GM BOX",
    )
    p = profile_from_catalog_item(item)
    assert p.mode == "box"
    assert p.primary_unit == "box"
    line = SimpleNamespace(
        qty=Decimal("1"),
        unit="box",
        qty_in_stock_unit=None,
        item_name="SUNRICH 400GM BOX",
    )
    assert line_qty_in_stock_unit(line, item) == Decimal("1.000")
    assert validate_purchase_line_unit(item, "box") is None
