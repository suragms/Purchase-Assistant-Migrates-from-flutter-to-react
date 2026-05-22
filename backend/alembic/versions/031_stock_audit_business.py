"""Stock audits: business_id + line reconciliation fields.

Revision ID: 031_stock_audit_business
Revises: 030_catalog_barcode
"""

from __future__ import annotations

from pathlib import Path
from typing import Sequence, Union

from alembic import op

revision: str = "031_stock_audit_business"
down_revision: Union[str, None] = "030_catalog_barcode"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_SQL = Path(__file__).resolve().parents[2] / "sql" / "031_stock_audit_business.sql"


def upgrade() -> None:
    bind = op.get_bind()
    if bind.dialect.name != "postgresql":
        return
    if _SQL.is_file():
        op.execute(_SQL.read_text(encoding="utf-8"))


def downgrade() -> None:
    pass
