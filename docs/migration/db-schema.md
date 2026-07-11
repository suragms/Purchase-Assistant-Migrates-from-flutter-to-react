# Database Schema — Purchase Assistant (PostgreSQL)

Reverse-engineered from `backend/app/models/*.py` and `backend/sql/*.sql` (applied in numeric order). 44 tables across 29 model files.

---

## Conventions

- All tables have `id UUID PRIMARY KEY DEFAULT gen_random_uuid()` unless noted
- All tables have `created_at TIMESTAMPTZ DEFAULT now()` unless noted
- All business-scoped tables have `business_id UUID REFERENCES businesses(id)` — RLS enforced via migration 054
- `deleted_at TIMESTAMPTZ` used for soft-delete (filtered `WHERE deleted_at IS NULL` in queries)
- Units canonical set: `BAG`, `KG`, `BOX`, `TIN`, `PIECE` (+ display variants `PC`, `PCS`, `SACK`, `LOOSE`)

---

## 1. Core & Users

### `businesses`
| Column | Type | Constraints |
|--------|------|-------------|
| id | UUID | PK |
| name | VARCHAR(255) | NOT NULL |
| branding_title | VARCHAR(128) | |
| branding_logo_url | VARCHAR(512) | |
| gst_number | VARCHAR(20) | |
| address | TEXT | |
| phone | VARCHAR(32) | |
| contact_email | VARCHAR(255) | |
| default_currency | VARCHAR(3) | NOT NULL DEFAULT 'INR' |
| created_at | TIMESTAMPTZ | NOT NULL DEFAULT now() |

### `users`
| Column | Type | Constraints |
|--------|------|-------------|
| id | UUID | PK |
| email | VARCHAR(320) | UNIQUE, NOT NULL |
| username | VARCHAR(64) | UNIQUE, NOT NULL |
| password_hash | VARCHAR(255) | nullable (Google-only users) |
| name | VARCHAR(255) | |
| phone | VARCHAR(32) | UNIQUE |
| google_sub | VARCHAR(128) | UNIQUE |
| ai_monthly_token_budget | INTEGER | DEFAULT 100000 |
| ai_tokens_used_month | INTEGER | DEFAULT 0 |
| is_active | BOOLEAN | DEFAULT true |
| is_super_admin | BOOLEAN | DEFAULT false |
| is_blocked | BOOLEAN | DEFAULT false |
| notes | VARCHAR(2000) | |
| device_info | JSONB | |
| token_version | INTEGER | DEFAULT 0 (migration 067) |
| created_by | UUID | FK → users(id) |
| last_login_at | TIMESTAMPTZ | |
| last_active_at | TIMESTAMPTZ | |
| deleted_at | TIMESTAMPTZ | |
| created_at | TIMESTAMPTZ | NOT NULL |

Indexes: `ix_users_email`, `ix_users_google_sub`, `ix_users_username`

### `memberships`
| Column | Type | Constraints |
|--------|------|-------------|
| id | UUID | PK |
| user_id | UUID | FK → users(id), NOT NULL |
| business_id | UUID | FK → businesses(id), NOT NULL |
| role | VARCHAR(32) | NOT NULL — one of: owner, admin, manager, staff, viewer, super_admin |
| permissions_json | JSONB | Granular permission overrides |
| created_at | TIMESTAMPTZ | NOT NULL |

Indexes: `ix_memberships_user_id`, `ix_memberships_business_id`; UNIQUE(user_id, business_id)

### `user_sessions` (migration 022/027)
| Column | Type | Constraints |
|--------|------|-------------|
| id | UUID | PK |
| user_id | UUID | FK → users(id) |
| business_id | UUID | FK → businesses(id) |
| login_at | TIMESTAMPTZ | |
| is_active | BOOLEAN | DEFAULT true |

### `password_reset_tokens`
| Column | Type | Constraints |
|--------|------|-------------|
| id | UUID | PK |
| user_id | UUID | FK → users(id), NOT NULL |
| token_hash | VARCHAR(255) | NOT NULL |
| expires_at | TIMESTAMPTZ | NOT NULL |
| used_at | TIMESTAMPTZ | |
| created_at | TIMESTAMPTZ | NOT NULL |

---

## 2. Catalog

### `item_categories`
| Column | Type | Constraints |
|--------|------|-------------|
| id | UUID | PK |
| business_id | UUID | FK → businesses(id), NOT NULL |
| name | VARCHAR(255) | NOT NULL |
| created_at | TIMESTAMPTZ | NOT NULL |

