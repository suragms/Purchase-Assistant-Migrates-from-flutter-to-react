from fastapi.testclient import TestClient

from app.config import get_settings
from app.main import app


def _post_cron(headers: dict | None = None):
    get_settings.cache_clear()
    client = TestClient(app)
    return client.post("/internal/whatsapp-reports/send-due", headers=headers or {})


def test_whatsapp_reports_cron_requires_secret(monkeypatch):
    monkeypatch.setenv("WHATSAPP_REPORTS_CRON_SECRET", "test-secret")
    r = _post_cron()
    assert r.status_code == 401


def test_whatsapp_reports_cron_ok(monkeypatch):
    monkeypatch.setenv("WHATSAPP_REPORTS_CRON_SECRET", "test-secret")
    r = _post_cron(headers={"X-Cron-Secret": "test-secret"})
    assert r.status_code == 200
    assert r.json()["status"] == "ok"
    assert r.json()["sent"] == 0
