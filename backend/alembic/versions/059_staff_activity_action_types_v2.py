"""Extend staff_activity_log action_type CHECK for stock and delivery codes.

Revision ID: 059_staff_activity_action_types_v2
Revises: 058_barcode_lookup_indexes
"""

from __future__ import annotations

from pathlib import Path
from typing import Sequence, Union

from alembic import op

revision: str = "059_staff_activity_action_types_v2"
down_revision: Union[str, None] = "058_barcode_lookup_indexes"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_SQL = Path(__file__).resolve().parents[2] / "sql" / "059_staff_activity_action_types_v2.sql"


def upgrade() -> None:
    op.execute(_SQL.read_text(encoding="utf-8"))


def downgrade() -> None:
    sql_032 = Path(__file__).resolve().parents[2] / "sql" / "032_staff_activity_action_types.sql"
    if sql_032.is_file():
        op.execute(sql_032.read_text(encoding="utf-8"))
