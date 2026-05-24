import asyncio
import logging
import time

from fastapi import APIRouter, Depends
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession
from starlette.responses import JSONResponse, Response

from app.config import Settings, get_settings
from app.database import get_db

router = APIRouter(tags=["health"])
logger = logging.getLogger("harisree.health")


@router.get("/")
async def root():
    """Avoid a bare 404 at the API origin — browsers often open `/` first."""
    return {
        "service": "Harisree Warehouse API",
        "docs": "/docs",
        "openapi_json": "/openapi.json",
        "health": "/health",
        "health_ready": "/health/ready",
        "hint": "The operator admin app is the Vite dev server (see ADMIN_URL in backend settings), path /login.",
    }


@router.head("/")
async def root_head():
    """Uptime probes often use HEAD; without this, Starlette returns 405 for HEAD /."""
    return Response(status_code=200)


@router.get("/health")
async def health(settings: Settings = Depends(get_settings)):
    """Liveness + non-secret config hints for ops (Render/Vercel smoke tests)."""
    prov = (settings.ai_provider or "stub").strip().lower()
    gemini_k = bool((settings.google_ai_api_key or "").strip())
    groq_k = bool((settings.groq_api_key or "").strip())
    openai_k = bool((settings.openai_api_key or "").strip())
    ai_key_env = bool(gemini_k or groq_k or openai_k)
    # Assistant always usable (stub rules + grounded queries); LLM intent needs provider + key.
    ai_ready = prov == "stub" or ai_key_env
    # Failover-ready when any key exists (Gemini -> Groq -> OpenAI order at runtime).
    llm_failover_ready = ai_key_env and bool(settings.enable_ai)
    intent_llm_active = llm_failover_ready
    if intent_llm_active:
        ai_status = "llm_ready"
    elif prov == "stub" or not prov:
        ai_status = "rules_only"
    else:
        ai_status = "missing_api_key"
    return {
        "status": "ok",
        "app_env": settings.app_env,
        "ai_provider": prov,
        "ai_keys_set_in_env": ai_key_env,
        "gemini_key_set_in_env": gemini_k,
        "groq_key_set_in_env": groq_k,
        "openai_key_set_in_env": openai_k,
        "llm_failover_ready": llm_failover_ready,
        "enable_ai": settings.enable_ai,
        "ai_ready": ai_ready,
        "intent_llm_active": intent_llm_active,
        "ai_status": ai_status,
        "assistant_ready": True,
        "redis_url_set": bool((settings.redis_url or "").strip()),
    }


@router.get("/health/ready")
async def health_ready(db: AsyncSession = Depends(get_db)):
    """Readiness for load balancers (Render health checks, uptime monitors).

    Returns **200** when `SELECT 1` succeeds; **503** if the database is unreachable.
    Response includes **db_ms** — use Render logs + `SLOW_HTTP` / `HTTP 503` to correlate.
    """
    t0 = time.perf_counter()
    try:
        await asyncio.wait_for(db.execute(text("SELECT 1")), timeout=3.0)
    except Exception:  # noqa: BLE001
        logger.exception("health_ready: SELECT 1 failed")
        ms = int((time.perf_counter() - t0) * 1000)
        return JSONResponse(
            status_code=503,
            content={
                "status": "unhealthy",
                "db": "down",
                "db_ms": ms,
            },
        )
    ms = int((time.perf_counter() - t0) * 1000)
    return {"status": "ok", "db": "ok", "db_ms": ms}


@router.get("/health/db-check")
async def health_db_check(db: AsyncSession = Depends(get_db)):
    """Verify core ORM tables respond (SQLite / Postgres)."""
    try:
        await db.execute(text("SELECT COUNT(*) FROM trade_purchases"))
        await db.execute(text("SELECT COUNT(*) FROM item_categories"))
        return {"status": "ok", "tables": "trade_purchases, item_categories verified"}
    except Exception as e:  # noqa: BLE001
        logger.exception("db-check failed")
        return {"status": "error", "detail": str(e)}
