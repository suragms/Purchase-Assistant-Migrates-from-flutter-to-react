"""Barcode vs item_code: from-scan create, lookup, patch."""

import uuid

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def _owner_headers():
    u = uuid.uuid4().hex[:10]
    email = f"bc{u}@test.hexa.local"
    r = client.post(
        "/v1/auth/register",
        json={"username": f"u{u}", "email": email, "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    h = {"Authorization": f"Bearer {r.json()['access_token']}"}
    bid = client.get("/v1/me/businesses", headers=h).json()[0]["id"]
    return h, bid


def _type_id(h, bid):
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
    return types.json()[0]["id"]


def test_from_scan_create_and_lookup():
    h, bid = _owner_headers()
    tid = _type_id(h, bid)
    body = {
        "barcode": "8901234567890",
        "item_code": "RICE-PONNI-50KG",
        "name": "Rice Ponni Test",
        "type_id": tid,
        "default_unit": "bag",
        "default_kg_per_bag": 50,
    }
    created = client.post(
        f"/v1/businesses/{bid}/catalog-items/from-scan",
        headers=h,
        json=body,
    )
    assert created.status_code == 201, created.text
    data = created.json()
    assert data["barcode"] == "8901234567890"
    assert data["item_code"] == "RICE-PONNI-50KG"

    lookup = client.get(
        f"/v1/businesses/{bid}/stock/barcode/lookup",
        headers=h,
        params={"code": "8901234567890"},
    )
    assert lookup.status_code == 200, lookup.text
    assert lookup.json()["item_code"] == "RICE-PONNI-50KG"

    dup = client.post(
        f"/v1/businesses/{bid}/catalog-items/from-scan",
        headers=h,
        json={**body, "name": "Other Name"},
    )
    assert dup.status_code == 409


def test_patch_item_code():
    h, bid = _owner_headers()
    tid = _type_id(h, bid)
    created = client.post(
        f"/v1/businesses/{bid}/catalog-items/from-scan",
        headers=h,
        json={
            "barcode": "890111222333",
            "item_code": "OIL-COCO-1L",
            "name": "Coconut Oil",
            "type_id": tid,
            "default_unit": "kg",
        },
    )
    assert created.status_code == 201
    iid = created.json()["id"]
    patched = client.patch(
        f"/v1/businesses/{bid}/catalog-items/{iid}/item-code",
        headers=h,
        json={"item_code": "OIL-COCO-2L"},
    )
    assert patched.status_code == 200, patched.text
    assert patched.json()["item_code"] == "OIL-COCO-2L"
