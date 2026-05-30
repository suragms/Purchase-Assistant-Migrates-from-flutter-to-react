"""Trade purchase lifecycle: due_date, partial payment, overdue derivation."""

import uuid
from datetime import date, timedelta
from decimal import Decimal

from fastapi.testclient import TestClient

from app.main import app
from app.schemas.trade_purchases import TradePurchaseCreateRequest, TradePurchaseLineIn
from app.services.trade_purchase_service import compute_totals

client = TestClient(app)


def _register_and_business():
    u = uuid.uuid4().hex[:10]
    email = f"tp{u}@test.hexa.local"
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


def _staff_headers(owner_h, bid):
    suffix = uuid.uuid4().hex[:8]
    phone = f"98{int(suffix, 16) % 100000000:08d}"
    staff_email = f"tpstaff{suffix}@test.hexa.local"
    cr = client.post(
        f"/v1/businesses/{bid}/users",
        headers=owner_h,
        json={
            "full_name": "Trade Purchase Staff",
            "phone": phone,
            "email": staff_email,
            "role": "staff",
        },
    )
    assert cr.status_code == 201, cr.text
    login = client.post(
        "/v1/auth/login",
        json={"email": staff_email, "password": cr.json()["generated_password"]},
    )
    assert login.status_code == 200, login.text
    return {"Authorization": f"Bearer {login.json()['access_token']}"}


def _arrive_verify_commit(h, bid, purchase: dict):
    """Delivery pipeline: arrive → verify → commit-stock (replaces legacy delivery PATCH)."""
    pid = purchase["id"]
    line_id = purchase["lines"][0]["id"]
    qty = str(purchase["lines"][0].get("qty", 10))
    arr = client.post(
        f"/v1/businesses/{bid}/trade-purchases/{pid}/arrive",
        headers=h,
        json={},
    )
    assert arr.status_code == 200, arr.text
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
    commit = client.post(
        f"/v1/businesses/{bid}/trade-purchases/{pid}/commit-stock",
        headers=h,
    )
    assert commit.status_code == 200, commit.text
    return commit.json()


def _line_body(catalog_item_id: str | None = None):
    body = {
        "item_name": "Rice",
        "qty": 10,
        "unit": "BAG",
        "landing_cost": "100",
        "tax_percent": "0",
        "kg_per_unit": "50",
        "landing_cost_per_kg": "2",
    }
    if catalog_item_id is not None:
        body["catalog_item_id"] = catalog_item_id
    return body


def _supplier_id(h, bid, *, name: str = "TP Test Supplier") -> str:
    r = client.post(
        f"/v1/businesses/{bid}/suppliers",
        headers=h,
        json={"name": name, "phone": "9876501234", "gst_number": "22AAAAA0000A1Z5"},
    )
    assert r.status_code == 201, r.text
    return r.json()["id"]


def _catalog_item_id(
    h,
    bid,
    *,
    name: str = "Test rice",
    item_code: str | None = None,
    barcode: str | None = None,
) -> str:
    """Create a minimal catalog item. Phase 6 requires every purchase line to
    link to one, so tests need to create it up-front."""
    sid = _supplier_id(h, bid, name=f"Def {uuid.uuid4().hex[:6]}")
    cat = client.post(
        f"/v1/businesses/{bid}/item-categories",
        headers=h,
        json={"name": f"Cat {uuid.uuid4().hex[:6]}"},
    )
    assert cat.status_code == 201, cat.text
    cid = cat.json()["id"]
    types = client.get(
        f"/v1/businesses/{bid}/item-categories/{cid}/category-types",
        headers=h,
    )
    assert types.status_code == 200, types.text
    tid = types.json()[0]["id"]
    payload = {
        "category_id": cid,
        "type_id": tid,
        "name": name,
        "default_unit": "bag",
        "stock_unit": "bag",
        "default_kg_per_bag": 50,
        "default_supplier_ids": [sid],
    }
    if item_code is not None:
        payload["item_code"] = item_code
    if barcode is not None:
        payload["barcode"] = barcode
    item = client.post(
        f"/v1/businesses/{bid}/catalog-items",
        headers=h,
        json=payload,
    )
    assert item.status_code == 201, item.text
    return item.json()["id"]


