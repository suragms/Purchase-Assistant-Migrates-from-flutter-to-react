"""Delivery pipeline: staff verify then owner commit-stock; commit is idempotent."""

import uuid
from decimal import Decimal

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def _register_owner():
    u = uuid.uuid4().hex[:8]
    email = f"dp{u}@test.hexa.local"
    r = client.post(
        "/v1/auth/register",
        json={"username": f"dp{u}", "email": email, "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    h = {"Authorization": f"Bearer {r.json()['access_token']}"}
    bid = client.get("/v1/me/businesses", headers=h).json()[0]["id"]
    return h, bid


def _create_purchase(h, bid, iid, sup, qty: str = "10"):
    purchase = client.post(
        f"/v1/businesses/{bid}/trade-purchases",
        headers=h,
        json={
            "supplier_id": sup,
            "purchase_date": "2026-05-18",
            "status": "confirmed",
            "lines": [
                {
                    "catalog_item_id": iid,
                    "item_name": "Pipeline Item",
                    "qty": qty,
                    "unit": "piece",
                    "purchase_rate": "100",
                    "landing_cost": "100",
                }
            ],
        },
    )
    assert purchase.status_code in (200, 201), purchase.text
    return purchase.json()


def _setup_item(h, bid):
    cat = client.post(
        f"/v1/businesses/{bid}/item-categories", headers=h, json={"name": "CatDP"}
    ).json()["id"]
    sup = client.post(
        f"/v1/businesses/{bid}/suppliers",
        headers=h,
        json={"name": "SupDP", "phone": "9000000199", "gst_number": "22AAAAA0000A1Z5"},
    ).json()["id"]
    item = client.post(
        f"/v1/businesses/{bid}/catalog-items",
        headers=h,
        json={
            "category_id": cat,
            "name": "Pipeline Soap",
            "default_unit": "piece",
            "default_supplier_ids": [sup],
        },
    )
    assert item.status_code == 201, item.text
    return item.json()["id"], sup


def _arrive_and_verify(h, bid, pid, line_id: str, qty: str = "10"):
    arr = client.post(
        f"/v1/businesses/{bid}/trade-purchases/{pid}/arrive",
        headers=h,
        json={},
    )
    assert arr.status_code == 200, arr.text
    assert arr.json()["delivery_status"] == "arrived"
    ver = client.post(
        f"/v1/businesses/{bid}/trade-purchases/{pid}/verify",
        headers=h,
        json={
            "lines": [
                {
                    "line_id": line_id,
                    "received_qty": qty,
                    "damaged_qty": "0",
                    "return_qty": "0",
                }
            ],
        },
    )
    assert ver.status_code == 200, ver.text
    status = ver.json()["delivery_status"]
    assert status in ("staff_verified", "partial", "stock_committed")
    return ver.json()


def _commit_stock(h, bid, pid):
    r = client.post(
        f"/v1/businesses/{bid}/trade-purchases/{pid}/commit-stock",
        headers=h,
    )
    assert r.status_code == 200, r.text
    assert r.json()["delivery_status"] == "stock_committed"
    return r.json()


def test_verify_auto_commits_stock_when_units_ready():
    h, bid = _register_owner()
    iid, sup = _setup_item(h, bid)
    p = _create_purchase(h, bid, iid, sup)
    pid, line_id = p["id"], p["lines"][0]["id"]

    stock0 = client.get(f"/v1/businesses/{bid}/stock/{iid}", headers=h)
    assert Decimal(str(stock0.json()["current_stock"])) == Decimal("0")

    body = _arrive_and_verify(h, bid, pid, line_id)
    assert body["delivery_status"] == "stock_committed"

    stock1 = client.get(f"/v1/businesses/{bid}/stock/{iid}", headers=h)
    assert Decimal(str(stock1.json()["current_stock"])) == Decimal("10")


def test_verify_does_not_commit_stock_until_owner_commit():
    """Legacy name kept — verify now auto-commits when units are configured."""
    test_verify_auto_commits_stock_when_units_ready()


def test_commit_stock_increments_once():
    h, bid = _register_owner()
    iid, sup = _setup_item(h, bid)
    p = _create_purchase(h, bid, iid, sup)
    pid, line_id = p["id"], p["lines"][0]["id"]
    body = _arrive_and_verify(h, bid, pid, line_id)
    assert body["delivery_status"] == "stock_committed"

    stock0 = client.get(f"/v1/businesses/{bid}/stock/{iid}", headers=h)
    assert Decimal(str(stock0.json()["current_stock"])) == Decimal("10")

    c2 = client.post(
        f"/v1/businesses/{bid}/trade-purchases/{pid}/commit-stock",
        headers=h,
    )
    assert c2.status_code == 200, c2.text
    assert (c2.json().get("stock_updates") or []) == []

    stock = client.get(f"/v1/businesses/{bid}/stock/{iid}", headers=h)
    assert Decimal(str(stock.json()["current_stock"])) == Decimal("10")


def test_patch_deliver_true_rejected():
    h, bid = _register_owner()
    iid, sup = _setup_item(h, bid)
    p = _create_purchase(h, bid, iid, sup)
    pid = p["id"]
    r = client.patch(
        f"/v1/businesses/{bid}/trade-purchases/{pid}/delivery",
        headers=h,
        json={"is_delivered": True},
    )
    assert r.status_code == 400, r.text


def _staff_headers(owner_h, bid):
    suffix = uuid.uuid4().hex[:8]
    phone_digits = "".join(c for c in suffix if c.isdigit())
    if len(phone_digits) < 8:
        phone_digits = f"{int(suffix[:8], 16) % 100000000:08d}"
    phone = f"98{phone_digits[:8]}"
    staff_email = f"stfdp{suffix}@test.hexa.local"
    cr = client.post(
        f"/v1/businesses/{bid}/users",
        headers=owner_h,
        json={
            "full_name": "Staff DP",
            "phone": phone,
            "email": staff_email,
            "role": "staff",
        },
    )
    assert cr.status_code == 201, cr.text
    pw = cr.json()["generated_password"]
    login = client.post(
        "/v1/auth/login",
        json={"email": staff_email, "password": pw},
    )
    assert login.status_code == 200, login.text
    return {"Authorization": f"Bearer {login.json()['access_token']}"}


def test_staff_cannot_commit_stock_before_verify():
    owner_h, bid = _register_owner()
    staff_h = _staff_headers(owner_h, bid)
    iid, sup = _setup_item(owner_h, bid)
    p = _create_purchase(owner_h, bid, iid, sup)
    pid = p["id"]
    client.post(
        f"/v1/businesses/{bid}/trade-purchases/{pid}/arrive",
        headers=staff_h,
        json={},
    )
    r = client.post(
        f"/v1/businesses/{bid}/trade-purchases/{pid}/commit-stock",
        headers=staff_h,
    )
    assert r.status_code in (400, 403), r.text


def test_verify_records_received_qty_before_commit():
    """Partial verify keeps stock at zero until owner commit."""
    h, bid = _register_owner()
    iid, sup = _setup_item(h, bid)
    p = _create_purchase(h, bid, iid, sup, qty="10")
    pid, line_id = p["id"], p["lines"][0]["id"]
    client.post(
        f"/v1/businesses/{bid}/trade-purchases/{pid}/arrive",
        headers=h,
        json={},
    )
    ver = client.post(
        f"/v1/businesses/{bid}/trade-purchases/{pid}/verify",
        headers=h,
        json={
            "lines": [
                {
                    "line_id": line_id,
                    "received_qty": "7",
                    "damaged_qty": "0",
                    "return_qty": "0",
                }
            ]
        },
    )
    assert ver.status_code == 200, ver.text
    assert ver.json()["delivery_status"] == "partial"
    stock = client.get(f"/v1/businesses/{bid}/stock/{iid}", headers=h)
    assert Decimal(str(stock.json()["current_stock"])) == Decimal("0")

    _commit_stock(h, bid, pid)
    stock = client.get(f"/v1/businesses/{bid}/stock/{iid}", headers=h)
    assert Decimal(str(stock.json()["current_stock"])) == Decimal("7")


def test_staff_verify_then_owner_commit_adds_stock():
    owner_h, bid = _register_owner()
    staff_h = _staff_headers(owner_h, bid)
    iid, sup = _setup_item(owner_h, bid)
    p = _create_purchase(owner_h, bid, iid, sup)
    pid, line_id = p["id"], p["lines"][0]["id"]
    client.post(
        f"/v1/businesses/{bid}/trade-purchases/{pid}/arrive",
        headers=staff_h,
        json={},
    )
    ver = client.post(
        f"/v1/businesses/{bid}/trade-purchases/{pid}/verify",
        headers=staff_h,
        json={
            "lines": [
                {
                    "line_id": line_id,
                    "received_qty": "10",
                    "damaged_qty": "0",
                    "return_qty": "0",
                }
            ]
        },
    )
    assert ver.status_code == 200, ver.text
    assert ver.json()["delivery_status"] == "stock_committed"
    stock = client.get(f"/v1/businesses/{bid}/stock/{iid}", headers=owner_h)
    assert Decimal(str(stock.json()["current_stock"])) == Decimal("10")

    c2 = client.post(
        f"/v1/businesses/{bid}/trade-purchases/{pid}/commit-stock",
        headers=owner_h,
    )
    assert c2.status_code == 200, c2.text
    assert (c2.json().get("stock_updates") or []) == []
    stock = client.get(f"/v1/businesses/{bid}/stock/{iid}", headers=owner_h)
    assert Decimal(str(stock.json()["current_stock"])) == Decimal("10")


def test_staff_verify_notifies_owner():
    owner_h, bid = _register_owner()
    staff_h = _staff_headers(owner_h, bid)
    iid, sup = _setup_item(owner_h, bid)
    p = _create_purchase(owner_h, bid, iid, sup)
    pid, line_id = p["id"], p["lines"][0]["id"]
    client.post(
        f"/v1/businesses/{bid}/trade-purchases/{pid}/arrive",
        headers=staff_h,
        json={},
    )
    ver = client.post(
        f"/v1/businesses/{bid}/trade-purchases/{pid}/verify",
        headers=staff_h,
        json={
            "lines": [
                {
                    "line_id": line_id,
                    "received_qty": "10",
                    "damaged_qty": "0",
                    "return_qty": "0",
                }
            ]
        },
    )
    assert ver.status_code == 200, ver.text
    listed = client.get(f"/v1/businesses/{bid}/notifications", headers=owner_h)
    assert listed.status_code == 200, listed.text
    kinds = {row.get("kind") for row in listed.json()}
    assert "delivery_verified" in kinds or "stock_committed" in kinds


def test_dispatch_and_pipeline_counts():
    h, bid = _register_owner()
    iid, sup = _setup_item(h, bid)
    p = _create_purchase(h, bid, iid, sup)
    pid = p["id"]
    d = client.post(
        f"/v1/businesses/{bid}/trade-purchases/{pid}/dispatch",
        headers=h,
        json={"truck_number": "KL-07-1234"},
    )
    assert d.status_code == 200, d.text
    assert d.json()["delivery_status"] == "dispatched"
    pipe = client.get(
        f"/v1/businesses/{bid}/trade-purchases/delivery-pipeline",
        headers=h,
    )
    assert pipe.status_code == 200, pipe.text
    assert pipe.json()["dispatched"] >= 1

    listed = client.get(
        f"/v1/businesses/{bid}/trade-purchases",
        headers=h,
        params={"status": "dispatched", "limit": 50},
    )
    assert listed.status_code == 200, listed.text
    ids = {row["id"] for row in listed.json()}
    assert pid in ids

    other = client.get(
        f"/v1/businesses/{bid}/trade-purchases",
        headers=h,
        params={"status": "arrived", "limit": 50},
    )
    assert other.status_code == 200, other.text
    assert pid not in {row["id"] for row in other.json()}
