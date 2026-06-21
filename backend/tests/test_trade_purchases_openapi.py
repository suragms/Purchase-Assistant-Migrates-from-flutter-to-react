"""Smoke: trade purchase routes appear in OpenAPI."""

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_openapi_lists_trade_purchase_paths():
    r = client.get("/openapi.json")
    assert r.status_code == 200
    paths = r.json().get("paths", {})
    keys = " ".join(paths.keys())
    assert "/v1/businesses/{business_id}/trade-purchases" in keys
    assert "/v1/businesses/{business_id}/reports/trade-summary" in keys
    assert "/v1/businesses/{business_id}/reports/trade-daily-profit" in keys
