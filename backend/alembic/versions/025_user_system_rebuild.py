"""User system rebuild: deleted_at, notes, permissions_json, catalog audit columns.

Revision ID: 025_user_system_rebuild
Revises: 024_harisree_sql_parity
"""

from __future__ import annotations

from pathlib import Path
from typing import Sequence, Union

from alembic import op

revision: str = "025_user_system_rebuild"
down_revision: Union[str, None] = "024_harisree_sql_parity"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_SQL = Path(__file__).resolve().parents[2] / "sql" / "027_user_system_rebuild.sql"


def upgrade() -> None:
    bind = op.get_bind()
    if bind.dialect.name != "postgresql":
        return
    if _SQL.is_file():
        op.execute(_SQL.read_text(encoding="utf-8"))


def downgrade() -> None:
    pass
