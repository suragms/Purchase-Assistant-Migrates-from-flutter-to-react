-- Phase 1 hot-path indexes (Postgres). Safe IF NOT EXISTS; skip missing tables.

DO $$
BEGIN
  IF to_regclass('public.app_notifications') IS NOT NULL THEN
    CREATE INDEX IF NOT EXISTS ix_app_notifications_biz_user_unread
      ON app_notifications (business_id, user_id)
      WHERE read_at IS NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF to_regclass('public.stock_adjustment_logs') IS NOT NULL THEN
    CREATE INDEX IF NOT EXISTS ix_stock_adjustment_logs_biz_item_updated
      ON stock_adjustment_logs (business_id, item_id, updated_at DESC);
  END IF;
END $$;

-- Delivery pipeline already covered by 060:
-- ix_trade_purchases_biz_delivery_status ON (business_id, delivery_status, updated_at DESC)