def test_create_sets_due_date_from_payment_days():
    h, bid = _register_and_business()
    sid = _supplier_id(h, bid)
    iid = _catalog_item_id(h, bid)
    pd = date.today()
    body = {
        "purchase_date": pd.isoformat(),
        "payment_days": 14,
        "supplier_id": sid,
        "lines": [_line_body(iid)],
    }
    r = client.post(f"/v1/businesses/{bid}/trade-purchases", headers=h, json=body)
    assert r.status_code == 201, r.text
    data = r.json()
    assert data["due_date"] == (pd + timedelta(days=14)).isoformat()
    assert float(data["paid_amount"]) == 0
    assert data["derived_status"] in ("confirmed", "draft", "saved")


def test_partial_payment_derived_partially_paid():
    h, bid = _register_and_business()
    sid = _supplier_id(h, bid)
    iid = _catalog_item_id(h, bid)
    body = {
        "purchase_date": date.today().isoformat(),
        "payment_days": 30,
        "supplier_id": sid,
        "lines": [_line_body(iid)],
    }
    cr = client.post(f"/v1/businesses/{bid}/trade-purchases", headers=h, json=body)
    assert cr.status_code == 201, cr.text
    pid = cr.json()["id"]
    total = float(cr.json()["total_amount"])
    mid = total / 2
    pr = client.patch(
        f"/v1/businesses/{bid}/trade-purchases/{pid}/payment",
        headers=h,
        json={"paid_amount": mid},
    )
    assert pr.status_code == 200, pr.text
    d = pr.json()
    assert d["derived_status"] == "partially_paid"
    assert abs(float(d["remaining"]) - (total - mid)) < 0.01


def test_past_due_date_overdue_when_unpaid():
    h, bid = _register_and_business()
    sid = _supplier_id(h, bid)
    iid = _catalog_item_id(h, bid)
    old = date.today() - timedelta(days=100)
    body = {
        "purchase_date": old.isoformat(),
        "payment_days": 7,
        "supplier_id": sid,
        "lines": [_line_body(iid)],
    }
    cr = client.post(f"/v1/businesses/{bid}/trade-purchases", headers=h, json=body)
    assert cr.status_code == 201, cr.text
    d = cr.json()
    assert d["derived_status"] == "overdue"
    assert d["due_date"] == (old + timedelta(days=7)).isoformat()


def test_mark_paid_full():
    h, bid = _register_and_business()
    sid = _supplier_id(h, bid)
    iid = _catalog_item_id(h, bid)
    body = {
        "purchase_date": date.today().isoformat(),
        "payment_days": 5,
        "supplier_id": sid,
        "lines": [_line_body(iid)],
    }
    cr = client.post(f"/v1/businesses/{bid}/trade-purchases", headers=h, json=body)
    assert cr.status_code == 201, cr.text
    pid = cr.json()["id"]
    mr = client.post(f"/v1/businesses/{bid}/trade-purchases/{pid}/mark-paid", headers=h, json={})
    assert mr.status_code == 200, mr.text
    assert mr.json()["derived_status"] == "paid"


def test_cancel_purchase():
    h, bid = _register_and_business()
    sid = _supplier_id(h, bid)
    iid = _catalog_item_id(h, bid)
    body = {
        "purchase_date": date.today().isoformat(),
        "status": "draft",
        "supplier_id": sid,
        "lines": [_line_body(iid)],
    }
    cr = client.post(f"/v1/businesses/{bid}/trade-purchases", headers=h, json=body)
    assert cr.status_code == 201, cr.text
    pid = cr.json()["id"]
    xr = client.post(f"/v1/businesses/{bid}/trade-purchases/{pid}/cancel", headers=h)
    assert xr.status_code == 200, xr.text
    assert xr.json()["derived_status"] == "cancelled"


