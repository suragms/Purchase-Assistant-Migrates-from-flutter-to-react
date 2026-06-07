"""Item categories + catalog items CRUD."""

import uuid

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def _auth_and_business():
    u = uuid.uuid4().hex[:10]
    email = f"cat{u}@test.hexa.local"
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
    return h, bid


def test_category_and_item_crud():
    h, bid = _auth_and_business()
    r = client.post(
        f"/v1/businesses/{bid}/item-categories",
        json={"name": "Pulses"},
        headers=h,
    )
    assert r.status_code == 201, r.text
    cid = r.json()["id"]
    r = client.get(
        f"/v1/businesses/{bid}/item-categories/{cid}/category-types",
        headers=h,
    )
    assert r.status_code == 200
    types = r.json()
    assert len(types) == 1
    assert types[0]["name"] == "General"
    general_tid = types[0]["id"]

    r = client.get(f"/v1/businesses/{bid}/category-types-index", headers=h)
    assert r.status_code == 200, r.text
    idx = r.json()
    assert len(idx) == 1
    assert idx[0]["name"] == "General"
    assert idx[0]["category_id"] == cid
    assert idx[0]["category_name"] == "Pulses"
    assert idx[0]["id"] == general_tid

    r = client.get(f"/v1/businesses/{bid}/item-categories", headers=h)
    assert r.status_code == 200
    assert len(r.json()) == 1

    sup = client.post(
        f"/v1/businesses/{bid}/suppliers",
        json={"name": "Cat test sup", "phone": "9000000000", "gst_number": "22AAAAA0000A1Z5"},
        headers=h,
    )
    assert sup.status_code == 201, sup.text
    sid0 = sup.json()["id"]

    r = client.post(
        f"/v1/businesses/{bid}/catalog-items",
        json={
            "category_id": cid,
            "name": "Toor Dal",
            "default_unit": "kg",
            "hsn_code": "04061090",
            "default_supplier_ids": [sid0],
        },
        headers=h,
    )
    assert r.status_code == 201, r.text
    iid = r.json()["id"]
    assert r.json().get("default_supplier_ids") == [sid0]
    assert r.json().get("default_kg_per_bag") is None
    assert r.json().get("type_id") == general_tid
    assert r.json().get("type_name") == "General"

    r = client.post(
        f"/v1/businesses/{bid}/catalog-items",
        json={
            "category_id": cid,
            "name": "Rice bulk",
            "default_unit": "bag",
            "default_kg_per_bag": 50,
            "hsn_code": "10063020",
            "default_supplier_ids": [sid0],
        },
        headers=h,
    )
    assert r.status_code == 201, r.text
    bag_id = r.json()["id"]
    assert r.json().get("default_kg_per_bag") == 50.0

    r = client.patch(
        f"/v1/businesses/{bid}/catalog-items/{bag_id}",
        json={"default_unit": "kg"},
        headers=h,
    )
    assert r.status_code == 200, r.text
    assert r.json().get("default_kg_per_bag") is None
    r = client.get(f"/v1/businesses/{bid}/catalog-items", headers=h)
    assert r.status_code == 200
    assert len(r.json()) == 2

    r = client.get(f"/v1/businesses/{bid}/catalog-items?category_id={cid}", headers=h)
    assert r.status_code == 200
    assert len(r.json()) == 2
    ids = {row["id"] for row in r.json()}
    assert iid in ids and bag_id in ids

    r = client.delete(f"/v1/businesses/{bid}/item-categories/{cid}", headers=h)
    assert r.status_code == 400

    r = client.delete(f"/v1/businesses/{bid}/catalog-items/{bag_id}", headers=h)
    assert r.status_code == 204

    r = client.delete(f"/v1/businesses/{bid}/catalog-items/{iid}", headers=h)
    assert r.status_code == 204

    r = client.delete(f"/v1/businesses/{bid}/item-categories/{cid}", headers=h)
    assert r.status_code == 204


def test_catalog_item_requires_default_suppliers():
    h, bid = _auth_and_business()
    r = client.post(
        f"/v1/businesses/{bid}/item-categories",
        json={"name": "NoSup"},
        headers=h,
    )
    assert r.status_code == 201, r.text
    cid = r.json()["id"]
    r = client.post(
        f"/v1/businesses/{bid}/catalog-items",
        json={"category_id": cid, "name": "X", "default_unit": "kg"},
        headers=h,
    )
    assert r.status_code == 422, r.text