### `category_types` (subcategories)
| Column | Type | Constraints |
|--------|------|-------------|
| id | UUID | PK |
| category_id | UUID | FK → item_categories(id), NOT NULL |
| name | VARCHAR(255) | NOT NULL |
| created_at | TIMESTAMPTZ | NOT NULL |

### `catalog_items` (65+ columns)

| Column | Type | Constraints |
|--------|------|-------------|
| id | UUID | PK |
| business_id | UUID | FK → businesses(id), NOT NULL |
| category_id | UUID | FK → item_categories(id), NOT NULL |
| type_id | UUID | FK → category_types(id), nullable |
| name | VARCHAR(512) | NOT NULL |
| normalized_name | VARCHAR(512) | |
| default_unit | VARCHAR(32) | nullable (bag\|kg\|box\|tin\|piece) |
| default_purchase_unit | VARCHAR(32) | |
| default_sale_unit | VARCHAR(32) | |
| selling_unit | VARCHAR(32) | |
| stock_unit | VARCHAR(32) | |
| display_unit | VARCHAR(32) | |
| package_type | VARCHAR(32) | SACK\|LOOSE\|BOX\|TIN\|PIECE |
| package_size | NUMERIC(14,4) | |
| package_measurement | VARCHAR(16) | KG\|PC |
| package_volume | NUMERIC(14,4) | |
| package_weight | NUMERIC(14,4) | |
| conversion_factor | NUMERIC(14,6) | |
| default_kg_per_bag | NUMERIC(12,3) | |
| default_items_per_box | NUMERIC(12,3) | |
| default_weight_per_tin | NUMERIC(12,3) | |
| hsn_code | VARCHAR(32) | |
| item_code | VARCHAR(64) | |
| barcode | VARCHAR(64) | |
| public_token | VARCHAR(64) | UNIQUE |
| tax_percent | NUMERIC(5,2) | |
| default_landing_cost | NUMERIC(12,2) | |
| default_selling_cost | NUMERIC(12,2) | |
| reorder_level | NUMERIC(12,3) | DEFAULT 0 |
| current_stock | NUMERIC(12,3) | DEFAULT 0 |
| opening_stock_qty | NUMERIC(12,3) | |
| opening_stock_set_at | TIMESTAMPTZ | |
| opening_stock_set_by | VARCHAR(255) | |
| opening_stock_locked | BOOLEAN | DEFAULT false |
| rack_location | VARCHAR(100) | |
| stock_version | INTEGER | DEFAULT 0 (optimistic locking) |
| auto_detect_enabled | BOOLEAN | DEFAULT true |
| validation_status | VARCHAR(32) | |
| ai_detected_unit | VARCHAR(32) | |
| smart_classification | VARCHAR(64) | |
| unit_confidence | NUMERIC(5,2) | |
| packaging_confidence | NUMERIC(5,2) | |
| is_loose_item | BOOLEAN | |
| is_packaged_item | BOOLEAN | |
| ml_profile | JSON | |
| last_purchase_price | NUMERIC(12,2) | |
| last_selling_rate | NUMERIC(12,2) | |
| last_supplier_id | UUID | FK → suppliers(id) |
| last_broker_id | UUID | FK → brokers(id) |
| last_trade_purchase_id | UUID | FK → trade_purchases(id) |
| last_line_qty | NUMERIC(12,3) | |
| last_line_unit | VARCHAR(32) | |
| last_line_weight_kg | NUMERIC(14,3) | |
| last_purchase_at | TIMESTAMPTZ | |
| eviction_days | INTEGER | |
| last_stock_updated_at | TIMESTAMPTZ | |
| last_stock_updated_by | VARCHAR(255) | |
| created_by_user_id | UUID | FK → users(id) |
| updated_by_user_id | UUID | FK → users(id) |
| deleted_at | TIMESTAMPTZ | |
| archived_at | TIMESTAMPTZ | |
| created_at | TIMESTAMPTZ | |

**Indexes:** `ix_catalog_items_business_id`, `ix_catalog_items_category_id`, `ix_catalog_items_barcode`, `ix_catalog_items_item_code`, `ix_catalog_items_name_lower`, `ix_catalog_items_stock`, `ix_catalog_items_public_token`, `ix_catalog_items_last_supplier_id`, `ix_catalog_items_last_broker_id`, `ix_catalog_items_last_trade_purchase_id`

### `catalog_variants`
| Column | Type | Constraints |
|--------|------|-------------|
| id | UUID | PK |
| business_id | UUID | FK → businesses(id) |
| catalog_item_id | UUID | FK → catalog_items(id) |
| name | VARCHAR(512) | NOT NULL |
| default_kg_per_bag | NUMERIC(10,3) | |

