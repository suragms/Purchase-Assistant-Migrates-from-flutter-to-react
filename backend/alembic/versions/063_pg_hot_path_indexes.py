"""Phase 1 PostgreSQL hot-path indexes.

Revision ID: 063_pg_hot_path_indexes
Revises: 062_trade_report_indexes
"""

from __future__ import annotations

from pathlib import Path
from typing import Sequence, Union

from alembic import op

revision: str = "063_pg_hot_path_indexes"
down_revision: Union[str, None] = "062_trade_report_indexes"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_SQL = Path(__file__).resolve().parents[2] / "sql" / "063_pg_hot_path_indexes.sql"


def upgrade() -> None:
    op.execute(_SQL.read_text(encoding="utf-8"))


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS ix_stock_adjustment_logs_biz_item_updated;")
    op.execute("DROP INDEX IF EXISTS ix_app_notifications_biz_user_unread;")
