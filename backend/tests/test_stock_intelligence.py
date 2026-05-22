"""Stock list period fields and per-item intelligence endpoint."""

import uuid
from datetime import date, timedelta

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def _owner_headers():
    u = uuid.uuid4().hex[:10]
    email = f"si{u}@test.hexa.local"
    r = client.post(
        "/v1/auth/register",
        json={"username": f"u{u}", "email": email, "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    h = {"Authorization": f"Bearer {r.json()['access_token']}"}
    bid = client.get("/v1/me/businesses", headers=h).json()[0]["id"]
    return h, bid


def _supplier_id(h, bid):
    r = client.post(
        f"/v1/businesses/{bid}/suppliers",
        headers=h,
        json={"name": f"Sup{uuid.uuid4().hex[:6]}"},
    )
    assert r.status_code in (200, 201), r.text
    return r.json()["id"]


def _catalog_item_id(h, bid, *, name: str = "Intel rice") -> str:
    sid = _supplier_id(h, bid)
    cat = client.post(
        f"/v1/businesses/{bid}/item-categories",
        headers=h,
        json={"name": f"Cat{uuid.uuid4().hex[:6]}"},
    )
    assert cat.status_code == 201, cat.text
    cid = cat.json()["id"]
    types = client.get(
        f"/v1/businesses/{bid}/item-categories/{cid}/category-types",
        headers=h,
    )
    assert types.status_code == 200, types.text
    tid = types.json()[0]["id"]
    item = client.post(
        f"/v1/businesses/{bid}/catalog-items",
        headers=h,
        json={
            "category_id": cid,
            "type_id": tid,
            "name": name,
            "default_unit": "bag",
            "default_kg_per_bag": 50,
            "default_supplier_ids": [sid],
            "current_stock": 10,
            "reorder_level": 2,
        },
    )
    assert item.status_code == 201, item.text
    return item.json()["id"]


def test_stock_list_include_period_fields():
    h, bid = _owner_headers()
    iid = _catalog_item_id(h, bid)
    today = date.today()
    start = (today - timedelta(days=30)).isoformat()
    end = today.isoformat()
    r = client.get(
        f"/v1/businesses/{bid}/stock/list",
        headers=h,
        params={
            "include_period": True,
            "period_start": start,
            "period_end": end,
            "per_page": 50,
        },
    )
    assert r.status_code == 200, r.text
    rows = r.json()["items"]
    hit = next((x for x in rows if x["id"] == iid), None)
    assert hit is not None
    assert "period_purchased_qty" in hit
    assert "period_variance_qty" in hit
    assert "needs_verification" in hit


def test_stock_intelligence_endpoint():
    h, bid = _owner_headers()
    iid = _catalog_item_id(h, bid)
    today = date.today()
    start = (today - timedelta(days=30)).isoformat()
    end = today.isoformat()
    r = client.get(
        f"/v1/businesses/{bid}/stock/{iid}/intelligence",
        headers=h,
        params={"period_start": start, "period_end": end},
    )
    assert r.status_code == 200, r.text
    data = r.json()
    assert data["id"] == iid
    assert float(data["current_stock"]) >= 0
    assert "period_purchased_qty" in data
    assert "recent_purchases" in data