### `catalog_item_default_suppliers`
| Column | Type | Constraints |
|--------|------|-------------|
| id | UUID | PK |
| business_id | UUID | FK → businesses(id) |
| catalog_item_id | UUID | FK → catalog_items(id) |
| supplier_id | UUID | FK → suppliers(id) |
| sort_order | INTEGER | DEFAULT 0 |

### `catalog_item_default_brokers`
| Column | Type | Constraints |
|--------|------|-------------|
| id | UUID | PK |
| business_id | UUID | FK → businesses(id) |
| catalog_item_id | UUID | FK → catalog_items(id) |
| broker_id | UUID | FK → brokers(id) |
| sort_order | INTEGER | DEFAULT 0 |

### `supplier_item_defaults`
| Column | Type | Constraints |
|--------|------|-------------|
| id | UUID | PK |
| business_id | UUID | FK → businesses(id) |
| catalog_item_id | UUID | FK → catalog_items(id) |
| supplier_id | UUID | FK → suppliers(id) |
| last_price | NUMERIC(12,2) | |
| last_discount | NUMERIC(5,2) | |
| last_payment_days | INTEGER | |
| purchase_count | INTEGER | DEFAULT 0 |
| created_at | TIMESTAMPTZ | |

---

## 3. Contacts

### `suppliers`
| Column | Type | Constraints |
|--------|------|-------------|
| id | UUID | PK |
| business_id | UUID | FK → businesses(id) |
| name | VARCHAR(255) | NOT NULL |
| phone | VARCHAR(32) | |
| location | VARCHAR(255) | |
| broker_id | UUID | FK → brokers(id) (primary broker, legacy) |
| gst_number | VARCHAR(15) | |
| address | TEXT | |
| notes | TEXT | |
| default_payment_days | INTEGER | |
| default_discount | NUMERIC(5,2) | |
| default_delivered_rate | NUMERIC(12,2) | |
| default_billty_rate | NUMERIC(12,2) | |
| freight_type | VARCHAR(16) | CHECK(included, separate) |
| ai_memory_enabled | BOOLEAN | DEFAULT false |
| preferences_json | TEXT | JSON string of preferred categories/items |
| created_at | TIMESTAMPTZ | |

### `brokers`
| Column | Type | Constraints |
|--------|------|-------------|
| id | UUID | PK |
| business_id | UUID | FK → businesses(id) |
| name | VARCHAR(255) | NOT NULL |
| phone | VARCHAR(15) | |
| location | VARCHAR(255) | |
| notes | TEXT | |
| commission_type | VARCHAR(16) | CHECK(percent, flat), DEFAULT 'percent' |
| commission_value | NUMERIC(12,2) | |
| default_payment_days | INTEGER | |
| default_discount | NUMERIC(5,2) | |
| default_delivered_rate | NUMERIC(12,2) | |
| default_billty_rate | NUMERIC(12,2) | |
| freight_type | VARCHAR(16) | CHECK(included, separate) |
| image_url | VARCHAR(1024) | |
| preferences_json | TEXT | |
| created_at | TIMESTAMPTZ | |

### `broker_supplier_m2m`
| Column | Type | Constraints |
|--------|------|-------------|
| id | UUID | PK |
| broker_id | UUID | FK → brokers(id) |
| supplier_id | UUID | FK → suppliers(id) |

Indexes: UNIQUE(broker_id, supplier_id)

---

## 4. Trade Purchases

### `trade_purchases`
| Column | Type | Constraints |
|--------|------|-------------|
| id | UUID | PK |
| business_id | UUID | FK → businesses(id) |
| user_id | UUID | FK → users(id) |
| human_id | VARCHAR(64) | NOT NULL (PUR-YYYY-NNNN) |
| purchase_date | DATE | NOT NULL |
| supplier_id | UUID | FK → suppliers(id) |
| broker_id | UUID | FK → brokers(id) |
| total_amount | NUMERIC(14,2) | |
| paid_amount | NUMERIC(14,2) | DEFAULT 0 |
| discount | NUMERIC(5,2) | |
| payment_days | INTEGER | |
| commission_type | VARCHAR(16) | |
| commission_value | NUMERIC(12,2) | |
| commission_money | NUMERIC(12,2) | |
| freight_type | VARCHAR(16) | |
| freight_charge | NUMERIC(12,2) | |
| notes | TEXT | |
| delivery_status | VARCHAR(32) | (migration 040) |
| delivery_date | DATE | |
| dispatch_date | DATE | |
| dispatch_note | TEXT | (migration 041) |
| delivered_by | VARCHAR(128) | |
| received_by | VARCHAR(128) | |
| vehicle_number | VARCHAR(32) | |
| verified_by | UUID | FK → users(id) |
| status | VARCHAR(32) | NOT NULL — lifecycle (migration 053) |
| deleted_at | TIMESTAMPTZ | |
| created_at | TIMESTAMPTZ | |
| updated_at | TIMESTAMPTZ | |

