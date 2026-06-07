import asyncio
import json
import logging
import os
import re
import time
import uuid
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Any

from fastapi import FastAPI
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError, ProgrammingError, SQLAlchemyError
from starlette.exceptions import HTTPException as StarletteHTTPException
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.middleware.trustedhost import TrustedHostMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse

from app.config import get_settings
from app.db_resilience import is_sa_infrastructure_failure

from app.database import async_session_factory, engine, is_sqlite_runtime
from app.sqlite_bootstrap import apply_sqlite_bootstrap
from app.routers import (
    admin,
    analytics,
    auth,
    catalog,
    contacts,
    dashboard,
    entries,
    exports,
    health,
    internal_cron,
    me,
    media,
    price_intelligence,
    public_items,
    public_barcode,
    realtime,
    reports_trade,
    report_views,
    search,
    trade_purchases,
    damage_reports,
    stock,
    stock_audits,
    operations,
    users,
    notifications,
)

logger = logging.getLogger(__name__)

_BUSINESS_ROUTE_PREFIX_RE = re.compile(r"^/v1/businesses/([^/]+)/")

_GET_CACHE_CONTROL_RULES: tuple[tuple[re.Pattern[str], int], ...] = (
    (re.compile(r"^/v1/businesses/[^/]+/stock/list(?:/compact)?$"), 30),
    (re.compile(r"^/v1/businesses/[^/]+/stock/delivery-indicator-counts$"), 30),
    (re.compile(r"^/v1/businesses/[^/]+/dashboard$"), 60),
    (re.compile(r"^/v1/businesses/[^/]+/reports/home-overview$"), 60),
    (re.compile(r"^/v1/businesses/[^/]+/catalog-items$"), 120),
)


