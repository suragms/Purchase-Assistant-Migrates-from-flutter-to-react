-- Harisree Warehouse Master Fix v3 — production parity (idempotent).
-- Verified on Supabase 2026-05-24 via MCP: critical columns already present.
-- Safe to re-run on Render/Supabase; no-op when applied.

ALTER TABLE catalog_items ADD COLUMN IF NOT EXISTS current_stock NUMERIC(12, 3) DEFAULT 0;
ALTER TABLE catalog_items ADD COLUMN IF NOT EXISTS reorder_level NUMERIC(12, 3) DEFAULT 0;
ALTER TABLE catalog_items ADD COLUMN IF NOT EXISTS rack_location VARCHAR(100);
ALTER TABLE catalog_items ADD COLUMN IF NOT EXISTS last_stock_updated_at TIMESTAMPTZ;
ALTER TABLE catalog_items ADD COLUMN IF NOT EXISTS last_stock_updated_by VARCHAR(255);
ALTER TABLE catalog_items ADD COLUMN IF NOT EXISTS barcode VARCHAR(64);

ALTER TABLE trade_purchases ADD COLUMN IF NOT EXISTS is_delivered BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE trade_purchase_lines ADD COLUMN IF NOT EXISTS qty_in_stock_unit NUMERIC(12, 3);