**Status lifecycle** (migration 053): draft → pending → dispatched → arrived → staff_verifying → staff_verified → stock_committed. Also: paid, overdue, due_soon, cancelled, partial.

### `trade_purchase_lines`
| Column | Type | Constraints |
|--------|------|-------------|
| id | UUID | PK |
| trade_purchase_id | UUID | FK → trade_purchases(id) |
| catalog_item_id | UUID | FK → catalog_items(id), nullable |
| item_name | VARCHAR(512) | NOT NULL |
| qty | NUMERIC(12,3) | NOT NULL |
| unit | VARCHAR(16) | NOT NULL |
| qty_in_stock_unit | NUMERIC(12,3) | (migration 033b) |
| landing_cost | NUMERIC(12,2) | NOT NULL |
| selling_rate | NUMERIC(12,2) | |
| selling_cost | NUMERIC(12,2) | |
| line_total | NUMERIC(14,2) | |
| profit | NUMERIC(14,2) | |
| discount_pct | NUMERIC(5,2) | |
| tax_mode | VARCHAR(8) | CHECK(inclusive, exclusive) (migration 024) |
| tax_percent | NUMERIC(5,2) | |
| kg_per_unit | NUMERIC(12,4) | |
| total_weight | NUMERIC(14,4) | |
| landing_cost_per_kg | NUMERIC(14,4) | |
| received_qty | NUMERIC(12,3) | (migration 047) |
| damaged_qty | NUMERIC(12,3) | |
| return_qty | NUMERIC(12,3) | |
| sort_order | INTEGER | |

### `trade_purchase_drafts`
| Column | Type | Constraints |
|--------|------|-------------|
| id | UUID | PK |
| business_id | UUID | FK → businesses(id) |
| user_id | UUID | FK → users(id) |
| step | VARCHAR(32) | |
| payload | JSONB | |
| created_at | TIMESTAMPTZ | |
| updated_at | TIMESTAMPTZ | |

UNIQUE(business_id, user_id)

### `purchase_lifecycle_events` (migration 051)
| Column | Type | Constraints |
|--------|------|-------------|
| id | UUID | PK |
| trade_purchase_id | UUID | FK → trade_purchases(id) |
| from_status | VARCHAR(32) | |
| to_status | VARCHAR(32) | |
| actor_id | UUID | FK → users(id) |
| notes | TEXT | |
| metadata | JSONB | |
| created_at | TIMESTAMPTZ | |

### `purchase_damage_reports` (migration 056/057)
| Column | Type | Constraints |
|--------|------|-------------|
| id | UUID | PK |
| business_id | UUID | FK → businesses(id) |
| trade_purchase_id | UUID | FK → trade_purchases(id) |
| catalog_item_id | UUID | FK → catalog_items(id) |
| reported_by | UUID | FK → users(id) |
| item_name | VARCHAR(512) | |
| qty_damaged | NUMERIC(12,3) | |
| unit | VARCHAR(16) | |
| damage_type | VARCHAR(32) | |
| status | VARCHAR(32) | DEFAULT 'pending' |
| reason | TEXT | |
| photo_url | VARCHAR(1024) | |
| notes | TEXT | |
| resolution_notes | TEXT | |
| damage_items_in_batch | JSONB | |
| created_at | TIMESTAMPTZ | |

---

## 5. Stock & Warehouse

### `stock_adjustment_log`
| Column | Type | Constraints |
|--------|------|-------------|
| id | UUID | PK |
| business_id | UUID | FK → businesses(id) |
| item_id | UUID | FK → catalog_items(id) |
| old_qty | NUMERIC(12,3) | |
| new_qty | NUMERIC(12,3) | |
| adjustment_type | VARCHAR(32) | |
| reason | VARCHAR(512) | |
| updated_by | UUID | FK → users(id) |
| updated_at | TIMESTAMPTZ | |

