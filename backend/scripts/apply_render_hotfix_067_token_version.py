"""Hotfix: add users.token_version on Render Postgres (login 503 when column missing).

Safe to re-run (IF NOT EXISTS). Does not change alembic_version — prod may use
065_api_storm_hotpath_indexes while repo chain uses 065_archive_legacy_entries_tables.
"""
from __future__ import annotations

import json
import urllib.request
from pathlib import Path

POSTGRES_ID = "dpg-d8fu1p77f7vs73eooiu0-a"
_REPO = Path(__file__).resolve().parents[2]
_SQL = _REPO / "backend" / "sql" / "067_user_token_version.sql"


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

    sql = _SQL.read_text(encoding="utf-8")
    conn = psycopg2.connect(_external_url())
    conn.autocommit = True
    cur = conn.cursor()
    cur.execute("SELECT version_num FROM alembic_version LIMIT 1")
    row = cur.fetchone()
    print(f"alembic_version: {row[0] if row else None}")

    cur.execute(
        """
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'users'
          AND column_name = 'token_version'
        LIMIT 1
        """
    )
    before = cur.fetchone()
    print(f"token_version column before: {'yes' if before else 'no'}")

    if before:
        print("Column already present — nothing to do.")
    else:
        cur.execute(sql)
        print("Applied 067_user_token_version.sql")

    cur.execute(
        """
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'users'
          AND column_name = 'token_version'
        LIMIT 1
        """
    )
    after = cur.fetchone()
    print(f"token_version column after: {'yes' if after else 'no'}")
    cur.close()
    conn.close()


if __name__ == "__main__":
    main()