def _apply_get_cache_control(request: Request, response) -> None:
    if request.method != "GET":
        return
    if response.status_code < 200 or response.status_code >= 300:
        return
    if response.headers.get("cache-control"):
        return
    path = request.url.path
    for pattern, max_age in _GET_CACHE_CONTROL_RULES:
        if pattern.search(path):
            response.headers["Cache-Control"] = f"private, max-age={max_age}"
            return


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings = get_settings()
    settings.validate_production_safety()
    logging.basicConfig(level=getattr(logging, settings.log_level.upper(), logging.INFO))

    if settings.sentry_dsn:
        try:
            import sentry_sdk

            sentry_sdk.init(
                dsn=settings.sentry_dsn,
                environment=settings.app_env,
                traces_sample_rate=0.1 if settings.app_env == "production" else 0.0,
            )
            logger.info("Sentry initialized")
        except Exception as e:  # noqa: BLE001
            logger.warning("Sentry init failed: %s", e)

    logger.info(
        "Observability: log_level=%s slow_http_warning_ms=%s request_id_echo=%s "
        "sentry=%s db_slow_query_ms=%s api_read_budget_s=%s http_access_log_all=%s",
        settings.log_level,
        settings.http_slow_request_warning_ms,
        settings.http_propagate_request_id,
        bool(settings.sentry_dsn),
        settings.database_slow_query_log_ms,
        settings.api_read_budget_seconds,
        getattr(settings, "http_access_log_all", False),
    )

    async with engine.begin() as conn:
        if is_sqlite_runtime():
            await conn.run_sync(apply_sqlite_bootstrap)
        else:
            logger.info(
                "Postgres: schema is managed by Alembic only — run `alembic upgrade head` before deploy. "
                "Startup does not execute create_all or ad-hoc ALTERs."
            )

    if not is_sqlite_runtime() and os.getenv("AUTO_MIGRATE", "").strip() in {"1", "true", "TRUE", "yes", "YES"}:
        try:
            from alembic import command
            from alembic.config import Config

            # Render start command does `cd backend && uvicorn ...`, so `alembic.ini`
            # is often available as a relative path. We keep a few fallbacks to
            # avoid fragile assumptions about the current working directory.
            candidates = [
                Path("alembic.ini"),
                Path(__file__).resolve().parents[2] / "alembic.ini",
                Path(__file__).resolve().parents[3] / "alembic.ini",
            ]
            ini_path = next((p for p in candidates if p.exists()), None)
            if ini_path is None:
                raise RuntimeError("alembic.ini not found (AUTO_MIGRATE enabled)")

            cfg = Config(str(ini_path))
            # Defensive: if config did not load, force the script location.
            if not cfg.get_main_option("script_location"):
                cfg.set_main_option("script_location", "alembic")
            command.upgrade(cfg, "head")
            logger.info("Alembic: upgraded to head (AUTO_MIGRATE enabled)")
        except Exception as e:  # noqa: BLE001
            logger.exception("Alembic: upgrade failed (AUTO_MIGRATE enabled): %s", e)
            raise

    if not is_sqlite_runtime():
        try:
            async with async_session_factory() as sess:
                await sess.execute(text("SELECT 1"))
            logger.info("Postgres warmup: SELECT 1 ok")
        except Exception as e:  # noqa: BLE001
            logger.warning(
                "Postgres warmup failed (non-fatal) | %s | %s",
                type(e).__name__,
                e,
            )
        run_backfill = os.getenv("AUTO_STOCK_BACKFILL_ON_START", "true").strip().lower()
        if run_backfill not in {"0", "false", "no"}:
            try:
                from scripts.backfill_purchase_stock_commit import run as run_stock_backfill

                await run_stock_backfill(business_id=None, dry_run=False)
                logger.info("Stock backfill: startup repair completed")
            except Exception as e:  # noqa: BLE001
                logger.warning("Stock backfill skipped/failed: %s", e, exc_info=True)

    low_stock_task: asyncio.Task | None = None
    idle_delivery_task: asyncio.Task | None = None

    async def _low_stock_notify_hourly() -> None:
        """Best-effort hourly scan: items below reorder → per-user notification rows."""
        await asyncio.sleep(60)
        from app.services.low_stock_notifications import run_low_stock_notification_scan

        while True:
            try:
                async with async_session_factory() as db:
                    n = await run_low_stock_notification_scan(db)
                    if n:
                        logger.info("low_stock_notification_scan: queued %s new notifications", n)
            except asyncio.CancelledError:
                raise
            except Exception as e:  # noqa: BLE001
                logger.warning("low_stock_notification_scan failed: %s", e, exc_info=True)
            await asyncio.sleep(3600)

    async def _idle_delivery_notify_hourly() -> None:
        await asyncio.sleep(120)
        from app.services.scheduled_notification_jobs import (
            run_idle_delivery_notification_scan,
        )

        while True:
            try:
                async with async_session_factory() as db:
                    n = await run_idle_delivery_notification_scan(db)
                    if n:
                        logger.info("idle_delivery_scan: queued %s notifications", n)
            except asyncio.CancelledError:
                raise
            except Exception as e:  # noqa: BLE001
                logger.warning("idle_delivery_scan failed: %s", e, exc_info=True)
            await asyncio.sleep(3600)

    try:
        low_stock_task = asyncio.create_task(_low_stock_notify_hourly())
        idle_delivery_task = asyncio.create_task(_idle_delivery_notify_hourly())
        logger.info("Background: low_stock hourly notification task started")
    except Exception as e:  # noqa: BLE001
        logger.warning("Background: low_stock task not started: %s", e)

    scheduler = None
    try:
        from zoneinfo import ZoneInfo

        from apscheduler.schedulers.asyncio import AsyncIOScheduler

        scheduler = AsyncIOScheduler(timezone=ZoneInfo("Asia/Kolkata"))

        def _due_soon_tick() -> None:
            """Hook: scan due-soon trade purchases; extend with DB + push/WhatsApp if needed."""
            logger.info("due_soon_reminder: tick (use app.services.monthly_payment_reminder)")

        async def _evening_physical_tick() -> None:
            from app.services.scheduled_notification_jobs import (
                run_evening_physical_count_reminder,
            )

            try:
                async with async_session_factory() as sess:
                    n = await run_evening_physical_count_reminder(sess)
                    if n:
                        logger.info("evening_physical_reminder: %s notifications", n)
            except Exception as e:  # noqa: BLE001
                logger.warning("evening_physical_reminder failed: %s", e, exc_info=True)

        async def _db_keepalive_tick() -> None:
            """Best-effort Postgres keepalive for hosted free-tier databases."""
            if is_sqlite_runtime():
                return
            try:
                async with async_session_factory() as sess:
                    await sess.execute(text("SELECT 1"))
                logger.info("db_keepalive: SELECT 1 ok")
            except Exception as e:  # noqa: BLE001
                logger.warning("db_keepalive failed: %s", e, exc_info=True)

        scheduler.add_job(
            _due_soon_tick, "cron", hour=8, minute=0, id="due_soon_scan", replace_existing=True
        )
        scheduler.add_job(
            _evening_physical_tick,
            "cron",
            hour=18,
            minute=0,
            id="evening_physical_reminder",
            replace_existing=True,
        )
        scheduler.add_job(
            _db_keepalive_tick,
            "interval",
            hours=48,
            id="db_keepalive",
            replace_existing=True,
        )
        scheduler.start()
        logger.info("APScheduler: due_soon and db_keepalive jobs registered")
    except Exception as e:  # noqa: BLE001
        logger.warning("APScheduler not started: %s", e)

    yield
    for task in (low_stock_task, idle_delivery_task):
        if task is not None:
            task.cancel()
            try:
                await task
            except asyncio.CancelledError:
                pass
            except Exception:  # noqa: BLE001
                pass
    if scheduler is not None:
        try:
            scheduler.shutdown(wait=False)
        except Exception:  # noqa: BLE001
            pass
    await engine.dispose()


