"""Add stock_movements.unit_mismatch_flag for conversion diagnostics."""

from __future__ import annotations

from pathlib import Path
from typing import Sequence, Union

from alembic import op

revision: str = "052_stock_movement_unit_mismatch_flag"
down_revision: Union[str, None] = "051_delivery_discrepancy_and_lifecycle"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_SQL = Path(__file__).resolve().parents[2] / "sql" / "052_stock_movement_unit_mismatch_flag.sql"


def upgrade() -> None:
    op.execute(_SQL.read_text(encoding="utf-8"))


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS ix_stock_movements_unit_mismatch_flag;")
    op.execute("ALTER TABLE stock_movements DROP COLUMN IF EXISTS unit_mismatch_flag;")
