-- Extend staff_activity_log.action_type CHECK for stock, delivery, and WhatsApp audit codes.

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'staff_activity_log_action_type_check'
  ) THEN
    ALTER TABLE staff_activity_log DROP CONSTRAINT staff_activity_log_action_type_check;
  END IF;
EXCEPTION WHEN undefined_table THEN
  NULL;
END $$;

ALTER TABLE staff_activity_log ADD CONSTRAINT staff_activity_log_action_type_check
  CHECK (action_type IN (
    'SCAN',
    'STOCK_UPDATE',
    'STOCK_PHYSICAL_UPDATE',
    'STOCK_CORRECTION_RECORDED',
    'STOCK_DAMAGE_RECORDED',
    'STOCK_SALE_ADJUSTMENT',
    'STOCK_QUICK_PURCHASE',
    'OPENING_STOCK_SET',
    'PHYSICAL_STOCK_COUNT',
    'ITEM_CREATE',
    'ITEM_UPDATE',
    'PURCHASE_SAVE',
    'PURCHASE_EDIT',
    'PURCHASE_CREATE',
    'PURCHASE_DISPATCHED',
    'PURCHASE_ARRIVED',
    'PURCHASE_VERIFIED',
    'PURCHASE_STOCK_COMMITTED',
    'PURCHASE_WHATSAPP_SENT',
    'PURCHASE_WHATSAPP_FAILED',
    'VERIFICATION',
    'LOGIN',
    'LOGOUT',
    'PASSWORD_RESET',
    'USER_CREATE',
    'USER_BLOCK',
    'USER_DELETE',
    'BARCODE_PRINT',
    'BARCODE_COUNT_VERIFY',
    'REPORT_EXPORT',
    'DELETE_ACTION',
    'CHECKLIST_COMPLETE',
    'USAGE_LOG',
    'STOCK_AUDIT_LINE',
    'STOCK_AUDIT_COMPLETE'
  ));
