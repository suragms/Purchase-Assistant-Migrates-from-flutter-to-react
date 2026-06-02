"""Expand trade purchase status lifecycle constraint."""

from __future__ import annotations

from pathlib import Path
from typing import Sequence, Union

from alembic import op

revision: str = "053_purchase_lifecycle_statuses"
down_revision: Union[str, None] = "052_stock_movement_unit_mismatch_flag"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_SQL = Path(__file__).resolve().parents[2] / "sql" / "053_purchase_lifecycle_statuses.sql"


def upgrade() -> None:
    op.execute(_SQL.read_text(encoding="utf-8"))


def downgrade() -> None:
    op.execute("ALTER TABLE trade_purchases DROP CONSTRAINT IF EXISTS trade_purchases_status_check;")