### `stock_movements` (migration 037)
| Column | Type | Constraints |
|--------|------|-------------|
| id | UUID | PK |
| business_id | UUID | FK → businesses(id) |
| item_id | UUID | FK → catalog_items(id) |
| from_location | VARCHAR(128) | |
| to_location | VARCHAR(128) | |
| qty | NUMERIC(12,3) | |
| unit | VARCHAR(16) | |
| unit_mismatch_flag | BOOLEAN | DEFAULT false (migration 052) |
| moved_by | UUID | FK → users(id) |
| notes | TEXT | |
| created_at | TIMESTAMPTZ | |

### `stock_physical_counts` (migration 034, 068)
| Column | Type | Constraints |
|--------|------|-------------|
| id | UUID | PK |
| business_id | UUID | FK → businesses(id) |
| item_id | UUID | FK → catalog_items(id) |
| counted_qty | NUMERIC(12,3) | |
| system_qty | NUMERIC(12,3) | |
| unit | VARCHAR(16) | |
| variance | NUMERIC(12,3) | |
| counted_by | UUID | FK → users(id) |
| notes | TEXT | |
| idempotency_key | VARCHAR(64) | (migration 068) |
| is_verified | BOOLEAN | DEFAULT false |
| verified_by | UUID | FK → users(id) |
| verified_at | TIMESTAMPTZ | |
| created_at | TIMESTAMPTZ | |

### `stock_audits` (migration 026, 031)
| Column | Type | Constraints |
|--------|------|-------------|
| id | UUID | PK |
| business_id | UUID | FK → businesses(id) |
| title | VARCHAR(255) | |
| status | VARCHAR(32) | DEFAULT 'in_progress' |
| notes | TEXT | |
| created_by | UUID | FK → users(id) |
| completed_by | UUID | FK → users(id) |
| completed_at | TIMESTAMPTZ | |
| created_at | TIMESTAMPTZ | |

### `stock_audit_items`
| Column | Type | Constraints |
|--------|------|-------------|
| id | UUID | PK |
| stock_audit_id | UUID | FK → stock_audits(id) |
| catalog_item_id | UUID | FK → catalog_items(id) |
| expected_qty | NUMERIC(12,3) | |
| actual_qty | NUMERIC(12,3) | |
| variance | NUMERIC(12,3) | |
| notes | TEXT | |
| counted_at | TIMESTAMPTZ | |

### `stock_dispute_cases` (migration 039)
| Column | Type | Constraints |
|--------|------|-------------|
| id | UUID | PK |
| business_id | UUID | FK → businesses(id) |
| item_id | UUID | FK → catalog_items(id) |
| reported_by | UUID | FK → users(id) |
| expected_qty | NUMERIC(12,3) | |
| actual_qty | NUMERIC(12,3) | |
| reason | TEXT | |
| status | VARCHAR(32) | DEFAULT 'open' |
| resolved_by | UUID | FK → users(id) |
| resolved_at | TIMESTAMPTZ | |
| resolution_notes | TEXT | |
| created_at | TIMESTAMPTZ | |

### `reorder_list` (migration 025)
| Column | Type | Constraints |
|--------|------|-------------|
| id | UUID | PK |
| business_id | UUID | FK → businesses(id) |
| catalog_item_id | UUID | FK → catalog_items(id) |
| suggested_qty | NUMERIC(12,3) | |
| notes | TEXT | |
| created_at | TIMESTAMPTZ | |

---

## 6. Operations

### `daily_usage_logs` (migration 029)
| Column | Type | Constraints |
|--------|------|-------------|
| id | UUID | PK |
| business_id | UUID | FK → businesses(id) |
| item_id | UUID | FK → catalog_items(id) |
| qty_used | NUMERIC(12,3) | |
| unit | VARCHAR(16) | |
| usage_date | DATE | |
| logged_by | UUID | FK → users(id) |
| notes | TEXT | |
| created_at | TIMESTAMPTZ | |

### `staff_checklist_templates` (migration 029)
| Column | Type | Constraints |
|--------|------|-------------|
| id | UUID | PK |
| business_id | UUID | FK → businesses(id) |
| title | VARCHAR(255) | |
| description | TEXT | |
| frequency | VARCHAR(32) | daily\|weekly\|monthly |
| created_at | TIMESTAMPTZ | |

### `staff_checklist_completions`
| Column | Type | Constraints |
|--------|------|-------------|
| id | UUID | PK |
| checklist_id | UUID | FK → staff_checklist_templates(id) |
| business_id | UUID | FK → businesses(id) |
| user_id | UUID | FK → users(id) |
| completed_at | TIMESTAMPTZ | |

