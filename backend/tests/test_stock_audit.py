import uuid
from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)


def _setup_auth_and_item():
    u = uuid.uuid4().hex[:10]
    email = f"e{u}@test.hexa.local"
    r = client.post(
        "/v1/auth/register",
        json={"username": f"u{u}", "email": email, "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    access = r.json()["access_token"]
    h = {"Authorization": f"Bearer {access}"}

    br = client.get("/v1/me/businesses", headers=h)
    assert br.status_code == 200, br.text
    bid = br.json()[0]["id"]

    cat = client.post(
        f"/v1/businesses/{bid}/item-categories",
        headers=h,
        json={"name": "Test Cat"},
    )
    assert cat.status_code == 201, cat.text
    cid = cat.json()["id"]

    def_sup = client.post(
        f"/v1/businesses/{bid}/suppliers",
        headers=h,
        json={"name": "Item default sup", "phone": "9000000099", "gst_number": "22AAAAA0000A1Z5"},
    )
    assert def_sup.status_code == 201, def_sup.text
    def_sid = def_sup.json()["id"]

    item = client.post(
        f"/v1/businesses/{bid}/catalog-items",
        headers=h,
        json={
            "category_id": cid,
            "name": "Audit Test Rice",
            "default_unit": "kg",
            "default_supplier_ids": [def_sid],
        },
    )
    assert item.status_code == 201, item.text
    iid = item.json()["id"]

    patch = client.patch(
        f"/v1/businesses/{bid}/stock/{iid}",
        headers=h,
        json={"new_qty": 100, "adjustment_type": "manual", "reason": "seed"},
    )
    assert patch.status_code == 200, patch.text

    return h, bid, iid


def test_stock_audit_lifecycle_and_complete_applies_stock():
    h, bid, iid = _setup_auth_and_item()
    base = f"/v1/businesses/{bid}/stock-audits"

    r_create = client.post(
        base,
        headers=h,
        json={"notes": "Initial draft audit", "items": []},
    )
    assert r_create.status_code == 201, r_create.text
    audit = r_create.json()
    audit_id = audit["id"]
    assert audit["status"] == "draft"
    assert audit["business_id"] == bid

    r_line = client.post(
        f"{base}/{audit_id}/lines",
        headers=h,
        json={
            "item_id": iid,
            "counted_qty": 99,
            "adjustment_type": "verification",
            "reason": "Physical count",
        },
    )
    assert r_line.status_code == 200, r_line.text
    line = r_line.json()["items"][0]
    assert float(line["system_qty"]) == 100.0
    assert float(line["counted_qty"]) == 99.0
    assert float(line["difference_qty"]) == 1.0

    r_complete = client.post(f"{base}/{audit_id}/complete", headers=h)
    assert r_complete.status_code == 200, r_complete.text
    assert r_complete.json()["status"] == "completed"

    stock = client.get(f"/v1/businesses/{bid}/stock/{iid}", headers=h)
    assert stock.status_code == 200, stock.text
    assert float(stock.json()["current_stock"]) == 99.0

    r_fail = client.put(
        f"{base}/{audit_id}",
        headers=h,
        json={"notes": "blocked"},
    )
    assert r_fail.status_code == 400


def test_verify_count_endpoint():
    h, bid, iid = _setup_auth_and_item()

    r = client.post(
        f"/v1/businesses/{bid}/stock/{iid}/verify-count",
        headers=h,
        json={
            "counted_qty": 88,
            "adjustment_type": "verification",
            "reason": "Scan count",
        },
    )
    assert r.status_code == 200, r.text
    assert float(r.json()["current_stock"]) == 88
