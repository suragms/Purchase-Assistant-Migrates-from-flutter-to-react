"""Stock list warehouse columns: purchased + diff + physical snapshot."""

import uuid
from datetime import date, timedelta
from decimal import Decimal

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def _owner_headers():
    suffix = uuid.uuid4().hex[:10]
    email = f"stockcols{suffix}@test.hexa.local"
    r = client.post(
        "/v1/auth/register",
        json={"username": f"sc{suffix}", "email": email, "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    h = {"Authorization": f"Bearer {r.json()['access_token']}"}
    bid = client.get("/v1/me/businesses", headers=h).json()[0]["id"]
    return h, bid


def _supplier_id(h, bid) -> str:
    r = client.post(
        f"/v1/businesses/{bid}/suppliers",
        headers=h,
        json={"name": f"Col Supplier {uuid.uuid4().hex[:6]}", "phone": "9876501234"},
    )
    assert r.status_code == 201, r.text
    return r.json()["id"]


def _catalog_item_id(h, bid, *, current_stock: int = 100) -> str:
    sid = _supplier_id(h, bid)
    cat = client.post(
        f"/v1/businesses/{bid}/item-categories",
        headers=h,
        json={"name": f"Col Cat {uuid.uuid4().hex[:6]}"},
    )
    assert cat.status_code == 201, cat.text
    cid = cat.json()["id"]
    types = client.get(
        f"/v1/businesses/{bid}/item-categories/{cid}/category-types",
        headers=h,
    )
    tid = types.json()[0]["id"]
    item = client.post(
        f"/v1/businesses/{bid}/catalog-items",
        headers=h,
        json={
            "category_id": cid,
            "type_id": tid,
            "name": f"Col Item {uuid.uuid4().hex[:4]}",
            "default_unit": "bag",
            "stock_unit": "bag",
            "default_kg_per_bag": 50,
            "default_supplier_ids": [sid],
            "current_stock": current_stock,
            "reorder_level": 2,
        },
    )
    assert item.status_code == 201, item.text
    return item.json()["id"], sid


def test_physical_update_sets_physical_qty_and_warehouse_diff():
    h, bid = _owner_headers()
    iid, sid = _catalog_item_id(h, bid, current_stock=100)
    today = date.today().isoformat()

    quick = client.post(
        f"/v1/businesses/{bid}/stock/{iid}/quick-purchase",
        headers=h,
        json={"qty": 30, "supplier_id": sid, "notes": "morning receipt"},
    )
    assert quick.status_code == 200, quick.text

    before = client.get(f"/v1/businesses/{bid}/stock/{iid}", headers=h)
    assert before.status_code == 200

    physical = client.post(
        f"/v1/businesses/{bid}/stock/{iid}/physical-update",
        headers=h,
        json={
            "counted_qty": 50,
            "adjustment_type": "verification",
            "reason": "Physical count",
            "period_start": today,
            "period_end": today,
            "last_seen_stock_version": before.json()["stock_version"],
        },
    )
    assert physical.status_code == 200, physical.text
    assert Decimal(str(physical.json()["item"]["current_stock"])) == Decimal("50")

    listed = client.get(
        f"/v1/businesses/{bid}/stock/list",
        headers=h,
        params={
            "include_period": True,
            "period_start": today,
            "period_end": today,
            "per_page": 200,
        },
    )
    assert listed.status_code == 200, listed.text
    row = next(i for i in listed.json()["items"] if i["id"] == iid)
    assert Decimal(str(row["physical_stock_qty"])) == Decimal("50")
    assert Decimal(str(row["period_purchased_qty"])) == Decimal("30")
    assert Decimal(str(row["warehouse_diff_qty"])) == Decimal("20")


def test_quick_purchase_included_in_period_purchased():
    h, bid = _owner_headers()
    iid, sid = _catalog_item_id(h, bid, current_stock=10)
    today = date.today().isoformat()

    client.post(
        f"/v1/businesses/{bid}/stock/{iid}/quick-purchase",
        headers=h,
        json={"qty": 15, "supplier_id": sid},
    )

    listed = client.get(
        f"/v1/businesses/{bid}/stock/list",
        headers=h,
        params={
            "include_period": True,
            "period_start": today,
            "period_end": today,
            "per_page": 200,
        },
    )
    row = next(i for i in listed.json()["items"] if i["id"] == iid)
    assert Decimal(str(row["period_purchased_qty"])) == Decimal("15")
