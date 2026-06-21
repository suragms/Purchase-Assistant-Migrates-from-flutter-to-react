"""Apply SQL 065 on Render Postgres (API storm hot-path indexes).

Auth from .cursor/mcp.json Render token (same as apply_render_upgrade_064.py).
"""
from __future__ import annotations

import json
import urllib.request
from pathlib import Path

POSTGRES_ID = "dpg-d8fu1p77f7vs73eooiu0-a"
_REPO = Path(__file__).resolve().parents[2]
_BACKEND = _REPO / "backend"
_SQL = _BACKEND / "sql" / "065_api_storm_hotpath_indexes.sql"
_TARGET = "065_api_storm_hotpath_indexes"
_PREVIOUS = "064_pg_report_line_indexes"


def _auth() -> str:
    mcp_path = _REPO / ".cursor" / "mcp.json"
    if not mcp_path.is_file():
        raise SystemExit("Missing .cursor/mcp.json with render API token")
    mcp = json.loads(mcp_path.read_text(encoding="utf-8"))
    servers = mcp.get("mcpServers", {})
    token = ""
    for key in ("render", "project-0-Purchase Assistant-render"):
        hdr = (servers.get(key, {}).get("headers") or {}).get("Authorization") or ""
        if hdr.strip():
            token = hdr.strip()
            break
    if not token:
        raise SystemExit("No render Authorization in mcp.json")
    return token if token.lower().startswith("bearer ") else f"Bearer {token}"


def _get(url: str) -> dict:
    req = urllib.request.Request(
        url, headers={"Authorization": _auth(), "Accept": "application/json"}
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.load(resp)


def _external_url() -> str:
    info = _get(f"https://api.render.com/v1/postgres/{POSTGRES_ID}/connection-info")
    url = (
        info.get("externalConnectionString")
        or info.get("external_connection_string")
        or ""
    ).strip()
    if not url:
        raise SystemExit("No external connection string from Render API")
    return url


def main() -> None:
    try:
        import psycopg2
    except ImportError:
        raise SystemExit("pip install psycopg2-binary") from None

    url = _external_url()
    sql = _SQL.read_text(encoding="utf-8")

    conn = psycopg2.connect(url)
    conn.autocommit = False
    cur = conn.cursor()
    cur.execute("SELECT version_num FROM alembic_version LIMIT 1")
    before = cur.fetchone()
    print(f"alembic_version before: {before[0] if before else None}")

    if before and before[0] == _TARGET:
        print("Already at 065 — nothing to do.")
        cur.close()
        conn.close()
        return

    if before and before[0] != _PREVIOUS:
        raise SystemExit(f"Unexpected alembic head {before[0]!r}; aborting.")

    cur.execute(sql)
    cur.execute("UPDATE alembic_version SET version_num = %s", (_TARGET,))
    conn.commit()
    print("Applied 065_api_storm_hotpath_indexes.sql")

    cur.execute("SELECT version_num FROM alembic_version LIMIT 1")
    after = cur.fetchone()
    print(f"alembic_version after: {after[0] if after else None}")
    cur.close()
    conn.close()


if __name__ == "__main__":
    main()
