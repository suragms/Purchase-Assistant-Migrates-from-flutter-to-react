"""Catalog: packaging barcode column separate from item_code.

Revision ID: 030_catalog_barcode
Revises: 029_stockease_operations
"""

from __future__ import annotations

from pathlib import Path
from typing import Sequence, Union

from alembic import op

revision: str = "030_catalog_barcode"
down_revision: Union[str, None] = "029_stockease_operations"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_SQL = Path(__file__).resolve().parents[2] / "sql" / "030_catalog_barcode.sql"


def upgrade() -> None:
    bind = op.get_bind()
    if bind.dialect.name != "postgresql":
        return
    if _SQL.is_file():
        op.execute(_SQL.read_text(encoding="utf-8"))


def downgrade() -> None:
    pass
