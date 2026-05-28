import uuid

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def _register_and_business():
    u = uuid.uuid4().hex[:10]
    email = f"stockalerts{u}@test.hexa.local"
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


def test_warehouse_alerts_summary_contract():
    h, bid = _register_and_business()
    r = client.get(f"/v1/businesses/{bid}/stock/warehouse/alerts-summary", headers=h)
    assert r.status_code == 200, r.text
    data = r.json()
    for key in (
        "pending_deliveries",
        "low_stock",
        "critical_stock",
        "pending_verifications",
        "missing_barcode",
        "missing_usage_logs",
        "eviction_count",
        "checklist_completion_pct",
        "total_items",
    ):
        assert key in data