def test_purchase_response_includes_supplier_profile_and_line_hsn():
    h, bid = _register_and_business()
    cat = client.post(
        f"/v1/businesses/{bid}/item-categories",
        headers=h,
        json={"name": "Test grains"},
    )
    assert cat.status_code == 201, cat.text
    cid = cat.json()["id"]
    types = client.get(
        f"/v1/businesses/{bid}/item-categories/{cid}/category-types",
        headers=h,
    )
    assert types.status_code == 200, types.text
    tid = types.json()[0]["id"]
    sup = client.post(
        f"/v1/businesses/{bid}/suppliers",
        headers=h,
        json={
            "name": "Kerala Supplier",
            "gst_number": "32BBBBB0000B1Z5",
            "address": "Market Road, Thrissur",
            "phone": "9876501234",
        },
    )
    assert sup.status_code == 201, sup.text
    sid = sup.json()["id"]
    item = client.post(
        f"/v1/businesses/{bid}/catalog-items",
        headers=h,
        json={
            "category_id": cid,
            "name": "Test rice",
            "type_id": tid,
            "default_unit": "bag",
            "stock_unit": "bag",
            "default_kg_per_bag": 50,
            "hsn_code": "10063090",
            "default_supplier_ids": [sid],
        },
    )
    assert item.status_code == 201, item.text
    iid = item.json()["id"]

    body = {
        "purchase_date": date.today().isoformat(),
        "supplier_id": sid,
        "lines": [
            {
                "catalog_item_id": iid,
                "item_name": "Test rice",
                "qty": 5,
                "unit": "BAG",
                "landing_cost": "2000",
                "kg_per_unit": "50",
                "landing_cost_per_kg": "40",
                "tax_percent": "0",
            }
        ],
    }
    cr = client.post(f"/v1/businesses/{bid}/trade-purchases", headers=h, json=body)
    assert cr.status_code == 201, cr.text
    data = cr.json()
    assert data.get("supplier_gst") == "32BBBBB0000B1Z5"
    assert data.get("supplier_address") == "Market Road, Thrissur"
    assert data.get("supplier_phone") == "9876501234"
    lines = data.get("lines") or []
    assert len(lines) == 1
    assert lines[0].get("hsn_code") == "10063090"


def test_line_payment_days_hsn_description_round_trip():
    h, bid = _register_and_business()
    sid = _supplier_id(h, bid)
    iid = _catalog_item_id(h, bid)
    body = {
        "purchase_date": date.today().isoformat(),
        "payment_days": 10,
        "supplier_id": sid,
        "lines": [
            {
                **_line_body(iid),
                "payment_days": 5,
                "hsn_code": "12345678",
                "description": "Lot A",
            }
        ],
    }
    cr = client.post(f"/v1/businesses/{bid}/trade-purchases", headers=h, json=body)
    assert cr.status_code == 201, cr.text
    lines = cr.json().get("lines") or []
    assert len(lines) == 1
    assert lines[0].get("payment_days") == 5
    assert lines[0].get("hsn_code") == "12345678"
    assert lines[0].get("description") == "Lot A"


def test_list_due_soon_filter():
    h, bid = _register_and_business()
    sid = _supplier_id(h, bid)
    iid = _catalog_item_id(h, bid)
    body = {
        "purchase_date": date.today().isoformat(),
        "payment_days": 2,
        "supplier_id": sid,
        "lines": [_line_body(iid)],
    }
    cr = client.post(f"/v1/businesses/{bid}/trade-purchases", headers=h, json=body)
    assert cr.status_code == 201, cr.text
    pid = cr.json()["id"]
    assert cr.json()["derived_status"] == "due_soon"

    r_all = client.get(f"/v1/businesses/{bid}/trade-purchases", headers=h)
    assert r_all.status_code == 200, r_all.text
    ids_all = {x["id"] for x in r_all.json()}
    assert pid in ids_all

    r_ds = client.get(f"/v1/businesses/{bid}/trade-purchases?status=due_soon", headers=h)
    assert r_ds.status_code == 200, r_ds.text
    ids_ds = {x["id"] for x in r_ds.json()}
    assert pid in ids_ds


