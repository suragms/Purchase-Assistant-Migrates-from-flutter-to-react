"""Export endpoints: stock XLSX, monthly purchases PDF, PDF ZIP backup."""

import uuid

from fastapi.testclient import TestClient

from app.main import app
from app.services.trade_query import TRADE_STATUS_EXCLUDED_FROM_REPORTS

client = TestClient(app)


def _register_owner():
    u = uuid.uuid4().hex[:10]
    email = f"exp{u}@test.hexa.local"
    r = client.post(
        "/v1/auth/register",
        json={"username": f"ex{u}", "email": email, "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    h = {"Authorization": f"Bearer {r.json()['access_token']}"}
    bid = client.get("/v1/me/businesses", headers=h).json()[0]["id"]
    client.post("/v1/me/bootstrap-workspace", headers=h)
    return h, bid


def test_stock_inventory_xlsx_export():
    h, bid = _register_owner()
    r = client.get(f"/v1/businesses/{bid}/exports/stock-inventory.xlsx", headers=h)
    assert r.status_code == 200, r.text
    assert r.headers["content-type"].startswith(
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    )
    assert len(r.content) > 100
    assert b"PK" in r.content[:4]


def test_purchases_month_pdf_requires_data():
    h, bid = _register_owner()
    r = client.get(f"/v1/businesses/{bid}/exports/purchases-month.pdf", headers=h)
    assert r.status_code in (200, 404), r.text
    if r.status_code == 200:
        assert r.headers["content-type"] == "application/pdf"
        assert r.content[:4] == b"%PDF"


def test_trade_status_filter_includes_stock_committed():
    assert "added_to_stock" not in TRADE_STATUS_EXCLUDED_FROM_REPORTS
    assert "completed" not in TRADE_STATUS_EXCLUDED_FROM_REPORTS
    assert "draft" in TRADE_STATUS_EXCLUDED_FROM_REPORTS


def test_backup_zip_contains_pdfs_when_empty_business():
    h, bid = _register_owner()
    r = client.post(
        f"/v1/businesses/{bid}/exports/backup",
        headers=h,
        json={"range_preset": "month"},
    )
    assert r.status_code == 404, r.text


def test_backup_zip_pdf_builders():
    from app.services.export_files import (
        build_purchase_order_pdf,
        build_purchases_range_pdf,
        build_supplier_ledger_pdf,
    )

    class _FakePurchase:
        human_id = "PO-TEST-1"
        purchase_date = __import__("datetime").date.today()
        status = "added_to_stock"
        total_amount = 100
        paid_amount = 0
        invoice_number = "INV1"
        due_date = None
        supplier_row = None

    today = __import__("datetime").date.today()
    p = _FakePurchase()
    summary = build_purchases_range_pdf(
        business_label="Test",
        title="Test",
        range_start=today.replace(day=1),
        range_end=today,
        purchases=[p],  # type: ignore[arg-type]
    )
    assert summary[:4] == b"%PDF"
    order = build_purchase_order_pdf(business_label="Test", purchase=p, lines=[])  # type: ignore[arg-type]
    assert order[:4] == b"%PDF"
    ledger = build_supplier_ledger_pdf(
        business_label="Test",
        supplier_name="Sup",
        range_start=today.replace(day=1),
        range_end=today,
        purchases=[p],  # type: ignore[arg-type]
    )
    assert ledger[:4] == b"%PDF"
