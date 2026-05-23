"""Stock must revert when a confirmed trade purchase is cancelled."""

import uuid
from decimal import Decimal

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def _register_owner():
    u = uuid.uuid4().hex[:8]
    email = f"rev{u}@test.hexa.local"
    r = client.post(
        "/v1/auth/register",
        json={"username": f"ru{u}", "email": email, "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    h = {"Authorization": f"Bearer {r.json()['access_token']}"}
    bid = client.get("/v1/me/businesses", headers=h).json()[0]["id"]
    return h, bid


def test_cancel_confirmed_purchase_reverts_stock():
    h, bid = _register_owner()
    cat = client.post(
        f"/v1/businesses/{bid}/item-categories", headers=h, json={"name": "Cat"}
    ).json()["id"]
    sup = client.post(
        f"/v1/businesses/{bid}/suppliers",
        headers=h,
        json={"name": "Sup", "phone": "9000000199", "gst_number": "22AAAAA0000A1Z6"},
    ).json()["id"]
    item = client.post(
        f"/v1/businesses/{bid}/catalog-items",
        headers=h,
        json={
            "category_id": cat,
            "name": "Rice Bag",
            "default_unit": "piece",
            "default_supplier_ids": [sup],
        },
    )
    assert item.status_code == 201, item.text
    iid = item.json()["id"]

    purchase = client.post(
        f"/v1/businesses/{bid}/trade-purchases",
        headers=h,
        json={
            "supplier_id": sup,
            "purchase_date": "2026-05-20",
            "status": "confirmed",
            "lines": [
                {
                    "catalog_item_id": iid,
                    "item_name": "Rice Bag",
                    "qty": "10",
                    "unit": "piece",
                    "purchase_rate": "100",
                    "landing_cost": "100",
                }
            ],
        },
    )
    assert purchase.status_code in (200, 201), purchase.text
    pid = purchase.json()["id"]

    stock = client.get(f"/v1/businesses/{bid}/stock/{iid}", headers=h)
    assert Decimal(str(stock.json()["current_stock"])) == Decimal("10")

    cancel = client.post(
        f"/v1/businesses/{bid}/trade-purchases/{pid}/cancel",
        headers=h,
    )
    assert cancel.status_code == 200, cancel.text

    stock2 = client.get(f"/v1/businesses/{bid}/stock/{iid}", headers=h)
    assert Decimal(str(stock2.json()["current_stock"])) == Decimal("0")


def test_edit_confirmed_purchase_adjusts_stock():
    h, bid = _register_owner()
    cat = client.post(
        f"/v1/businesses/{bid}/item-categories", headers=h, json={"name": "Cat2"}
    ).json()["id"]
    sup = client.post(
        f"/v1/businesses/{bid}/suppliers",
        headers=h,
        json={"name": "Sup2", "phone": "9000000299", "gst_number": "22AAAAA0000A1Z7"},
    ).json()["id"]
    item = client.post(
        f"/v1/businesses/{bid}/catalog-items",
        headers=h,
        json={
            "category_id": cat,
            "name": "Dal Bag",
            "default_unit": "piece",
            "default_supplier_ids": [sup],
        },
    )
    assert item.status_code == 201, item.text
    iid = item.json()["id"]

    purchase = client.post(
        f"/v1/businesses/{bid}/trade-purchases",
        headers=h,
        json={
            "supplier_id": sup,
            "purchase_date": "2026-05-21",
            "status": "confirmed",
            "lines": [
                {
                    "catalog_item_id": iid,
                    "item_name": "Dal Bag",
                    "qty": "10",
                    "unit": "piece",
                    "purchase_rate": "50",
                    "landing_cost": "50",
                }
            ],
        },
    )
    assert purchase.status_code in (200, 201), purchase.text
    pid = purchase.json()["id"]

    upd = client.put(
        f"/v1/businesses/{bid}/trade-purchases/{pid}",
        headers=h,
        json={
            "supplier_id": sup,
            "purchase_date": "2026-05-21",
            "status": "confirmed",
            "lines": [
                {
                    "catalog_item_id": iid,
                    "item_name": "Dal Bag",
                    "qty": "8",
                    "unit": "piece",
                    "purchase_rate": "50",
                    "landing_cost": "50",
                }
            ],
        },
    )
    assert upd.status_code == 200, upd.text

    stock = client.get(f"/v1/businesses/{bid}/stock/{iid}", headers=h)
    assert Decimal(str(stock.json()["current_stock"])) == Decimal("8")
