"""Internal cron hooks (not part of public v1 API)."""

from __future__ import annotations

from fastapi import APIRouter, Header, HTTPException

from app.config import get_settings

router = APIRouter(prefix="/internal", tags=["internal"])


@router.post("/whatsapp-reports/send-due")
async def send_due_whatsapp_reports(
    x_cron_secret: str | None = Header(default=None, alias="X-Cron-Secret"),
) -> dict[str, int | str]:
    """Cron entrypoint for scheduled WhatsApp purchase summaries.

    Full schedule dispatch is not wired yet; this endpoint exists so Render cron
    stops 404ing and can be extended when Cloud API sends are enabled.
    """
    settings = get_settings()
    expected = (settings.whatsapp_reports_cron_secret or "").strip()
    if not expected:
        raise HTTPException(status_code=503, detail="Cron secret not configured")
    if (x_cron_secret or "").strip() != expected:
        raise HTTPException(status_code=401, detail="Invalid cron secret")
    return {"sent": 0, "skipped": 0, "status": "ok"}
