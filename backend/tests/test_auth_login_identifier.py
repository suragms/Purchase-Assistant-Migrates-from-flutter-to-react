import uuid

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def _owner_with_staff():
    u = uuid.uuid4().hex[:8]
    suffix = u[-8:]
    phone = f"98{suffix[:8]}"
    username = f"krishna_{suffix[:6]}"
    email = f"owner{u}@test.hexa.local"
    r = client.post(
        "/v1/auth/register",
        json={"username": f"ow{u}", "email": email, "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    token = r.json()["access_token"]
    h = {"Authorization": f"Bearer {token}"}
    bid = client.get("/v1/me/businesses", headers=h).json()[0]["id"]
    digits = "".join(c for c in phone if c.isdigit())
    cr = client.post(
        f"/v1/businesses/{bid}/users",
        headers=h,
        json={
            "full_name": "Krishna Staff",
            "phone": phone,
            "role": "staff",
            "username": username,
        },
    )
    assert cr.status_code == 201, cr.text
    pwd = cr.json()["generated_password"]
    return pwd, username, phone, f"{digits}@staff.harisree.local"


def test_login_by_username():
    pwd, username, _phone, _email = _owner_with_staff()
    r = client.post(
        "/v1/auth/login",
        json={"identifier": username, "password": pwd},
    )
    assert r.status_code == 200, r.text
    assert r.json().get("access_token")


def test_login_by_phone_digits():
    pwd, _username, phone, _email = _owner_with_staff()
    r = client.post(
        "/v1/auth/login",
        json={"identifier": phone, "password": pwd},
    )
    assert r.status_code == 200, r.text


def test_login_by_staff_synthetic_email():
    pwd, _username, _phone, staff_email = _owner_with_staff()
    r = client.post(
        "/v1/auth/login",
        json={"identifier": staff_email, "password": pwd},
    )
    assert r.status_code == 200, r.text


def test_login_wrong_password():
    pwd, username, _phone, _email = _owner_with_staff()
    r = client.post(
        "/v1/auth/login",
        json={"identifier": username, "password": "wrongpass99"},
    )
    assert r.status_code == 401
    assert "password" in r.json()["detail"].lower()


def test_login_inactive_user():
    u = uuid.uuid4().hex[:8]
    owner_email = f"own2{u}@test.hexa.local"
    reg = client.post(
        "/v1/auth/register",
        json={"username": f"o2{u}", "email": owner_email, "password": "testpass12"},
    )
    h = {"Authorization": f"Bearer {reg.json()['access_token']}"}
    bid = client.get("/v1/me/businesses", headers=h).json()[0]["id"]
    inactive_phone = f"92{u[-8:]}"
    cr = client.post(
        f"/v1/businesses/{bid}/users",
        headers=h,
        json={"full_name": "Inactive", "phone": inactive_phone, "role": "staff"},
    )
    uid = cr.json()["user"]["id"]
    ipwd = cr.json()["generated_password"]
    client.patch(
        f"/v1/businesses/{bid}/users/{uid}",
        headers=h,
        json={"is_active": False},
    )
    r = client.post(
        "/v1/auth/login",
        json={"identifier": inactive_phone, "password": ipwd},
    )
    assert r.status_code == 403