### `staff_purchase_logs` (migration 036)
| Column | Type | Constraints |
|--------|------|-------------|
| id | UUID | PK |
| business_id | UUID | FK → businesses(id) |
| user_id | UUID | FK → users(id) |
| item_name | VARCHAR(512) | |
| qty | NUMERIC(12,3) | |
| unit | VARCHAR(16) | |
| amount | NUMERIC(12,2) | |
| notes | TEXT | |
| purchase_date | DATE | |
| created_at | TIMESTAMPTZ | |

---

## 7. Notifications

### `notifications` / `app_notifications` (migration 023, 038)
| Column | Type | Constraints |
|--------|------|-------------|
| id | UUID | PK |
| business_id | UUID | FK → businesses(id) |
| user_id | UUID | FK → users(id) |
| kind | VARCHAR(64) | |
| title | VARCHAR(500) | |
| body | TEXT | |
| priority | VARCHAR(16) | critical\|high\|medium\|info (migration 038) |
| category | VARCHAR(32) | system\|stock\|purchase\|export (migration 038) |
| action_route | VARCHAR(255) | |
| dedupe_key | VARCHAR(128) | |
| payload | JSONB | |
| triggered_by_user_id | UUID | FK → users(id) |
| related_item_id | UUID | |
| related_purchase_id | UUID | |
| read_at | TIMESTAMPTZ | |
| created_at | TIMESTAMPTZ | |

---

## 8. Activity & Audit

### `staff_activity_log` (migration 022, 032, 059)
| Column | Type | Constraints |
|--------|------|-------------|
| id | UUID | PK |
| business_id | UUID | FK → businesses(id) |
| user_id | UUID | FK → users(id) |
| user_name | VARCHAR(255) | |
| action_type | VARCHAR(64) | NOT NULL — CHECK list (33 actions in v2) |
| item_id | UUID | |
| item_name | VARCHAR(512) | |
| details | JSONB | |
| created_at | TIMESTAMPTZ | |

Action types: SCAN, STOCK_UPDATE, ITEM_CREATE, ITEM_EDIT, CATEGORY_CREATE, SUPPLIER_CREATE, PURCHASE_CREATE, PURCHASE_EDIT, PURCHASE_DELETE, STOCK_AUDIT_START, STOCK_AUDIT_COMPLETE, PHYSICAL_COUNT, STOCK_MOVEMENT, STOCK_DISPUTE, DAMAGE_REPORT, USER_CREATE, USER_BLOCK, USER_DELETE, PASSWORD_RESET, etc.

### `admin_audit_logs`
| Column | Type | Constraints |
|--------|------|-------------|
| id | UUID | PK |
| admin_id | UUID | FK → users(id) |
| action | VARCHAR(64) | |
| target_type | VARCHAR(64) | |
| target_id | UUID | |
| details | JSONB | |
| created_at | TIMESTAMPTZ | |

### `api_usage_logs`
| Column | Type | Constraints |
|--------|------|-------------|
| id | UUID | PK |
| business_id | UUID | FK → businesses(id) |
| user_id | UUID | FK → users(id) |
| endpoint | VARCHAR(255) | |
| method | VARCHAR(8) | |
| status_code | INTEGER | |
| response_ms | INTEGER | |
| created_at | TIMESTAMPTZ | |

### `webhook_event_logs`
| Column | Type | Constraints |
|--------|------|-------------|
| id | UUID | PK |
| event_type | VARCHAR(64) | |
| payload | JSONB | |
| status | VARCHAR(32) | |
| created_at | TIMESTAMPTZ | |

### `user_sessions`
| Column | Type | Constraints |
|--------|------|-------------|
| id | UUID | PK |
| user_id | UUID | FK → users(id) |
| business_id | UUID | FK → businesses(id) |
| login_at | TIMESTAMPTZ | |
| is_active | BOOLEAN | DEFAULT true |

---

## 9. Reports

### `report_saved_views` (migration 046)
| Column | Type | Constraints |
|--------|------|-------------|
| id | UUID | PK |
| business_id | UUID | FK → businesses(id) |
| user_id | UUID | FK → users(id) |
| name | VARCHAR(255) | |
| report_type | VARCHAR(64) | |
| filters | JSONB | |
| created_at | TIMESTAMPTZ | |
| updated_at | TIMESTAMPTZ | |

---

## 10. Unit Intelligence (migration 019 / supabase_019)

