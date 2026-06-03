"""Stock saves must not 409 when activity log uses extended action_type codes."""

import uuid
from decimal import Decimal

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def _owner_headers():
    u = uuid.uuid4().hex[:10]
    email = f"act{u}@test.hexa.local"
    r = client.post(
        "/v1/auth/register",
        json={"username": f"u{u}", "email": email, "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    h = {"Authorization": f"Bearer {r.json()['access_token']}"}
    bid = client.get("/v1/me/businesses", headers=h).json()[0]["id"]
    return h, bid


def _catalog_item(h, bid) -> str:
    sid_r = client.post(
        f"/v1/businesses/{bid}/suppliers",
        headers=h,
        json={"name": f"Sup{uuid.uuid4().hex[:6]}"},
    )
    assert sid_r.status_code in (200, 201), sid_r.text
    sid = sid_r.json()["id"]
    cat = client.post(
        f"/v1/businesses/{bid}/item-categories",
        headers=h,
        json={"name": f"Cat{uuid.uuid4().hex[:6]}"},
    )
    assert cat.status_code == 201, cat.text
    cid = cat.json()["id"]
    item = client.post(
        f"/v1/businesses/{bid}/catalog-items",
        headers=h,
        json={
            "category_id": cid,
            "name": f"Sugar {uuid.uuid4().hex[:4]}",
            "default_unit": "bag",
            "default_kg_per_bag": 50,
            "default_supplier_ids": [sid],
        },
    )
    assert item.status_code == 201, item.text
    iid = item.json()["id"]
    seed = client.patch(
        f"/v1/businesses/{bid}/stock/{iid}",
        headers=h,
        json={"new_qty": 100, "adjustment_type": "correction", "reason": "seed"},
    )
    assert seed.status_code == 200, seed.text
    return iid


def test_physical_count_succeeds_with_physical_stock_count_action():
    h, bid = _owner_headers()
    iid = _catalog_item(h, bid)
    rec = client.post(
        f"/v1/businesses/{bid}/stock/{iid}/physical-count",
        headers=h,
        json={"counted_qty": 95, "notes": "floor count"},
    )
    assert rec.status_code == 200, rec.text
    assert Decimal(str(rec.json()["counted_qty"])) == Decimal("95")


def test_patch_correction_succeeds_with_stock_correction_recorded_action():
    h, bid = _owner_headers()
    iid = _catalog_item(h, bid)
    detail = client.get(f"/v1/businesses/{bid}/stock/{iid}", headers=h)
    assert detail.status_code == 200
    ver = detail.json().get("stock_version")
    patch = client.patch(
        f"/v1/businesses/{bid}/stock/{iid}",
        headers=h,
        json={
            "new_qty": 111,
            "adjustment_type": "correction",
            "reason": "test correction",
            "last_seen_stock_version": ver,
        },
    )
    assert patch.status_code == 200, patch.text
    assert Decimal(str(patch.json()["current_stock"])) == Decimal("111")