app = FastAPI(title="Harisree Warehouse API", lifespan=lifespan)


def _http_measurement_payload(
    *,
    request: Request,
    response,
    duration_ms: int,
    business_id: str,
    request_id: str,
    slow: bool,
    read_budget_exceeded: bool,
) -> dict[str, Any]:
    return {
        "event": "http_request",
        "method": request.method,
        "path": request.url.path,
        "status_code": response.status_code,
        "duration_ms": duration_ms,
        "business_id": business_id or None,
        "request_id": request_id or None,
        "slow": slow,
        "read_budget_exceeded": read_budget_exceeded,
    }


@app.middleware("http")
async def harisree_request_monitor_middleware(request: Request, call_next):
    cfg = get_settings()
    rid = ""
    if cfg.http_propagate_request_id:
        rid = request.headers.get("x-request-id", "").strip()
        if not rid:
            rid = str(uuid.uuid4())
        elif len(rid) > 96:
            rid = rid[:96]
        setattr(request.state, "request_id", rid)
    bid = ""
    mpath = _BUSINESS_ROUTE_PREFIX_RE.match(request.url.path)
    if mpath:
        bid = mpath.group(1)

    start = time.perf_counter()
    response = await call_next(request)
    ms = int((time.perf_counter() - start) * 1000)
    if cfg.http_propagate_request_id and rid:
        response.headers.setdefault("X-Request-Id", rid)
        response.headers["X-Process-Time-Ms"] = str(ms)
    response.headers.setdefault("X-Response-Time", f"{ms}ms")
    _apply_get_cache_control(request, response)

    slow_ms = getattr(cfg, "http_slow_request_warning_ms", None) or 0
    is_slow = slow_ms > 0 and ms >= slow_ms
    budget_ms = int(max(0.0, float(cfg.api_read_budget_seconds)) * 1000)
    path = request.url.path
    heavy_read = (
        budget_ms > 0
        and ms >= budget_ms
        and request.method == "GET"
        and (
            "/reports/" in path
            or path.rstrip("/").endswith("/catalog-items")
            or path.rstrip("/").endswith("/item-categories")
        )
    )
    log_json = (
        cfg.http_access_log_all
        or path.startswith("/v1/businesses")
        or is_slow
        or heavy_read
        or response.status_code >= 400
    )
    if log_json:
        logger.info(
            "HTTP_JSON %s",
            json.dumps(
                _http_measurement_payload(
                    request=request,
                    response=response,
                    duration_ms=ms,
                    business_id=bid,
                    request_id=rid,
                    slow=is_slow,
                    read_budget_exceeded=heavy_read,
                ),
                default=str,
            ),
        )
    if heavy_read:
        logger.warning(
            "READ_BUDGET_EXCEEDED %sms | budget_ms=%s | %s %s business_id=%s request_id=%s",
            ms,
            budget_ms,
            request.method,
            path,
            bid or "-",
            rid or "-",
        )
    if slow_ms > 0 and ms >= slow_ms:
        logger.warning(
            "SLOW_HTTP %sms | %s %s status=%s business_id=%s request_id=%s",
            ms,
            request.method,
            request.url.path,
            response.status_code,
            bid or "-",
            rid or "-",
        )
    if response.status_code >= 500:
        logger.error(
            "HTTP %s | %sms | %s %s business_id=%s request_id=%s",
            response.status_code,
            ms,
            request.method,
            request.url.path,
            bid or "-",
            rid or "-",
        )
    elif response.status_code >= 400:
        logger.warning(
            "HTTP %s | %sms | %s %s business_id=%s request_id=%s",
            response.status_code,
            ms,
            request.method,
            request.url.path,
            bid or "-",
            rid or "-",
        )
    elif ms > 3000:
        logger.warning(
            "VERY_SLOW_HTTP %sms | %s %s business_id=%s request_id=%s",
            ms,
            request.method,
            request.url.path,
            bid or "-",
            rid or "-",
        )
    return response


