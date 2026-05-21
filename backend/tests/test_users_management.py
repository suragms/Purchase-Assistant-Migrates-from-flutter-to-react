import uuid

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_create_staff_user():
    u = uuid.uuid4().hex[:8]
    email = f"owner{u}@test.hexa.local"
    r = client.post(
        "/v1/auth/register",
        json={"username": f"ow{u}", "email": email, "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    h = {"Authorization": f"Bearer {r.json()['access_token']}"}
    bid = client.get("/v1/me/businesses", headers=h).json()[0]["id"]

    phone = f"91{u[-8:]}"
    cr = client.post(
        f"/v1/businesses/{bid}/users",
        headers=h,
        json={
            "full_name": "Ravi Staff",
            "phone": phone,
            "role": "staff",
        },
    )
    assert cr.status_code == 201, cr.text
    body = cr.json()
    assert body["generated_password"]
    assert body["user"]["role"] == "staff"