def test_list_unknown_status_returns_200_not_422():
    """Optional filters must not yield validation errors (bad clients / URLs)."""
    h, bid = _register_and_business()
    r = client.get(
        f"/v1/businesses/{bid}/trade-purchases?status=not_a_real_status",
        headers=h,
    )
    assert r.status_code == 200, r.text
    assert isinstance(r.json(), list)


def test_list_q_filters_by_item_name():
    h, bid = _register_and_business()
    sid = _supplier_id(h, bid)
    iid = _catalog_item_id(h, bid)
    unique = f"ZetaGrain{uuid.uuid4().hex[:8]}"
    body = {
        "purchase_date": date.today().isoformat(),
        "supplier_id": sid,
        "lines": [
            {
                "catalog_item_id": iid,
                "item_name": unique,
                "qty": 1,
                "unit": "kg",
                "landing_cost": "10",
                "tax_percent": "0",
            }
        ],
    }
    cr = client.post(f"/v1/businesses/{bid}/trade-purchases", headers=h, json=body)
    assert cr.status_code == 201, cr.text
    pid = cr.json()["id"]

    r = client.get(
        f"/v1/businesses/{bid}/trade-purchases?q={unique[:6]}",
        headers=h,
    )
    assert r.status_code == 200, r.text
    ids = {x["id"] for x in r.json()}
    assert pid in ids


def test_list_purchase_date_range_inclusive_filter():
    h, bid = _register_and_business()
    sid = _supplier_id(h, bid)
    iid = _catalog_item_id(h, bid)
    d_old = date(2024, 1, 15)
    d_mid = date(2024, 6, 10)
    d_new = date(2024, 12, 1)

    for pd in (d_old, d_mid, d_new):
        body = {
            "purchase_date": pd.isoformat(),
            "supplier_id": sid,
            "lines": [
                {
                    "catalog_item_id": iid,
                    "item_name": "Rice",
                    "qty": 1,
                    "unit": "kg",
                    "landing_cost": "10",
                    "tax_percent": "0",
                }
            ],
        }
        cr = client.post(f"/v1/businesses/{bid}/trade-purchases", headers=h, json=body)
        assert cr.status_code == 201, cr.text

    ra = client.get(
        f"/v1/businesses/{bid}/trade-purchases"
        f"?purchase_from={d_mid.isoformat()}&purchase_to={d_mid.isoformat()}&limit=50",
        headers=h,
    )
    assert ra.status_code == 200, ra.text
    rows = ra.json()
    assert len(rows) == 1
    assert rows[0]["purchase_date"] == d_mid.isoformat()

    rb = client.get(
        f"/v1/businesses/{bid}/trade-purchases"
        f"?purchase_from={d_old.isoformat()}&purchase_to={d_new.isoformat()}&limit=50",
        headers=h,
    )
    assert rb.status_code == 200, rb.text
    assert len(rb.json()) == 3


def test_compute_totals_plain_line():
    req = TradePurchaseCreateRequest(
        purchase_date=date.today(),
        supplier_id=uuid.uuid4(),
        lines=[
            TradePurchaseLineIn(
                catalog_item_id=uuid.uuid4(),
                item_name="Rice",
                qty=10,
                unit="kg",
                landing_cost=100,
                tax_percent=0,
            )
        ],
    )
    qty, amt = compute_totals(req)
    assert qty == Decimal("10")
    assert amt == Decimal("1000")