@app.middleware("http")
async def app_requested_with_guard(request: Request, call_next):
    """Lightweight CSRF hardening for browser-origin state-changing requests."""
    method = request.method.upper()
    if method not in {"GET", "HEAD", "OPTIONS"}:
        path = request.url.path
        exempt = (
            path.startswith("/internal/")
            or path.startswith("/health")
            or path.startswith("/static/")
            or path.startswith("/v1/auth/")
            or path.startswith("/public/")
        )
        origin = request.headers.get("origin", "").strip()
        referer = request.headers.get("referer", "").strip()
        browser_like = bool(origin or referer)
        if browser_like and not exempt:
            xrw = request.headers.get("x-requested-with", "").strip().lower()
            if xrw != "harisree-app":
                return JSONResponse(
                    status_code=403,
                    content={"detail": "Missing required app request header"},
                )
    return await call_next(request)


_backend_root = Path(__file__).resolve().parent.parent
_static_root = _backend_root / "static"
_static_root.mkdir(exist_ok=True)
(_static_root / "branding").mkdir(exist_ok=True)
app.mount("/static", StaticFiles(directory=str(_static_root)), name="static")

settings = get_settings()
# Browsers reject Access-Control-Allow-Origin: * together with credentialed requests.
# Flutter web (localhost / 127.0.0.1) needs explicit origins when using Authorization headers.
# If CORS_ORIGINS is set but omits Flutter web (e.g. only :5173), the browser hides response bodies
# from JS — Dio looks like "network error" while DevTools may still show 4xx/5xx.
_DEFAULT_LOCAL_CORS_ORIGINS = [
    "http://localhost:8080",
    "http://127.0.0.1:8080",
    "http://localhost:8082",
    "http://127.0.0.1:8082",
    "http://localhost:5173",
    "http://127.0.0.1:5173",
    "http://localhost:5174",
    "http://127.0.0.1:5174",
    "http://localhost:5175",
    "http://127.0.0.1:5175",
    "http://localhost:3000",
    "http://127.0.0.1:3000",
    "http://localhost:8081",
    "http://127.0.0.1:8081",
    "http://localhost:8090",
    "http://127.0.0.1:8090",
    "http://localhost:8091",
    "http://127.0.0.1:8091",
    "http://localhost:8092",
    "http://127.0.0.1:8092",
]
_origins = [o.strip() for o in settings.cors_origins.split(",") if o.strip()]
# Canonical Harisree production web (Vercel). Single hostname — do not add assistant/assastant typos.
_CANONICAL_PROD_WEB = "https://purchase-assiastant.vercel.app"
if settings.app_env.lower() == "production" and _CANONICAL_PROD_WEB not in _origins:
    _origins.append(_CANONICAL_PROD_WEB)
logger.info("CORS origins (%d): %s", len(_origins), _origins)
if not _origins:
    _origins = list(_DEFAULT_LOCAL_CORS_ORIGINS)
elif settings.app_env.lower() == "development":
    _seen = set(_origins)
    for _o in _DEFAULT_LOCAL_CORS_ORIGINS:
        if _o not in _seen:
            _origins.append(_o)
            _seen.add(_o)
