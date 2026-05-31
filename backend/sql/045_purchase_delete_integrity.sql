-- Purchase delete/cancel integrity: align delivery_status and catalog last-trade snapshots.
-- Safe to re-run (idempotent data repair + optional index).

-- 1) Deleted/cancelled POs must not remain in a pending delivery state.
UPDATE trade_purchases
SET delivery_status = 'cancelled'
WHERE status IN ('deleted', 'cancelled')
  AND COALESCE(delivery_status, 'pending') NOT IN ('cancelled', 'stock_committed');

-- 2) Clear catalog snapshots that still point at deleted/cancelled purchases.
UPDATE catalog_items ci
SET
  last_trade_purchase_id = NULL,
  last_line_qty = NULL,
  last_line_unit = NULL,
  last_line_weight_kg = NULL
FROM trade_purchases tp
WHERE tp.id = ci.last_trade_purchase_id
  AND ci.deleted_at IS NULL
  AND tp.status IN ('deleted', 'cancelled');

-- 3) Repoint items with no snapshot to their newest active purchase line.
WITH latest AS (
  SELECT DISTINCT ON (tpl.catalog_item_id)
    tpl.catalog_item_id,
    tp.id AS tp_id,
    tpl.qty,
    tpl.unit
  FROM trade_purchase_lines tpl
  INNER JOIN trade_purchases tp ON tp.id = tpl.trade_purchase_id
  WHERE tpl.catalog_item_id IS NOT NULL
    AND tp.status NOT IN ('deleted', 'cancelled', 'draft')
  ORDER BY tpl.catalog_item_id, tp.purchase_date DESC, tp.created_at DESC
)
UPDATE catalog_items ci
SET
  last_trade_purchase_id = l.tp_id,
  last_line_qty = l.qty,
  last_line_unit = LEFT(COALESCE(l.unit, ''), 32)
FROM latest l
WHERE ci.id = l.catalog_item_id
  AND ci.deleted_at IS NULL
  AND ci.last_trade_purchase_id IS NULL;

-- 4) Speed up pending-truck queries on stock list.
CREATE INDEX IF NOT EXISTS ix_trade_purchases_pending_delivery
  ON trade_purchases (business_id, purchase_date DESC)
  WHERE status NOT IN ('deleted', 'cancelled', 'draft')
    AND COALESCE(delivery_status, 'pending') NOT IN ('stock_committed', 'cancelled');
