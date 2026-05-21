import uuid

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def _setup_with_items():
    u = uuid.uuid4().hex[:10]
    email = f"inv{u}@test.hexa.local"
    r = client.post(
        "/v1/auth/register",
        json={"username": f"iu{u}", "email": email, "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    h = {"Authorization": f"Bearer {r.json()['access_token']}"}
    bid = client.get("/v1/me/businesses", headers=h).json()[0]["id"]
    cat = client.post(
        f"/v1/businesses/{bid}/item-categories",
        headers=h,
        json={"name": "Spices"},
    ).json()["id"]
    sup = client.post(
        f"/v1/businesses/{bid}/suppliers",
        headers=h,
        json={"name": "S1", "phone": "9000000099", "gst_number": "22AAAAA0000A1Z5"},
    ).json()["id"]
    base = f"/v1/businesses/{bid}/catalog-items"
    bag = client.post(
        base,
        headers=h,
        json={
            "category_id": cat,
            "name": "Rice Bag",
            "default_unit": "bag",
            "default_kg_per_bag": 50,
            "default_landing_cost": 100,
            "default_supplier_ids": [sup],
        },
    )
    assert bag.status_code == 201, bag.text
    bag_id = bag.json()["id"]
    box = client.post(
        base,
        headers=h,
        json={
            "category_id": cat,
            "name": "Masala Box",
            "default_unit": "box",
            "default_items_per_box": 12,
            "default_landing_cost": 50,
            "default_supplier_ids": [sup],
        },
    )
    assert box.status_code == 201, box.text
    box_id = box.json()["id"]
    loose = client.post(
        base,
        headers=h,
        json={
            "category_id": cat,
            "name": "Loose KG",
            "default_unit": "kg",
            "default_supplier_ids": [sup],
        },
    )
    assert loose.status_code == 201, loose.text
    loose_id = loose.json()["id"]
    stock_base = f"/v1/businesses/{bid}/stock"
    for iid, qty in ((bag_id, 10), (box_id, 2), (loose_id, 5)):
        patch = client.patch(
            f"{stock_base}/{iid}",
            headers=h,
            json={"new_qty": qty, "adjustment_type": "verification"},
        )
        assert patch.status_code == 200, patch.text
        assert float(patch.json()["current_stock"]) == float(qty)
    return h, bid


def test_inventory_summary_empty_catalog():
    u = uuid.uuid4().hex[:10]
    r = client.post(
        "/v1/auth/register",
        json={"username": f"ie{u}", "email": f"ie{u}@t.local", "password": "testpass12"},
    )
    assert r.status_code == 200
    h = {"Authorization": f"Bearer {r.json()['access_token']}"}
    bid = client.get("/v1/me/businesses", headers=h).json()[0]["id"]
    res = client.get(
        f"/v1/businesses/{bid}/stock/inventory-summary",
        headers=h,
    )
    assert res.status_code == 200, res.text
    body = res.json()
    assert body["total_value_inr"] == 0.0
    assert body["item_count"] == 0


def test_inventory_summary_mixed_units_and_value():
    h, bid = _setup_with_items()
    res = client.get(
        f"/v1/businesses/{bid}/stock/inventory-summary",
        headers=h,
    )
    assert res.status_code == 200, res.text
    body = res.json()
    assert body["item_count"] == 3
    unit_sum = body["bags"] + body["boxes"] + body["tins"] + body["kg"]
    assert unit_sum == 17.0
    # 10*100 + 2*50 + 0 (no landing on loose) = 1100
    assert body["total_value_inr"] == 1100.0
