from __future__ import annotations

import hashlib
import hmac
from datetime import date, datetime, timedelta, timezone
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field
from sqlalchemy import func, select, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import Settings, get_settings
from app.database import get_db
from app.deps import AdminCaller, require_admin_caller, require_super_admin
from app.models import AdminAuditLog, ApiUsageLog, Business, TradePurchase, User
from app.services.low_stock_notifications import run_low_stock_notification_scan

router = APIRouter(prefix="/v1/admin", tags=["admin"])


class AdminLoginRequest(BaseModel):
    email: str = Field(min_length=3, max_length=320)
    password: str = Field(min_length=1, max_length=256)


class AdminEnvUpdateRequest(BaseModel):
    """Deprecated no-op retained for admin_web compatibility."""

    updates: dict[str, str] = Field(default_factory=dict)


def _password_matches(stored: str, given: str) -> bool:
    return hmac.compare_digest(
        hashlib.sha256(stored.encode("utf-8")).digest(),
        hashlib.sha256(given.encode("utf-8")).digest(),
    )


async def _api_usage_payload(settings: Settings, db: AsyncSession) -> dict:
    since = datetime.now(timezone.utc) - timedelta(hours=24)
    br = await db.execute(
        select(ApiUsageLog.provider, func.count(ApiUsageLog.id))
        .where(ApiUsageLog.created_at >= since)
        .group_by(ApiUsageLog.provider)
    )
    by_provider = {row[0]: int(row[1] or 0) for row in br.all()}
    total_24h = sum(by_provider.values())
    return {
        "providers": [
            {"name": k, "calls_24h": v, "note": "api_usage_logs"}
            for k, v in sorted(by_provider.items(), key=lambda x: -x[1])
        ],
        "calls_24h_total": total_24h,
        "integrations_configured": {
            "openai": bool(settings.openai_api_key or settings.google_ai_api_key),
            "ocr": bool(settings.ocr_api_key),
            "sentry": bool(settings.sentry_dsn),
        },
    }


@router.post("/login")
async def admin_login(
    settings: Annotated[Settings, Depends(get_settings)],
    body: AdminLoginRequest,
):
    if not settings.admin_email or not settings.admin_password or not settings.admin_api_token:
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Admin login not configured.",
        )
    if body.email.strip().lower() != settings.admin_email.strip().lower():
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, detail="Invalid credentials")
    if not _password_matches(settings.admin_password, body.password):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, detail="Invalid credentials")
    return {"access_token": settings.admin_api_token, "token_type": "bearer"}


