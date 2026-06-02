ALTER TABLE stock_movements
  ADD COLUMN IF NOT EXISTS unit_mismatch_flag BOOLEAN NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS ix_stock_movements_unit_mismatch_flag
  ON stock_movements (business_id, unit_mismatch_flag, created_at DESC)
  WHERE unit_mismatch_flag = true;
