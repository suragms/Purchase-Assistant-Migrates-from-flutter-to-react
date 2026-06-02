BEGIN;

ALTER TABLE trade_purchases
  DROP CONSTRAINT IF EXISTS trade_purchases_status_check;

ALTER TABLE trade_purchases
  ADD CONSTRAINT trade_purchases_status_check
  CHECK (
    status IN (
      'draft',
      'saved',
      'confirmed',
      'active',
      'approved',
      'ordered',
      'supplier_confirmed',
      'in_transit',
      'arrived',
      'verification_pending',
      'verified',
      'added_to_stock',
      'completed',
      'delivered',
      'cancelled',
      'deleted',
      'paid',
      'due_soon',
      'overdue',
      'partially_paid'
    )
  );

COMMIT;
