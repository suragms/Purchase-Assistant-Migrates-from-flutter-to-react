"""Enable RLS business isolation policies for public tables with business_id."""

from __future__ import annotations

from pathlib import Path
from typing import Sequence, Union

from alembic import op

revision: str = "054_enable_rls_business_policies"
down_revision: Union[str, None] = "053_purchase_lifecycle_statuses"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_SQL = Path(__file__).resolve().parents[2] / "sql" / "054_enable_rls_business_policies.sql"


def upgrade() -> None:
    op.execute(_SQL.read_text(encoding="utf-8"))


def downgrade() -> None:
    op.execute(
        """
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT schemaname, tablename
    FROM pg_policies
    WHERE schemaname = 'public' AND policyname = 'p_business_isolation'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS p_business_isolation ON %I.%I', r.schemaname, r.tablename);
  END LOOP;
END $$;
        """
    )
