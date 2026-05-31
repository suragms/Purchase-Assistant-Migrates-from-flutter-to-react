"""Purchase line received qty for warehouse verify → stock commit."""

from alembic import op

revision = "047_purchase_line_received_qty"
down_revision = "046_report_saved_views"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """
        ALTER TABLE trade_purchase_lines
          ADD COLUMN IF NOT EXISTS received_qty NUMERIC(12, 3),
          ADD COLUMN IF NOT EXISTS damaged_qty NUMERIC(12, 3),
          ADD COLUMN IF NOT EXISTS return_qty NUMERIC(12, 3);
        """
    )


def downgrade() -> None:
    op.execute(
        """
        ALTER TABLE trade_purchase_lines
          DROP COLUMN IF EXISTS return_qty,
          DROP COLUMN IF EXISTS damaged_qty,
          DROP COLUMN IF EXISTS received_qty;
        """
    )
