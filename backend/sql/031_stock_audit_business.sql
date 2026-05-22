-- Stock audits: business scope + line metadata for reconciliation apply.

ALTER TABLE stock_audits
  ADD COLUMN IF NOT EXISTS business_id UUID REFERENCES businesses(id) ON DELETE CASCADE;

UPDATE stock_audits sa
SET business_id = sub.bid
FROM (
  SELECT sa2.id AS aid, m.business_id AS bid
  FROM stock_audits sa2
  JOIN memberships m ON m.user_id = sa2.auditor_id
  WHERE sa2.business_id IS NULL
  ORDER BY m.created_at ASC
) sub
WHERE sa.id = sub.aid AND sa.business_id IS NULL;

CREATE INDEX IF NOT EXISTS ix_stock_audits_business_status
  ON stock_audits (business_id, status, audit_date DESC);

ALTER TABLE stock_audit_items
  ADD COLUMN IF NOT EXISTS line_status VARCHAR(32) NOT NULL DEFAULT 'recorded',
  ADD COLUMN IF NOT EXISTS adjustment_type VARCHAR(32),
  ADD COLUMN IF NOT EXISTS reason TEXT,
  ADD COLUMN IF NOT EXISTS notes TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS uq_stock_audit_items_audit_item
  ON stock_audit_items (audit_id, item_id);