### `master_units`
| Column | Type | Constraints |
|--------|------|-------------|
| code | VARCHAR(16) | PK (e.g. BAG, KG, BOX, TIN, PIECE) |
| label_plural | VARCHAR(32) | |
| category | VARCHAR(32) | weight\|count\|volume |
| base_unit | VARCHAR(16) | |
| conversion_to_base | NUMERIC(12,6) | |
| created_at | TIMESTAMPTZ | |

### `item_packaging_profiles`
| Column | Type | Constraints |
|--------|------|-------------|
| id | UUID | PK |
| catalog_item_id | UUID | FK → catalog_items(id) |
| profile_type | VARCHAR(32) | |
| display_unit | VARCHAR(16) | |
| stock_unit | VARCHAR(16) | |
| package_size | NUMERIC(12,4) | |
| package_measurement | VARCHAR(8) | |
| created_at | TIMESTAMPTZ | |

### `ocr_item_aliases`
| Column | Type | Constraints |
|--------|------|-------------|
| id | UUID | PK |
| business_id | UUID | FK → businesses(id) |
| catalog_item_id | UUID | FK → catalog_items(id) |
| alias_text | VARCHAR(512) | |
| source | VARCHAR(32) | |
| confidence | REAL | |
| created_at | TIMESTAMPTZ | |

### `smart_unit_rules` / `smart_package_rules`
| Column | Type | Constraints |
|--------|------|-------------|
| id | UUID | PK |
| keyword | VARCHAR(128) | |
| unit_code | VARCHAR(16) | FK → master_units(code) |
| package_type | VARCHAR(32) | |
| priority | INTEGER | |
| is_active | BOOLEAN | |

### `item_learning_history`
| Column | Type | Constraints |
|--------|------|-------------|
| id | UUID | PK |
| catalog_item_id | UUID | FK → catalog_items(id) |
| corrected_unit | VARCHAR(16) | |
| corrected_package_type | VARCHAR(32) | |
| user_id | UUID | FK → users(id) |
| created_at | TIMESTAMPTZ | |

### `unit_confidence_logs`
| Column | Type | Constraints |
|--------|------|-------------|
| id | UUID | PK |
| catalog_item_id | UUID | FK → catalog_items(id) |
| source | VARCHAR(32) | |
| unit_code | VARCHAR(16) | |
| confidence_score | REAL | |
| created_at | TIMESTAMPTZ | |

### `ai_item_profiles`
| Column | Type | Constraints |
|--------|------|-------------|
| id | UUID | PK |
| catalog_item_id | UUID | FK → catalog_items(id) |
| profile_data | JSONB | |
| generated_by | VARCHAR(64) | |
| created_at | TIMESTAMPTZ | |

---

## 11. Business Config

### `business_goals`
| Column | Type | Constraints |
|--------|------|-------------|
| id | UUID | PK |
| business_id | UUID | FK → businesses(id) |
| metric | VARCHAR(64) | |
| target_value | NUMERIC(14,2) | |
| period | VARCHAR(16) | monthly\|quarterly\|yearly |
| created_at | TIMESTAMPTZ | |

---

## 12. Archived (Legacy)

### `_archived_entries` / `_archived_entry_line_items`
Created by migration 065_archive_legacy_entries_tables. Mirrors legacy `entries`/`entry_line_items` schema. No active app code reads these.

---

## RLS Policies (migration 054)

Migration `054_enable_rls_business_policies.sql` enables Row-Level Security on all business-scoped tables. Policy: `USING (business_id = current_setting('app.current_business_id')::UUID)`.

Tables with RLS: `catalog_items`, `item_categories`, `category_types`, `suppliers`, `brokers`, `broker_supplier_m2m`, `trade_purchases`, `trade_purchase_lines`, `trade_purchase_drafts`, `stock_adjustment_log`, `stock_movements`, `stock_physical_counts`, `stock_audits`, `stock_audit_items`, `stock_dispute_cases`, `daily_usage_logs`, `staff_checklist_templates`, `staff_checklist_completions`, `staff_purchase_logs`, `notifications`, `report_saved_views`, `reorder_list`.

---

## Migration History (62 files, applied in numeric order)

