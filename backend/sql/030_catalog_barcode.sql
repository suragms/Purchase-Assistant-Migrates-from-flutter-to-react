-- Separate packaging barcode from internal item_code

ALTER TABLE catalog_items
  ADD COLUMN IF NOT EXISTS barcode VARCHAR(64);

-- Backfill: numeric/EAN-like item_code → barcode (legacy scan rows)
UPDATE catalog_items
SET barcode = item_code
WHERE barcode IS NULL
  AND item_code IS NOT NULL
  AND item_code ~ '^[0-9]{8,20}$'
  AND deleted_at IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_catalog_items_business_barcode
  ON catalog_items (business_id, barcode)
  WHERE barcode IS NOT NULL AND deleted_at IS NULL;
