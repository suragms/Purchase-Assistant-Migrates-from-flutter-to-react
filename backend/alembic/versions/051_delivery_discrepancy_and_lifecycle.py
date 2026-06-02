"""Delivery discrepancy tracking, lifecycle events, and DB performance indexes."""

from __future__ import annotations

from pathlib import Path
from typing import Sequence, Union

from alembic import op

revision: str = "051_delivery_discrepancy_and_lifecycle"
down_revision: Union[str, None] = "050_stock_ledger_replay_current_stock"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_SQL = Path(__file__).resolve().parents[2] / "sql" / "051_delivery_discrepancy_and_lifecycle.sql"


def upgrade() -> None:
    op.execute(_SQL.read_text(encoding="utf-8"))


def downgrade() -> None:
    op.execute("DROP FUNCTION IF EXISTS cleanup_report_saved_views(interval);")
    op.execute("DROP INDEX IF EXISTS ix_report_saved_views_created_at;")
    op.execute("ALTER TABLE report_saved_views DROP COLUMN IF EXISTS is_pinned;")
    op.execute("DROP INDEX IF EXISTS idx_trade_purchases_biz_status_date;")
    op.execute("DROP INDEX IF EXISTS idx_staff_activity_log_biz_date;")
    op.execute("DROP INDEX IF EXISTS idx_stock_movements_item_date;")
    op.execute("DROP INDEX IF EXISTS idx_trade_purchase_lines_catalog_item_id;")
    op.execute("DROP INDEX IF EXISTS idx_tpl_biz_date_item;")
    op.execute("DROP INDEX IF EXISTS idx_dd_unresolved;")
    op.execute("DROP INDEX IF EXISTS idx_dd_business_date;")
    op.execute("DROP INDEX IF EXISTS idx_dd_purchase;")
    op.execute("DROP TABLE IF EXISTS delivery_discrepancies;")
    op.execute("DROP INDEX IF EXISTS idx_ple_business;")
    op.execute("DROP INDEX IF EXISTS idx_ple_purchase;")
    op.execute("DROP TABLE IF EXISTS purchase_lifecycle_events;")