| # | File | Key Changes |
|---|------|-------------|
| 019 | `_019_compact.sql` + `supabase_019*` | Smart unit intelligence: master_units, item_packaging_profiles, ocr_item_aliases, smart_unit_rules, ai columns on catalog_items |
| 020 | `supabase_020_ocr_learning.sql` | OCR learning tables |
| 021 | `021_stock_inventory.sql` | Stock columns on catalog_items, stock_adjustment_log |
| 022 | `022_user_management.sql` | user_sessions, staff_activity_log |
| 023 | `023_notifications.sql` | notifications table |
| 024 | `024_trade_line_tax_mode.sql` | tax_mode on trade_purchase_lines |
| 025 | `025_reorder_list.sql` | reorder_list table |
| 026 | `026_stock_audits.sql` | stock_audits, stock_audit_items |
| 027 | `027_user_system_rebuild.sql` | Soft delete, notes, permissions, catalog type_id |
| 028 | `028_user_mgmt_v2.sql` | is_blocked, admin role, expanded activity types |
| 029 | `029_stockease_operations.sql` | Perishable flag, daily_usage_logs, staff_checklist |
| 030 | `030_catalog_barcode.sql` | barcode column + backfill |
| 031 | `031_stock_audit_business.sql` | Business scope on audits |
| 032 | `032_staff_activity_action_types.sql` | Extended action_type CHECK |
| 033 | `033_catalog_public_qr.sql` | public_token for QR |
| 033b | `033b_trade_line_qty_in_stock_unit.sql` | qty_in_stock_unit |
| 034 | `034_stock_physical_counts.sql` | stock_physical_counts |
| 034b | `034b_master_fix_v3_prod_parity.sql` | Production parity |
| 035 | `035_opening_stock.sql` | Opening stock fields |
| 035b | `035b_schema_parity_confirm.sql` | Schema parity confirm |
| 036 | `036_staff_purchase_logs.sql` | staff_purchase_logs |
| 037 | `037_stock_movements.sql` | stock_movements + ledger columns |
| 038 | `038_notification_alert_v2.sql` | Notifications v2 (priority, category, routes) |
| 039 | `039_stock_dispute_cases.sql` | stock_dispute_cases |
| 040 | `040_purchase_delivery_tracking.sql` | delivery_status pipeline |
| 041 | `041_purchase_delivery_extras.sql` | Dispatch note, delivered qty |
| 042 | `042_catalog_stock_list_sort_index.sql` | Stock list sort index |
| 043 | `043_audit_perf_indexes.sql` | Audit/opening/FK indexes |
| 044 | `044_catalog_current_stock_non_negative.sql` | current_stock >= 0 CHECK |
| 045 | `045_purchase_delete_integrity.sql` | Delete integrity + indexes |
| 046 | `046_report_saved_views.sql` | report_saved_views |
| 047 | `047_purchase_line_received_qty.sql` | received_qty, damaged_qty, return_qty |
| 051 | `051_delivery_discrepancy_and_lifecycle.sql` | delivery_discrepancies, purchase_lifecycle_events |
| 052 | `052_stock_movement_unit_mismatch_flag.sql` | unit_mismatch_flag |
| 053 | `053_purchase_lifecycle_statuses.sql` | Status lifecycle constraint (20 statuses) |
| 054 | `054_enable_rls_business_policies.sql` | RLS for all business_id tables |
| 055 | `055_business_whatsapp_contact.sql` | accounts_whatsapp_number |
| 056 | `056_purchase_damage_reports.sql` | purchase_damage_reports |
| 057 | `057_purchase_damage_reports_v2.sql` | Damage report workflow columns |
| 058 | `058_barcode_lookup_perf.sql` | Barcode/item_code indexes |
| 059 | `059_staff_activity_action_types_v2.sql` | Extended action_type (33 actions) |
| 060 | `060_stock_list_performance_indexes.sql` | Stock list/low-stock/movement indexes |
| 061 | `061_catalog_unit_simplify.sql` + `supabase_061*` | Canonical 5-unit profiles data backfill |
| 062 | `062_trade_report_indexes.sql` | Trade report indexes |
| 063 | `063_pg_hot_path_indexes.sql` | Hot-path performance indexes |
| 064 | `064_critical_performance_indexes.sql` + `064_pg_report_line_indexes.sql` | Critical perf indexes |
| 065 | `065_api_storm_hotpath_indexes.sql` + `065_archive_legacy_entries_tables.sql` | Hot-path indexes + archive legacy entries |
| 066 | `066_drop_scan_and_whatsapp.sql` | Drop legacy tables |
| 067 | `067_user_token_version.sql` | token_version for JWT invalidation |
| 068 | `068_physical_count_idempotency_key.sql` | idempotency_key + partial unique index |

**Superseded/Archived:** `065_archive_legacy_entries_tables.sql` archives `entries`/`entry_line_items` into `_archived_entries`/`_archived_entry_line_items`. `066_drop_scan_and_whatsapp.sql` drops `purchase_scan_traces`, `catalog_aliases`, and WhatsApp columns.
