"""Home overview ETag conditional GET."""

import uuid

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def _owner_headers():
    u = uuid.uuid4().hex[:10]
    email = f"homeetag{u}@test.hexa.local"
    r = client.post(
        "/v1/auth/register",
        json={"username": f"homeetag{u}", "email": email, "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    token = r.json()["access_token"]
    h = {"Authorization": f"Bearer {token}"}
    bid = client.get("/v1/me/businesses", headers=h).json()[0]["id"]
    return h, bid


def test_home_overview_returns_etag_and_honors_if_none_match():
    h, bid = _owner_headers()
    r = client.get(
        f"/v1/businesses/{bid}/reports/home-overview",
        headers=h,
        params={"from": "2026-01-01", "to": "2026-01-31", "shell_bundle": "true"},
    )
    assert r.status_code == 200, r.text
    etag = r.headers.get("etag")
    assert etag is not None
    r2 = client.get(
        f"/v1/businesses/{bid}/reports/home-overview",
        headers={**h, "If-None-Match": etag},
        params={"from": "2026-01-01", "to": "2026-01-31", "shell_bundle": "true"},
    )
    assert r2.status_code == 304
