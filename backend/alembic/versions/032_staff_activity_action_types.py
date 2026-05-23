"""Extend staff_activity_log.action_type CHECK for stock audit and operations.

Revision ID: 032_staff_activity_action_types
Revises: 031_stock_audit_business
"""

from __future__ import annotations

from pathlib import Path
from typing import Sequence, Union

from alembic import op

revision: str = "032_staff_activity_action_types"
down_revision: Union[str, None] = "031_stock_audit_business"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_SQL = Path(__file__).resolve().parents[2] / "sql" / "032_staff_activity_action_types.sql"


def upgrade() -> None:
    bind = op.get_bind()
    if bind.dialect.name != "postgresql":
        return
    if _SQL.is_file():
        op.execute(_SQL.read_text(encoding="utf-8"))


def downgrade() -> None:
    pass
