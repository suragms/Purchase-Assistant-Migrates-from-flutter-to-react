-- User system rebuild: soft delete, notes, permissions, catalog audit, activity actions

ALTER TABLE users ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;
ALTER TABLE users ADD COLUMN IF NOT EXISTS notes TEXT;

ALTER TABLE memberships ADD COLUMN IF NOT EXISTS permissions_json JSONB DEFAULT '{}'::jsonb;

ALTER TABLE catalog_items ADD COLUMN IF NOT EXISTS created_by_user_id UUID REFERENCES users(id) ON DELETE SET NULL;
ALTER TABLE catalog_items ADD COLUMN IF NOT EXISTS updated_by_user_id UUID REFERENCES users(id) ON DELETE SET NULL;

-- Extend staff_activity_log action types (drop/recreate check if present)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'staff_activity_log_action_type_check'
  ) THEN
    ALTER TABLE staff_activity_log DROP CONSTRAINT staff_activity_log_action_type_check;
  END IF;
EXCEPTION WHEN undefined_object THEN
  NULL;
END $$;

ALTER TABLE staff_activity_log ADD CONSTRAINT staff_activity_log_action_type_check
  CHECK (action_type IN (
    'SCAN','STOCK_UPDATE','ITEM_CREATE','PURCHASE_SAVE','VERIFICATION',
    'LOGIN','LOGOUT','PASSWORD_RESET'
  ));