def test_compute_totals_line_tax_multiplier():
    """Header total uses tax-inclusive [_line_money] (parity with Flutter computeTradeTotals)."""
    req = TradePurchaseCreateRequest(
        purchase_date=date.today(),
        supplier_id=uuid.uuid4(),
        lines=[
            TradePurchaseLineIn(
                catalog_item_id=uuid.uuid4(),
                item_name="Rice",
                qty=10,
                unit="kg",
                landing_cost=100,
                tax_percent=5,
            )
        ],
    )
    qty, amt = compute_totals(req)
    assert qty == Decimal("10")
    assert amt == Decimal("1050")


def test_compute_totals_line_discount():
    req = TradePurchaseCreateRequest(
        purchase_date=date.today(),
        supplier_id=uuid.uuid4(),
        lines=[
            TradePurchaseLineIn(
                catalog_item_id=uuid.uuid4(),
                item_name="Rice",
                qty=10,
                unit="kg",
                landing_cost=100,
                tax_percent=0,
                discount=10,
            )
        ],
    )
    qty, amt = compute_totals(req)
    assert qty == Decimal("10")
    assert amt == Decimal("900")


def test_compute_totals_header_discount_and_commission():
    req = TradePurchaseCreateRequest(
        purchase_date=date.today(),
        supplier_id=uuid.uuid4(),
        discount=10,
        commission_percent=5,
        lines=[
            TradePurchaseLineIn(
                catalog_item_id=uuid.uuid4(),
                item_name="Rice",
                qty=10,
                unit="kg",
                landing_cost=100,
                tax_percent=0,
            )
        ],
    )
    qty, amt = compute_totals(req)
    assert qty == Decimal("10")
    after_header = Decimal("900")
    assert amt == after_header + after_header * Decimal("5") / Decimal("100")


def test_compute_totals_one_bag_2250_commission_2_percent_dart_parity():
    """Same inputs as flutter_app/test/calc_engine_test.dart (bag + 2% commission)."""
    req = TradePurchaseCreateRequest(
        purchase_date=date.today(),
        supplier_id=uuid.uuid4(),
        commission_percent=2,
        lines=[
            TradePurchaseLineIn(
                catalog_item_id=uuid.uuid4(),
                item_name="Wheat bag",
                qty=1,
                unit="BAG",
                landing_cost=2250,
                kg_per_unit=50,
                landing_cost_per_kg=Decimal("45"),
                tax_percent=0,
            )
        ],
    )
    qty, amt = compute_totals(req)
    assert qty == Decimal("1")
    after_header = Decimal("2250")
    assert amt == after_header + after_header * Decimal("2") / Decimal("100")


def test_compute_totals_flat_box_commission_only_counts_box_lines():
    req = TradePurchaseCreateRequest(
        purchase_date=date.today(),
        supplier_id=uuid.uuid4(),
        commission_mode="flat_box",
        commission_money=Decimal("3"),
        lines=[
            TradePurchaseLineIn(
                catalog_item_id=uuid.uuid4(),
                item_name="Sunrich BOX",
                qty=200,
                unit="box",
                landing_cost=Decimal("10"),
                tax_percent=Decimal("0"),
            ),
            TradePurchaseLineIn(
                catalog_item_id=uuid.uuid4(),
                item_name="Sugar 50 KG",
                qty=100,
                unit="bag",
                landing_cost=Decimal("2000"),
                kg_per_unit=Decimal("50"),
                landing_cost_per_kg=Decimal("40"),
                tax_percent=Decimal("0"),
            ),
        ],
    )
    qty, amt = compute_totals(req)
    assert qty == Decimal("300")
    # line totals are tax-inclusive; commission only applies to box qty=200
    expected_lines = Decimal("10") * Decimal("200") + Decimal("2000") * Decimal("100")
    expected_comm = Decimal("3") * Decimal("200")
    assert amt == expected_lines + expected_comm


