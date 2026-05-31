"""Purchase delete integrity: repair snapshots + pending delivery index.

Revision ID: 045_purchase_delete_integrity
Revises: 044_catalog_current_stock_non_negative
"""

from __future__ import annotations

from pathlib import Path
from typing import Sequence, Union

from alembic import op

revision: str = "045_purchase_delete_integrity"
down_revision: Union[str, None] = "044_catalog_current_stock_non_negative"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_SQL = Path(__file__).resolve().parents[2] / "sql" / "045_purchase_delete_integrity.sql"


def upgrade() -> None:
    op.execute(_SQL.read_text(encoding="utf-8"))


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS ix_trade_purchases_pending_delivery;")
