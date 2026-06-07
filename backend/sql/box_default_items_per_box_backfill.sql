-- Box catalog rows: default_items_per_box = 1 when missing (single retail boxes).
-- Safe to run multiple times.

UPDATE catalog_items
SET default_items_per_box = 1,
    package_type = COALESCE(NULLIF(TRIM(package_type), ''), 'BOX'),
    stock_unit = COALESCE(NULLIF(TRIM(stock_unit), ''), 'BOX')
WHERE deleted_at IS NULL
  AND LOWER(COALESCE(default_unit, '')) = 'box'
  AND (default_items_per_box IS NULL OR default_items_per_box <= 0);

-- Name contains BOX but still tracked as piece — align for commit-stock (optional).
UPDATE catalog_items
SET default_unit = 'box',
    default_items_per_box = 1,
    package_type = 'BOX',
    stock_unit = 'BOX'
WHERE deleted_at IS NULL
  AND LOWER(COALESCE(default_unit, 'piece')) IN ('piece', 'pcs')
  AND UPPER(name) LIKE '% BOX%'
  AND (default_items_per_box IS NULL OR default_items_per_box <= 0);