def test_compute_totals_freight_separate_vs_included():
    line = TradePurchaseLineIn(
        catalog_item_id=uuid.uuid4(),
        item_name="Rice",
        qty=1,
        unit="kg",
        landing_cost=100,
        tax_percent=0,
    )
    sid = uuid.uuid4()
    sep = TradePurchaseCreateRequest(
        purchase_date=date.today(),
        supplier_id=sid,
        freight_amount=50,
        freight_type="separate",
        lines=[line],
    )
    inc = TradePurchaseCreateRequest(
        purchase_date=date.today(),
        supplier_id=sid,
        freight_amount=50,
        freight_type="included",
        lines=[line],
    )
    assert compute_totals(sep)[1] == Decimal("150")
    assert compute_totals(inc)[1] == Decimal("100")


def test_compute_totals_billty_and_delivered_fixed_rupees():
    line = TradePurchaseLineIn(
        catalog_item_id=uuid.uuid4(),
        item_name="Rice",
        qty=1,
        unit="kg",
        landing_cost=100,
        tax_percent=0,
    )
    sid = uuid.uuid4()
    req = TradePurchaseCreateRequest(
        purchase_date=date.today(),
        supplier_id=sid,
        billty_rate=10,
        delivered_rate=5,
        lines=[line],
    )
    assert compute_totals(req)[1] == Decimal("115")


def test_line_money_kg_fields_matches_per_bag_landing():
    """100 bag × 50 kg × ₹42/kg == 100 × ₹2100/bag."""
    from app.services.trade_purchase_service import _line_money

    kg_line = TradePurchaseLineIn(
        catalog_item_id=uuid.uuid4(),
        item_name="Rice",
        qty=100,
        unit="bag",
        landing_cost=Decimal("2100"),
        kg_per_unit=Decimal("50"),
        landing_cost_per_kg=Decimal("42"),
        tax_percent=Decimal("0"),
    )
    bag_line = TradePurchaseLineIn(
        catalog_item_id=uuid.uuid4(),
        item_name="Rice",
        qty=100,
        unit="bag",
        landing_cost=Decimal("2100"),
        kg_per_unit=Decimal("50"),
        landing_cost_per_kg=Decimal("42"),
        tax_percent=Decimal("0"),
    )
    assert _line_money(kg_line) == _line_money(bag_line)


def test_create_round_trip_invoice_number():
    h, bid = _register_and_business()
    sid = _supplier_id(h, bid, name="Inv Supplier")
    iid = _catalog_item_id(h, bid)
    body = {
        "purchase_date": date.today().isoformat(),
        "invoice_number": "INV-2026-0422",
        "supplier_id": sid,
        "lines": [_line_body(iid)],
    }
    cr = client.post(f"/v1/businesses/{bid}/trade-purchases", headers=h, json=body)
    assert cr.status_code == 201, cr.text
    assert cr.json().get("invoice_number") == "INV-2026-0422"
    pid = cr.json()["id"]
    gr = client.get(f"/v1/businesses/{bid}/trade-purchases/{pid}", headers=h)
    assert gr.status_code == 200, gr.text
    assert gr.json().get("invoice_number") == "INV-2026-0422"


def test_business_scoped_suppliers_catalog_items_trade_purchases_list_shapes():
    """Automates manual OpenAPI checks: business-scoped GET list routes + supplier mapping."""
    h, bid = _register_and_business()
    r_sup_list = client.get(f"/v1/businesses/{bid}/suppliers", headers=h)
    assert r_sup_list.status_code == 200, r_sup_list.text
    assert isinstance(r_sup_list.json(), list)

    sup = client.post(
        f"/v1/businesses/{bid}/suppliers",
        headers=h,
        json={
            "name": "API shape supplier",
            "phone": "9876501234",
            "gst_number": "32AAAAA0000A1Z5",
            "default_payment_days": 7,
            "default_billty_rate": 1.5,
            "default_delivered_rate": 2.0,
        },
    )
    assert sup.status_code == 201, sup.text
    row = sup.json()
    for k in ("id", "name", "gst_number", "default_payment_days", "default_billty_rate", "default_delivered_rate"):
        assert k in row

    r_cat = client.get(f"/v1/businesses/{bid}/catalog-items", headers=h)
    assert r_cat.status_code == 200, r_cat.text
    assert isinstance(r_cat.json(), list)

    r_tp = client.get(f"/v1/businesses/{bid}/trade-purchases", headers=h)
    assert r_tp.status_code == 200, r_tp.text
    assert isinstance(r_tp.json(), list)