@router.get("/health")
async def admin_super_health(
    _user: Annotated[User, Depends(require_super_admin)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    del _user
    try:
        await db.execute(text("SELECT 1"))
        db_ok = True
    except Exception:  # noqa: BLE001
        db_ok = False
    return {
        "status": "ok" if db_ok else "degraded",
        "database": "up" if db_ok else "down",
        "as_of": datetime.now(timezone.utc).isoformat(),
    }


@router.get("/businesses-overview")
async def admin_super_businesses_overview(
    _user: Annotated[User, Depends(require_super_admin)],
    db: Annotated[AsyncSession, Depends(get_db)],
    limit: int = Query(100, ge=1, le=500),
):
    del _user
    r = await db.execute(
        select(Business.id, Business.name, Business.created_at)
        .order_by(Business.created_at.desc())
        .limit(limit)
    )
    rows = r.all()
    return {
        "items": [
            {
                "id": str(row[0]),
                "name": row[1],
                "created_at": row[2].isoformat() if row[2] else None,
            }
            for row in rows
        ],
        "total_returned": len(rows),
    }


@router.post("/trigger-low-stock-alert")
async def admin_trigger_low_stock_alert(
    _user: Annotated[User, Depends(require_super_admin)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    del _user
    queued = await run_low_stock_notification_scan(db)
    return {
        "triggered": True,
        "queued_notifications": int(queued),
        "as_of": datetime.now(timezone.utc).isoformat(),
    }


@router.get("/stats")
async def admin_stats(
    _caller: Annotated[AdminCaller, Depends(require_admin_caller)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    del _caller
    today = date.today()
    users_n = await db.scalar(select(func.count(User.id)))
    businesses_n = await db.scalar(select(func.count(Business.id)))
    purchases_today = await db.scalar(
        select(func.count(TradePurchase.id)).where(TradePurchase.purchase_date == today)
    )
    purchases_total = await db.scalar(select(func.count(TradePurchase.id)))
    return {
        "users": int(users_n or 0),
        "businesses": int(businesses_n or 0),
        "entries_today": int(purchases_today or 0),
        "entries_total": int(purchases_total or 0),
        "as_of": datetime.now(timezone.utc).isoformat(),
    }


@router.get("/metrics")
async def admin_metrics(
    _caller: Annotated[AdminCaller, Depends(require_admin_caller)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    return await admin_stats(_caller, db)


@router.get("/users")
async def admin_users(
    _caller: Annotated[AdminCaller, Depends(require_admin_caller)],
    db: Annotated[AsyncSession, Depends(get_db)],
    limit: int = Query(200, ge=1, le=500),
    offset: int = Query(0, ge=0),
):
    del _caller
    total = await db.scalar(select(func.count(User.id)))
    r = await db.execute(
        select(User).order_by(User.created_at.desc()).limit(limit).offset(offset)
    )
    users = r.scalars().all()
    ids = [u.id for u in users]
    counts: dict = {}
    if ids:
        cr = await db.execute(
            select(TradePurchase.user_id, func.count(TradePurchase.id))
            .where(TradePurchase.user_id.in_(ids))
            .group_by(TradePurchase.user_id)
        )
        counts = {uid: int(c or 0) for uid, c in cr.all()}
    return {
        "items": [
            {
                "id": str(u.id),
                "email": u.email,
                "username": u.username,
                "name": u.name,
                "phone": u.phone,
                "is_super_admin": u.is_super_admin,
                "created_at": u.created_at.isoformat() if u.created_at else None,
                "has_password": bool(u.password_hash),
                "google_linked": bool(u.google_sub),
                "total_entries": counts.get(u.id, 0),
            }
            for u in users
        ],
        "total": int(total or 0),
        "limit": limit,
        "offset": offset,
    }


@router.get("/businesses")
async def admin_businesses(
    _caller: Annotated[AdminCaller, Depends(require_admin_caller)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    del _caller
    r = await db.execute(select(Business.id, Business.name, Business.created_at))
    rows = r.all()
    return {
        "items": [
            {
                "id": str(row[0]),
                "name": row[1],
                "created_at": row[2].isoformat() if row[2] else None,
            }
            for row in rows
        ]
    }


@router.get("/api-usage")
async def admin_api_usage(
    _caller: Annotated[AdminCaller, Depends(require_admin_caller)],
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
):
    del _caller
    return await _api_usage_payload(settings, db)


@router.get("/api-usage-summary")
async def admin_api_usage_summary(
    _caller: Annotated[AdminCaller, Depends(require_admin_caller)],
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
):
    del _caller
    ec = await db.execute(
        select(TradePurchase.user_id, func.count(TradePurchase.id)).group_by(TradePurchase.user_id)
    )
    entry_counts = {row[0]: int(row[1] or 0) for row in ec.all()}
    ur = await db.execute(select(User).order_by(User.created_at.desc()).limit(300))
    per_user = [
        {
            "user_id": str(u.id),
            "email": u.email,
            "entries_total": entry_counts.get(u.id, 0),
            "estimated_cost_inr": round(entry_counts.get(u.id, 0) * 0.25, 2),
        }
        for u in ur.scalars().all()
    ]
    return {
        **(await _api_usage_payload(settings, db)),
        "per_user": per_user,
        "generated_at": datetime.now(timezone.utc).isoformat(),
    }


@router.get("/integrations")
async def admin_integrations(
    _caller: Annotated[AdminCaller, Depends(require_admin_caller)],
    settings: Annotated[Settings, Depends(get_settings)],
):
    del _caller
    return {
        "openai": {"configured": bool(settings.openai_api_key or settings.google_ai_api_key)},
        "ocr": {"configured": bool(settings.ocr_api_key), "provider": settings.ocr_provider},
        "s3": {"configured": bool(settings.s3_bucket and settings.s3_access_key)},
        "sentry": {"configured": bool(settings.sentry_dsn)},
        "redis": {"configured": bool(settings.redis_url)},
    }


@router.get("/audit-logs")
async def admin_audit_logs(
    _caller: Annotated[AdminCaller, Depends(require_admin_caller)],
    db: Annotated[AsyncSession, Depends(get_db)],
    limit: int = Query(100, ge=1, le=500),
):
    del _caller
    r = await db.execute(
        select(AdminAuditLog).order_by(AdminAuditLog.created_at.desc()).limit(limit)
    )
    rows = r.scalars().all()
    return {
        "items": [
            {
                "id": str(x.id),
                "actor": x.actor,
                "action": x.action,
                "resource_type": x.resource_type,
                "resource_id": x.resource_id,
                "details": x.details,
                "note": x.note,
                "created_at": x.created_at.isoformat() if x.created_at else None,
            }
            for x in rows
        ],
        "total_returned": len(rows),
    }


@router.post("/env-update")
async def admin_env_update(
    _caller: Annotated[AdminCaller, Depends(require_admin_caller)],
    body: AdminEnvUpdateRequest,
):
    del _caller, body
    return {
        "ok": True,
        "deprecated": True,
        "note": "Database-backed platform integration, billing, Razorpay, and WhatsApp admin endpoints were removed for Harisree client deployment.",
    }