def test_catalog_item_create_box_with_items_per_box():
    h, bid = _auth_and_business()
    r = client.post(
        f"/v1/businesses/{bid}/item-categories",
        json={"name": "BoxCat"},
        headers=h,
    )
    assert r.status_code == 201, r.text
    cid = r.json()["id"]
    sup = client.post(
        f"/v1/businesses/{bid}/suppliers",
        json={"name": "Box sup", "phone": "9000000001", "gst_number": "22AAAAA0000A1Z5"},
        headers=h,
    )
    assert sup.status_code == 201, sup.text
    sid = sup.json()["id"]
    r = client.post(
        f"/v1/businesses/{bid}/catalog-items",
        json={
            "category_id": cid,
            "name": "Biscuits 12p",
            "default_unit": "box",
            "default_items_per_box": 12,
            "default_supplier_ids": [sid],
        },
        headers=h,
    )
    assert r.status_code == 201, r.text
    assert r.json()["default_items_per_box"] == 12.0
    assert r.json()["default_supplier_ids"] == [sid]


def test_catalog_fuzzy_check():
    h, bid = _auth_and_business()
    r = client.post(
        f"/v1/businesses/{bid}/item-categories",
        json={"name": "TestCat"},
        headers=h,
    )
    assert r.status_code == 201, r.text
    cid = r.json()["id"]
    r = client.get(
        f"/v1/businesses/{bid}/item-categories/{cid}/category-types",
        headers=h,
    )
    assert r.status_code == 200
    tid = r.json()[0]["id"]
    sup = client.post(
        f"/v1/businesses/{bid}/suppliers",
        json={"name": "S1", "phone": "9111111111", "gst_number": "22AAAAA0000A1Z5"},
        headers=h,
    )
    assert sup.status_code == 201, sup.text
    sid = sup.json()["id"]
    r = client.post(
        f"/v1/businesses/{bid}/catalog-items",
        json={
            "category_id": cid,
            "type_id": tid,
            "name": "Toor Dal Premium",
            "default_unit": "kg",
            "default_supplier_ids": [sid],
        },
        headers=h,
    )
    assert r.status_code == 201, r.text
    r = client.get(
        f"/v1/businesses/{bid}/catalog/fuzzy-check",
        params={"name": "Toor Dal Prem", "type_id": tid},
        headers=h,
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert "hits" in body
    assert len(body["hits"]) >= 1
    top = body["hits"][0]
    assert top["score"] >= 0.65
    assert "Toor" in top["name"]


def test_catalog_item_patch_box_requires_items_per_box():
    h, bid = _auth_and_business()
    r = client.post(
        f"/v1/businesses/{bid}/item-categories",
        json={"name": "PatchBox"},
        headers=h,
    )
    assert r.status_code == 201, r.text
    cid = r.json()["id"]
    sup = client.post(
        f"/v1/businesses/{bid}/suppliers",
        json={"name": "Patch sup", "phone": "9000000002", "gst_number": "22AAAAA0000A1Z5"},
        headers=h,
    )
    assert sup.status_code == 201, sup.text
    sid = sup.json()["id"]
    r = client.post(
        f"/v1/businesses/{bid}/catalog-items",
        json={
            "category_id": cid,
            "name": "SUNRICH 400GM BOX",
            "default_unit": "piece",
            "default_supplier_ids": [sid],
        },
        headers=h,
    )
    assert r.status_code == 201, r.text
    iid = r.json()["id"]

    r = client.patch(
        f"/v1/businesses/{bid}/catalog-items/{iid}",
        json={"default_unit": "box", "default_items_per_box": None},
        headers=h,
    )
    assert r.status_code == 422, r.text

    r = client.patch(
        f"/v1/businesses/{bid}/catalog-items/{iid}",
        json={"default_unit": "box", "default_items_per_box": 1},
        headers=h,
    )
    assert r.status_code == 200, r.text
    assert r.json()["default_unit"] == "box"
    assert r.json()["default_items_per_box"] == 1.0