def test_create_rejects_line_missing_catalog_item_id():
    """Phase 6 parity: the server must reject free-typed lines (no catalog link)
    so an older/offline client cannot bypass the strict Flutter validator."""
    h, bid = _register_and_business()
    sid = _supplier_id(h, bid, name="Strict parity supplier")
    body = {
        "purchase_date": date.today().isoformat(),
        "supplier_id": sid,
        "lines": [
            {
                "item_name": "Unlinked rice",
                "qty": 1,
                "unit": "kg",
                "landing_cost": 100,
            }
        ],
    }
    r = client.post(f"/v1/businesses/{bid}/trade-purchases", headers=h, json=body)
    assert r.status_code == 422, r.text
    body_json = r.json()
    detail = body_json.get("detail")
    assert isinstance(detail, list) and detail, body_json
    msg = " ".join(str(d.get("loc", [])) + " " + str(d.get("msg", "")) for d in detail)
    assert "catalog_item_id" in msg, msg


def test_create_rejects_line_with_only_one_kg_field():
    h, bid = _register_and_business()
    sid = _supplier_id(h, bid, name="Kg parity supplier")
    iid = _catalog_item_id(h, bid)
    body = {
        "purchase_date": date.today().isoformat(),
        "supplier_id": sid,
        "lines": [
            {
                "catalog_item_id": iid,
                "item_name": "Half-kg rice",
                "qty": 1,
                "unit": "bag",
                "landing_cost": "100",
                "kg_per_unit": 50,
                # landing_cost_per_kg intentionally omitted (must pair kg_per_unit)
            }
        ],
    }
    r = client.post(f"/v1/businesses/{bid}/trade-purchases", headers=h, json=body)
    assert r.status_code == 422, r.text


def test_get_trade_purchase_line_total_is_line_money_landing_gross_is_pre_tax():
    """API contract: line_total = tax/discount-inclusive purchase; line_landing_gross = line_gross_base."""
    h, bid = _register_and_business()
    sid = _supplier_id(h, bid)
    iid = _catalog_item_id(h, bid)
    line = _line_body(iid)
    line["discount"] = "10"
    line["tax_percent"] = "5"
    body = {
        "purchase_date": date.today().isoformat(),
        "payment_days": 7,
        "supplier_id": sid,
        "lines": [line],
    }
    cr = client.post(f"/v1/businesses/{bid}/trade-purchases", headers=h, json=body)
    assert cr.status_code == 201, cr.text
    pid = cr.json()["id"]
    gr = client.get(f"/v1/businesses/{bid}/trade-purchases/{pid}", headers=h)
    assert gr.status_code == 200, gr.text
    ln = gr.json()["lines"][0]
    # Gross: 10 * 50 * 2 = 1000; after 10% disc -> 900; after 5% tax -> 945
    assert abs(float(ln["line_landing_gross"]) - 1000.0) < 0.02
    assert abs(float(ln["line_total"]) - 945.0) < 0.02


def test_purchase_to_date_filter_is_inclusive_without_next_day_leak():
    h, bid = _register_and_business()
    sid = _supplier_id(h, bid)
    iid = _catalog_item_id(h, bid)
    for purchase_date in ("2026-05-20", "2026-05-21"):
        r = client.post(
            f"/v1/businesses/{bid}/trade-purchases",
            headers=h,
            json={
                "purchase_date": purchase_date,
                "supplier_id": sid,
                "lines": [_line_body(iid)],
            },
        )
        assert r.status_code == 201, r.text

    one_day = client.get(
        f"/v1/businesses/{bid}/trade-purchases",
        headers=h,
        params={"purchase_from": "2026-05-20", "purchase_to": "2026-05-20"},
    )
    assert one_day.status_code == 200, one_day.text
    rows = one_day.json()
    assert len(rows) == 1
    assert rows[0]["purchase_date"] == "2026-05-20"