_cors_kwargs = dict(
    allow_origins=_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
# Flutter web `flutter run -d chrome` often picks a random port; listing every port in CORS_ORIGINS is impractical.
# In development only, allow any http(s) localhost / 127.0.0.1 origin. Production must set explicit CORS_ORIGINS.
if settings.app_env.lower() == "development":
    # Flutter web may be served as http://[::1]:PORT on some systems — include IPv6 loopback.
    _cors_kwargs["allow_origin_regex"] = (
        r"https?://(localhost|127\.0\.0\.1|\[::1\])(:\d+)?$"
    )


class ForceCORSOnErrorMiddleware(BaseHTTPMiddleware):
    """Ensure 4xx/5xx responses include CORS headers when Origin is allowed.

    Uncaught errors can bypass CORSMiddleware header injection; browsers then hide
    the response body and Flutter web surfaces a generic network/CORS failure.
    """

    def __init__(
        self,
        app,
        *,
        allow_origins: list[str],
        allow_origin_regex: str | None = None,
    ):
        super().__init__(app)
        self._allow_origins = allow_origins
        self._origin_re = (
            re.compile(allow_origin_regex) if allow_origin_regex else None
        )

    def _origin_allowed(self, origin: str) -> bool:
        if origin in self._allow_origins:
            return True
        return bool(self._origin_re and self._origin_re.fullmatch(origin))

    async def dispatch(self, request: Request, call_next):
        response = await call_next(request)
        if response.status_code < 400:
            return response
        origin = request.headers.get("origin", "").strip()
        if not origin or not self._origin_allowed(origin):
            return response
        if "access-control-allow-origin" not in {
            k.lower() for k in response.headers
        }:
            response.headers["Access-Control-Allow-Origin"] = origin
            response.headers["Access-Control-Allow-Credentials"] = "true"
            response.headers["Vary"] = "Origin"
        return response


app.add_middleware(
    ForceCORSOnErrorMiddleware,
    allow_origins=_origins,
    allow_origin_regex=_cors_kwargs.get("allow_origin_regex"),
)
app.add_middleware(CORSMiddleware, **_cors_kwargs)

if settings.trusted_hosts:
    hosts = [h.strip() for h in settings.trusted_hosts.split(",") if h.strip()]
    if hosts:
        app.add_middleware(TrustedHostMiddleware, allowed_hosts=hosts)

app.include_router(health.router)
if (settings.whatsapp_reports_cron_secret or "").strip():
    app.include_router(internal_cron.router)
app.include_router(auth.router)
app.include_router(me.router)
app.include_router(entries.router)
app.include_router(exports.router)
app.include_router(trade_purchases.router)
app.include_router(damage_reports.router)
app.include_router(reports_trade.router)
app.include_router(report_views.router)
app.include_router(search.router)
app.include_router(analytics.router)
app.include_router(dashboard.router)
if settings.enable_ai:
    app.include_router(price_intelligence.router)
app.include_router(catalog.router)
app.include_router(contacts.router)
if settings.s3_bucket:
    app.include_router(media.router)
app.include_router(public_items.router)
app.include_router(public_barcode.router)
app.include_router(realtime.router)
app.include_router(notifications.router)
app.include_router(admin.router)
app.include_router(stock_audits.router)
app.include_router(stock.router)
app.include_router(operations.router)
app.include_router(users.router)
app.include_router(users.activity_router)


_FAILSAFE_GET_TRADE_LIST = re.compile(r"^/v1/businesses/[^/]+/trade-purchases$")
_FAILSAFE_GET_DASHBOARD = re.compile(r"^/v1/businesses/[^/]+/dashboard$")
_FAILSAFE_GET_TRADE_SNAPSHOT = re.compile(r"^/v1/businesses/[^/]+/reports/trade-dashboard-snapshot$")
_FAILSAFE_GET_HOME_OVERVIEW = re.compile(r"^/v1/businesses/[^/]+/reports/home-overview$")
_FAILSAFE_GET_TRADE_SUMMARY = re.compile(r"^/v1/businesses/[^/]+/reports/trade-summary$")


def _block_db_empty_shape_paths(path: str) -> bool:
    """Avoid synthetic empty payloads for auth, membership, admin, health."""
    return (
        path.startswith("/v1/auth/")
        or path.startswith("/v1/me")
        or path.startswith("/v1/admin")
        or path in ("/health", "/openapi.json")
    )


def _empty_trade_dashboard_snapshot_payload(request: Request) -> dict[str, Any]:
    q = request.query_params
    return {
        "from": q.get("from") or "",
        "to": q.get("to") or "",
        "summary": {
            "deals": 0,
            "total_purchase": 0.0,
            "total_landing": 0.0,
            "total_selling": 0.0,
            "total_profit": 0.0,
            "profit_percent": None,
            "total_qty": 0.0,
        },
        "unit_totals": {
            "total_kg": 0.0,
            "total_bags": 0.0,
            "total_boxes": 0.0,
            "total_tins": 0.0,
        },
        "categories": [],
        "subcategories": [],
        "item_slices": [],
        "suppliers": [],
        "recommendations": [],
        "consistency": {"portfolio_score": None},
    }


def _get_db_failsafe_body(request: Request) -> dict[str, Any] | list[Any] | None:
    path = request.url.path
    if _FAILSAFE_GET_TRADE_LIST.match(path):
        return []
    if _FAILSAFE_GET_DASHBOARD.match(path):
        return {
            "month": "service-unavailable",
            "total_purchase": 0.0,
            "total_paid": 0.0,
            "pending": 0.0,
            "total_profit": 0.0,
            "purchase_count": 0,
            "categories": [],
            "items": [],
        }
    if _FAILSAFE_GET_TRADE_SNAPSHOT.match(path):
        return _empty_trade_dashboard_snapshot_payload(request)
    if _FAILSAFE_GET_HOME_OVERVIEW.match(path):
        return _empty_trade_dashboard_snapshot_payload(request)
    if _FAILSAFE_GET_TRADE_SUMMARY.match(path):
        return {
            "deals": 0,
            "total_purchase": 0.0,
            "total_qty": 0.0,
            "avg_cost": 0.0,
            "unit_totals": {
                "total_kg": 0.0,
                "total_bags": 0.0,
                "total_boxes": 0.0,
                "total_tins": 0.0,
            },
        }
    return None


@app.exception_handler(SQLAlchemyError)
async def sqlalchemy_exception_handler(request: Request, exc: SQLAlchemyError):
    hdrs = {"X-Database-Unavailable": "1"}
    cfg = get_settings()
    path = request.url.path

    if isinstance(exc, IntegrityError):
        logger.warning(
            "SQLAlchemy IntegrityError | %s %s",
            request.method,
            path,
            exc_info=True,
        )
        return JSONResponse(status_code=409, content={"detail": "integrity_error"})

    if isinstance(exc, ProgrammingError):
        logger.exception(
            "SQLAlchemy ProgrammingError | %s %s",
            request.method,
            path,
        )
        return JSONResponse(status_code=500, content={"error": "SERVER_TEMPORARY_ISSUE"})

    if not is_sa_infrastructure_failure(exc):
        logger.exception(
            "SQLAlchemy logical error | %s %s",
            request.method,
            path,
        )
        return JSONResponse(status_code=500, content={"error": "SERVER_TEMPORARY_ISSUE"})

    logger.warning(
        "SQLAlchemy infrastructure | %s | %s %s",
        type(exc).__name__,
        request.method,
        path,
        exc_info=True,
    )
    payload = {"detail": "database_unavailable", "error": "SERVER_TEMPORARY_ISSUE"}
    if request.method != "GET":
        return JSONResponse(status_code=503, content=payload, headers=hdrs)
    if cfg.database_get_read_failsafe and not _block_db_empty_shape_paths(path):
        fb = _get_db_failsafe_body(request)
        if fb is not None:
            # 200 + X-Database-Unavailable: clients treat body as normal JSON (empty list /
            # zeroed dashboard) while still surfacing degraded mode from the header.
            return JSONResponse(status_code=200, content=fb, headers=hdrs)
    return JSONResponse(status_code=503, content=payload, headers=hdrs)


@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    """Never leak tracebacks / SQL to clients — full detail stays in logs."""
    if isinstance(exc, RequestValidationError):
        return JSONResponse(
            status_code=422,
            content={"detail": exc.errors()},
        )
    if isinstance(exc, StarletteHTTPException):
        detail = exc.detail
        payload: dict
        if isinstance(detail, dict):
            payload = dict(detail)
        else:
            payload = {"detail": detail}
        return JSONResponse(status_code=exc.status_code, content=payload)
    logger.exception(
        "Unhandled | %s %s",
        request.method,
        request.url.path,
    )
    return JSONResponse(
        status_code=500,
        content={"error": "SERVER_TEMPORARY_ISSUE"},
    )
