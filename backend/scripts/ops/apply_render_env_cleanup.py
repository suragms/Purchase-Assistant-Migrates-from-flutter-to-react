"""Apply Render env cleanup for my-purchases-api (Harisree production).

Reads Render API token from .cursor/mcp.json (same as _render_cutover_env.py).
Resumes suspended web service + Postgres if needed, merges fixes, deletes unused keys.
"""
from __future__ import annotations

import json
import urllib.error
import urllib.request
from pathlib import Path

SERVICE_ID = "srv-d7ea0il8nd3s73e4fvl0"
POSTGRES_ID = "dpg-d8fu1p77f7vs73eooiu0-a"
_REPO = Path(__file__).resolve().parents[2]

KEYS_TO_DELETE = (
    "AUTHKEY_API_KEY",
    "AUTHKEY_FROM_NUMBER",
    "AUTHKEY_SENDER_LABEL",
    "AUTHKEY_WEBHOOK_SECRET",
    "WHATSAPP_CLOUD_ACCESS_TOKEN",
    "WHATSAPP_CLOUD_PHONE_NUMBER_ID",
    "WHATSAPP_REPORTS_CRON_SECRET",
    "WHATSAPP_LLM_AGENT",
    "WHATSAPP_LLM_REPLY",
    "SCHEMA_RECOVERY_REV",
    "HTTP_ACCESS_LOG_ALL",
    "GOOGLE_AI_API_KEY",
    "GROQ_API_KEY",
    "DIALOG360_API_KEY",
    "DIALOG360_PHONE_NUMBER_ID",
    "DIALOG360_WEBHOOK_SECRET",
    "WHATSAPP_ASSISTANT_E164",
)

KEYS_TO_SET = {
    "AI_PROVIDER": "stub",
    "APP_ENV": "production",
    "APP_URL": "https://my-purchases-api.onrender.com",
    "AUTO_MIGRATE": "0",
    "API_READ_BUDGET_SECONDS": "6",
    "AUTO_STOCK_BACKFILL_ON_START": "false",
    "CORS_ORIGINS": "https://purchase-assiastant.vercel.app,https://purchase-assistant.vercel.app",
    "DATABASE_POOL_SIZE": "5",
    "DATABASE_MAX_OVERFLOW": "10",
    "DATABASE_SSL_INSECURE": "false",
    "DATABASE_SSL_SKIP_VERIFY": "true",
    "DEV_RETURN_OTP": "false",
    "ENABLE_AI": "false",
    "ENABLE_OCR": "false",
    "LOG_LEVEL": "WARNING",
}

# Render API rejects empty string values — delete REDIS_URL so OTP uses in-memory fallback
# (default localhost URL fails ping on Render; see otp.py get_otp_store).
KEYS_TO_DELETE_WITH_REDIS = (*KEYS_TO_DELETE, "REDIS_URL")

PRESERVE_IF_SET = (
    "DATABASE_URL",
    "JWT_SECRET",
    "JWT_REFRESH_SECRET",
    "OPENAI_API_KEY",
    "SENTRY_DSN",
    "HTTP_SLOW_REQUEST_WARNING_MS",
    "HTTP_PROPAGATE_REQUEST_ID",
)


def _auth() -> str:
    mcp = json.loads((_REPO / ".cursor" / "mcp.json").read_text(encoding="utf-8"))
    token = (mcp.get("mcpServers", {}).get("render", {}).get("headers", {}).get("Authorization") or "").strip()
    return token if token.lower().startswith("bearer ") else f"Bearer {token}"


def _request(method: str, url: str, payload: object | None = None) -> tuple[int, str]:
    headers = {"Authorization": _auth(), "Accept": "application/json"}
    data = None
    if payload is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            body = resp.read().decode("utf-8", errors="replace")
            return resp.status, body
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        return e.code, body


def _get_json(url: str) -> dict | list:
    status, body = _request("GET", url)
    if status >= 400:
        raise SystemExit(f"GET {url} -> HTTP {status}: {body[:500]}")
    return json.loads(body)


def _resume_resource(kind: str, resource_id: str) -> None:
    status, body = _request("POST", f"https://api.render.com/v1/{kind}/{resource_id}/resume")
    print(f"resume {kind} {resource_id}: HTTP {status}")
    if status not in (200, 202, 409):
        print(body[:500])


def _list_env_vars() -> dict[str, str]:
    out: dict[str, str] = {}
    cursor = ""
    while True:
        url = f"https://api.render.com/v1/services/{SERVICE_ID}/env-vars?limit=100"
        if cursor:
            url += f"&cursor={cursor}"
        payload = _get_json(url)
        for row in payload:
            env = row.get("envVar") or row
            key = env.get("key") or env.get("name")
            val = env.get("value")
            if key:
                out[str(key)] = "" if val is None else str(val)
        cursor = ""
        if isinstance(payload, list) and payload:
            last = payload[-1]
            cursor = (last.get("cursor") or "").strip()
        if not cursor:
            break
    return out


def _enable_auto_deploy() -> None:
    status, body = _request(
        "PATCH",
        f"https://api.render.com/v1/services/{SERVICE_ID}",
        {"autoDeploy": "yes", "branch": "main"},
    )
    print(f"autoDeploy=yes: HTTP {status}")
    if status >= 400:
        print(body[:500])


def main() -> None:
    svc = _get_json(f"https://api.render.com/v1/services/{SERVICE_ID}")
    auto = (svc.get("autoDeploy") or svc.get("serviceDetails", {}).get("autoDeploy") or "")
    print(f"autoDeploy before={auto!r}")
    if str(auto).lower() not in ("yes", "true"):
        _enable_auto_deploy()

    suspended = (svc.get("suspended") or "").strip()
    print(f"service suspended={suspended!r}")
    if suspended == "suspended":
        _resume_resource("services", SERVICE_ID)

    pg = _get_json(f"https://api.render.com/v1/postgres/{POSTGRES_ID}")
    pg_suspended = (pg.get("suspended") or "").strip()
    print(f"postgres suspended={pg_suspended!r}")
    if pg_suspended == "suspended":
        _resume_resource("postgres", POSTGRES_ID)

    before = _list_env_vars()
    print(f"env vars before: {len(before)} keys")

    for key in KEYS_TO_DELETE_WITH_REDIS:
        if key not in before:
            continue
        status, body = _request("DELETE", f"https://api.render.com/v1/services/{SERVICE_ID}/env-vars/{key}")
        print(f"delete {key}: HTTP {status}")
        if status >= 400 and status != 404:
            print(body[:300])

    for key, value in KEYS_TO_SET.items():
        status, body = _request(
            "PUT",
            f"https://api.render.com/v1/services/{SERVICE_ID}/env-vars/{key}",
            {"value": value},
        )
        print(f"set {key}={value!r}: HTTP {status}")
        if status >= 400:
            print(body[:300])

    after = _list_env_vars()
    print(f"env vars after: {len(after)} keys")
    for k in sorted(after):
        if k in KEYS_TO_SET or k in PRESERVE_IF_SET:
            mark = " [set]" if k in KEYS_TO_SET else " [kept]"
            print(f"  {k}{mark}")
    removed = sorted(set(before) - set(after))
    if removed:
        print("removed:", ", ".join(removed))

    status, body = _request("POST", f"https://api.render.com/v1/services/{SERVICE_ID}/deploys")
    print(f"deploy triggered: HTTP {status}")
    if status >= 400:
        print(body[:500])


if __name__ == "__main__":
    main()