def test_stock_search_matches_saved_barcode():
    h, bid = _register_and_business()
    _catalog_item_id(
        h,
        bid,
        name="Barcode Rice",
        item_code="RICE-CODE",
        barcode="8901234567890",
    )

    r = client.get(
        f"/v1/businesses/{bid}/stock/list",
        headers=h,
        params={"q": "8901234567890"},
    )
    assert r.status_code == 200, r.text
    names = [row["name"] for row in r.json()["items"]]
    assert "Barcode Rice" in names


def test_staff_cannot_edit_payment_but_can_receive_delivery_without_financials():
    owner_h, bid = _register_and_business()
    sid = _supplier_id(owner_h, bid)
    iid = _catalog_item_id(owner_h, bid)
    cr = client.post(
        f"/v1/businesses/{bid}/trade-purchases",
        headers=owner_h,
        json={
            "purchase_date": date.today().isoformat(),
            "supplier_id": sid,
            "lines": [_line_body(iid)],
        },
    )
    assert cr.status_code == 201, cr.text
    pid = cr.json()["id"]
    staff_h = _staff_headers(owner_h, bid)

    pay = client.patch(
        f"/v1/businesses/{bid}/trade-purchases/{pid}/payment",
        headers=staff_h,
        json={"paid_amount": 10},
    )
    assert pay.status_code == 403, pay.text

    arr = client.post(
        f"/v1/businesses/{bid}/trade-purchases/{pid}/arrive",
        headers=staff_h,
        json={},
    )
    assert arr.status_code == 200, arr.text
    line_id = cr.json()["lines"][0]["id"]
    verify = client.post(
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
            ],
        },
    )
    assert verify.status_code == 200, verify.text
    body = verify.json()
    assert body["delivery_status"] in ("staff_verified", "partial")
    assert "total_amount" not in body
    assert "landing_cost" not in body["lines"][0]

    commit = client.post(
        f"/v1/businesses/{bid}/trade-purchases/{pid}/commit-stock",
        headers=staff_h,
    )
    assert commit.status_code == 403, commit.text


def test_stock_period_purchased_counts_only_delivered_purchase_lines():
    h, bid = _register_and_business()
    sid = _supplier_id(h, bid)
    iid = _catalog_item_id(h, bid)
    first = client.post(
        f"/v1/businesses/{bid}/trade-purchases",
        headers=h,
        json={
            "purchase_date": "2026-05-20",
            "supplier_id": sid,
            "lines": [_line_body(iid)],
        },
    )
    assert first.status_code == 201, first.text
    second = client.post(
        f"/v1/businesses/{bid}/trade-purchases",
        headers=h,
        json={
            "purchase_date": "2026-05-20",
            "force_duplicate": True,
            "supplier_id": sid,
            "lines": [_line_body(iid)],
        },
    )
    assert second.status_code == 201, second.text
    delivered_body = _arrive_verify_commit(h, bid, first.json())
    assert delivered_body["is_delivered"] is True
    assert delivered_body["delivery_status"] == "stock_committed"

    stock = client.get(
        f"/v1/businesses/{bid}/stock/list",
        headers=h,
        params={
            "include_period": True,
            "period_start": "2026-05-20",
            "period_end": "2026-05-20",
            "q": "Test rice",
        },
    )
    assert stock.status_code == 200, stock.text
    rows = stock.json()["items"]
    assert len(rows) == 1
    assert abs(float(rows[0]["period_purchased_qty"]) - 10.0) < 0.001
    assert rows[0]["has_pending_order"] is True
    assert abs(float(rows[0]["pending_delivery_qty"]) - 10.0) < 0.001
