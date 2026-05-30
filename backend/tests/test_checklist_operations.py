"""Staff checklist: today, complete, owner template replace."""

import uuid

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def _owner_headers():
    u = uuid.uuid4().hex[:10]
    email = f"chk{u}@test.hexa.local"
    r = client.post(
        "/v1/auth/register",
        json={"username": f"u{u}", "email": email, "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    h = {"Authorization": f"Bearer {r.json()['access_token']}"}
    bid = client.get("/v1/me/businesses", headers=h).json()[0]["id"]
    return h, bid


def test_checklist_today_complete_and_owner_templates():
    h, bid = _owner_headers()
    today = client.get(
        f"/v1/businesses/{bid}/operations/checklist/today",
        headers=h,
    )
    assert today.status_code == 200, today.text
    body = today.json()
    tasks = body.get("tasks") or []
    assert len(tasks) >= 6
    morning = [t for t in tasks if t["slot"] == "morning"]
    assert len(morning) >= 2

    key = morning[0]["task_key"]
    done = client.post(
        f"/v1/businesses/{bid}/operations/checklist/morning/complete",
        headers=h,
        json={"task_key": key},
    )
    assert done.status_code == 204, done.text

    again = client.get(
        f"/v1/businesses/{bid}/operations/checklist/today",
        headers=h,
    )
    assert again.status_code == 200
    completed = [
        t for t in again.json()["tasks"]
        if t["task_key"] == key and t["completed"]
    ]
    assert len(completed) == 1

    put = client.put(
        f"/v1/businesses/{bid}/operations/checklist/templates",
        headers=h,
        json={
            "tasks": [
                {"slot": "morning", "task_key": "open_check", "label": "Opening stock", "sort_order": 1},
                {"slot": "evening", "task_key": "close", "label": "Close shop", "sort_order": 1},
            ]
        },
    )
    assert put.status_code == 200, put.text
    assert len(put.json()) == 2

    listed = client.get(
        f"/v1/businesses/{bid}/operations/checklist/templates",
        headers=h,
    )
    assert listed.status_code == 200
    assert len(listed.json()) == 2
