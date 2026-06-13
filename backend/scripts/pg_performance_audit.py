"""Read-only PostgreSQL performance audit for Harisree Purchase Assistant.

Runs EXPLAIN (ANALYZE, BUFFERS) on representative hot-path queries and writes
docs/perf/pg_audit_<date>.md. Safe for staging/production read replicas.

Usage:
  cd backend && python scripts/pg_performance_audit.py
  DATABASE_URL=postgresql://... python scripts/pg_performance_audit.py --business-id <uuid>
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import date
from pathlib import Path

_REPO = Path(__file__).resolve().parents[2]
_DOCS = _REPO / "docs" / "perf"


def _connect_url() -> str:
    url = (os.environ.get("DATABASE_URL") or "").strip()
    if not url:
        raise SystemExit("Set DATABASE_URL (postgresql://...)")
    if url.startswith("postgresql+asyncpg://"):
        url = "postgresql://" + url.removeprefix("postgresql+asyncpg://")
    elif url.startswith("postgres://"):
        url = "postgresql://" + url.removeprefix("postgres://")
    return url


def _explain(cur, label: str, sql: str, params: tuple) -> dict:
    cur.execute(f"EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) {sql}", params)
    row = cur.fetchone()
    plan = row[0] if row else []
    if isinstance(plan, str):
        plan = json.loads(plan)
    root = plan[0] if plan else {}
    timing = root.get("Plan", {}).get("Actual Total Time") or root.get("Execution Time")
    node_type = root.get("Plan", {}).get("Node Type", "?")
    flags: list[str] = []
    if node_type == "Seq Scan":
        flags.append("seq_scan")
    if timing and float(timing) > 100:
        flags.append("slow_100ms")
    if timing and float(timing) > 10 and node_type in ("Nested Loop", "Hash Join"):
        flags.append("heavy_join")
    return {
        "label": label,
        "timing_ms": timing,
        "node_type": node_type,
        "flags": flags,
        "plan": root,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="PostgreSQL hot-path EXPLAIN audit")
    parser.add_argument("--business-id", default="", help="Sample business UUID for scoped queries")
    args = parser.parse_args()

    try:
        import psycopg2
        from psycopg2.extras import RealDictCursor
    except ImportError:
        raise SystemExit("pip install psycopg2-binary") from None

    bid = args.business_id.strip()
    if not bid:
        conn_probe = psycopg2.connect(_connect_url())
        conn_probe.autocommit = True
        cur = conn_probe.cursor()
        cur.execute("SELECT id FROM businesses ORDER BY created_at DESC LIMIT 1")
        row = cur.fetchone()
        cur.close()
        conn_probe.close()
        if not row:
            raise SystemExit("No businesses row — pass --business-id")
        bid = str(row[0])

    conn = psycopg2.connect(_connect_url())
    conn.autocommit = True
    cur = conn.cursor(cursor_factory=RealDictCursor)

    sections: list[str] = [
        f"# PostgreSQL performance audit — {date.today().isoformat()}",
        "",
        f"Sample `business_id`: `{bid}`",
        "",
    ]

    # pg_stat_statements (optional)
    cur.execute(
        "SELECT 1 FROM pg_extension WHERE extname = 'pg_stat_statements'"
    )
    if cur.fetchone():
        cur.execute(
            """
            SELECT LEFT(query, 120) AS query,
                   calls,
                   ROUND(mean_exec_time::numeric, 2) AS mean_ms,
                   ROUND(total_exec_time::numeric, 2) AS total_ms
            FROM pg_stat_statements
            WHERE query NOT LIKE '%pg_stat_statements%'
            ORDER BY mean_exec_time DESC
            LIMIT 15
            """
        )
        rows = cur.fetchall()
        sections.append("## Top pg_stat_statements (mean time)")
        sections.append("")
        sections.append("| mean_ms | calls | query |")
        sections.append("|--------:|------:|-------|")
        for r in rows:
            q = (r["query"] or "").replace("|", "\\|").replace("\n", " ")
            sections.append(f"| {r['mean_ms']} | {r['calls']} | `{q}` |")
        sections.append("")
    else:
        sections.append("## pg_stat_statements")
        sections.append("")
        sections.append("Extension not enabled. On Render Postgres: `CREATE EXTENSION pg_stat_statements;`")
        sections.append("")

    # Index inventory for hot tables
    for table in (
        "trade_purchases",
        "trade_purchase_lines",
        "catalog_items",
        "stock_movements",
        "stock_adjustment_logs",
        "app_notifications",
    ):
        cur.execute(
            """
            SELECT indexname, indexdef
            FROM pg_indexes
            WHERE tablename = %s
            ORDER BY indexname
            """,
            (table,),
        )
        idx = cur.fetchall()
        sections.append(f"## Indexes on `{table}`")
        sections.append("")
        if not idx:
            sections.append("_none_")
        else:
            for r in idx:
                sections.append(f"- `{r['indexname']}`")
        sections.append("")

    explains: list[dict] = []
    std = _explain(
        cur,
        "trade_purchases_list",
        """
        SELECT tp.id FROM trade_purchases tp
        WHERE tp.business_id = %s::uuid
          AND tp.status NOT IN ('deleted', 'cancelled')
        ORDER BY tp.purchase_date DESC
        LIMIT 50
        """,
        (bid,),
    )
    explains.append(std)

    explains.append(
        _explain(
            cur,
            "delivery_pipeline",
            """
            SELECT delivery_status, COUNT(*) FROM trade_purchases
            WHERE business_id = %s::uuid
              AND status NOT IN ('deleted', 'cancelled')
            GROUP BY delivery_status
            """,
            (bid,),
        )
    )

    explains.append(
        _explain(
            cur,
            "stock_adjustment_recent",
            """
            SELECT id FROM stock_adjustment_logs
            WHERE business_id = %s::uuid
            ORDER BY updated_at DESC
            LIMIT 250
            """,
            (bid,),
        )
    )

    explains.append(
        _explain(
            cur,
            "notifications_unread",
            """
            SELECT COUNT(*) FROM app_notifications
            WHERE business_id = %s::uuid
              AND read_at IS NULL
            """,
            (bid,),
        )
    )

    explains.append(
        _explain(
            cur,
            "catalog_active_items",
            """
            SELECT id FROM catalog_items
            WHERE business_id = %s::uuid AND deleted_at IS NULL
            ORDER BY lower(name)
            LIMIT 200
            """,
            (bid,),
        )
    )

    sections.append("## EXPLAIN ANALYZE hot paths")
    sections.append("")
    sections.append("| Query | ms | Node | Flags |")
    sections.append("|-------|---:|------|-------|")
    for ex in explains:
        flags = ", ".join(ex["flags"]) if ex["flags"] else "ok"
        ms = ex.get("timing_ms")
        ms_s = f"{float(ms):.2f}" if ms is not None else "?"
        sections.append(
            f"| {ex['label']} | {ms_s} | {ex['node_type']} | {flags} |"
        )
    sections.append("")

    slow = [e for e in explains if "slow_100ms" in e["flags"]]
    seq = [e for e in explains if "seq_scan" in e["flags"]]
    if slow or seq:
        sections.append("## Recommendations")
        sections.append("")
        if seq:
            sections.append("- Review seq scans above; apply migration 063 partial indexes if missing.")
        if slow:
            sections.append("- Queries over 100ms: add composite indexes or narrow SELECT columns.")
        sections.append("")

    _DOCS.mkdir(parents=True, exist_ok=True)
    out_path = _DOCS / f"pg_audit_{date.today().isoformat()}.md"
    out_path.write_text("\n".join(sections) + "\n", encoding="utf-8")
    print(f"Wrote {out_path}")
    cur.close()
    conn.close()


if __name__ == "__main__":
    main()
