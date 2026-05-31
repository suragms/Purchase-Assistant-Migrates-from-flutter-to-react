-- Staff warehouse verify: persist received/damaged/return per line for stock commit.
ALTER TABLE trade_purchase_lines
  ADD COLUMN IF NOT EXISTS received_qty NUMERIC(12, 3),
  ADD COLUMN IF NOT EXISTS damaged_qty NUMERIC(12, 3),
  ADD COLUMN IF NOT EXISTS return_qty NUMERIC(12, 3);
