# API Contract — Purchase Assistant Backend

Base URL: `/v1/businesses/{business_id}` (or `/v1/auth`, `/v1/me`, `/health/*`)

Auth scheme: Bearer JWT in `Authorization` header. All endpoints require `get_current_user` unless noted.

---

## 1. Health (`/health`, `/health/live`, `/health/ready`, `/health/db-check`)

| Method | Path | Auth | Request | Response | Status | Business Rules |
|--------|------|------|---------|----------|--------|---------------|
| GET | `/` | None | — | `{service, docs, openapi_json, health, health_ready, hint}` | 200 | Avoid bare 404 |
| HEAD | `/` | None | — | 200 | 200 | For uptime probes |
| GET | `/health/live` | None | — | `{alive: true}` | 200 | No DB — instant |
| GET | `/health` | None | — | `{status, app_env, ai_provider, ai_keys_set_in_env, ai_ready, ...}` | 200 | Probes AI config |
| GET | `/health/ready` | None | — | `{status, db, db_ms, schema, schema_ok, stock_sync_ready}` | 200/503 | `SELECT 1`, checks `alembic_version`, `received_qty`, `delivery_status`, `staff_activity_v2` |
| GET | `/health/db-check` | None | — | `{status, tables}` | 200 | Core table probes |

---

## 2. Auth (`/v1/auth`)

| Method | Path | Auth | Request | Response | Status | Business Rules |
|--------|------|------|---------|----------|--------|---------------|
| POST | `/v1/auth/register` | None | `RegisterRequest` (`email, username, password, name`) | `TokenPair` (`access_token, refresh_token, expires_in`) | 201 | Guarded by `allow_public_registration`. Dup check on email/username. Creates `Business` + `Membership(role=owner)`. Superadmin if email matches `superadmin_bootstrap_email`. |
| POST | `/v1/auth/login` | None | `LoginRequest` (`email, password, device_token?`) | `TokenPair` | 200 | Checks `deleted_at`, `is_blocked`, `is_active`. Updates `last_login_at`, `last_active_at`. Creates `UserSession`. Logs via `log_staff_login_if_applicable`. |
| POST | `/v1/auth/google` | None | `GoogleAuthRequest` (`id_token`) | `TokenPair` | 200 | Verifies Google id token. Links/creates user by `google_sub`. Creates workspace if new. |
| POST | `/v1/auth/refresh` | None | `RefreshRequest` (`refresh_token`) | `TokenPair` | 200 | Decodes refresh token, checks user exists, issues new pair. |
| POST | `/v1/auth/forgot-password` | None | `ForgotPasswordRequest` (`email`) | `{ok, message, dev_reset_token?}` | 200 | Creates `PasswordResetToken` (1h expiry). Dev mode returns raw token. |
| POST | `/v1/auth/reset-password` | None | `ResetPasswordRequest` (`token, new_password`) | `{ok, message}` | 200 | Validates hash, expiry, `used_at`. Hashes new password. |

**Services:** `auth_login.resolve_user_by_email`, `google_oauth.verify_google_id_token_async`, `jwt_tokens.*`, `passwords.*`, `staff_audit.log_staff_login_if_applicable`

---

## 3. Me (`/v1/me`)

| Method | Path | Auth | Request | Response | Status | Business Rules |
|--------|------|------|---------|----------|--------|---------------|
| GET | `/v1/me/profile` | User | — | `UserProfileOut` | 200 | Current user profile |
| PATCH | `/v1/me/profile` | User | `UserProfilePatch` (`name?`) | `UserProfileOut` | 200 | Update own name |
| POST | `/v1/me/bootstrap-workspace` | User | — | `BootstrapWorkspaceOut` | 200 | Idempotent: creates `Business` + seeds default catalog/suppliers |
| GET | `/v1/me/businesses` | User | — | `list[BusinessBrief]` | 200 | Lists memberships with role + computed permissions |
| PATCH | `/v1/me/businesses/{business_id}/branding` | Owner | `BusinessBrandingPatch` | `BusinessBrief` | 200 | Owner only. Updates name, title, logo URL, GST, address, phone, email. |
| POST | `/v1/me/businesses/{business_id}/branding/logo` | Owner | `file` (multipart) | `BusinessBrief` | 200 | JPEG/PNG/WebP ≤2MB. Saves to `static/branding/`. Sets `branding_logo_url`. |

**Services:** `default_workspace.bootstrap_user_workspace`, `permissions.membership_permissions`

---

## 4. Users (`/v1/businesses/{business_id}/users`)

| Method | Path | Auth | Request | Response | Status | Business Rules |
|--------|------|------|---------|----------|--------|---------------|
| POST | `` | owner/admin | `UserCreateIn` | `UserCreateOut` | 201 | Admin cannot create owners. Allocates username. Auto-generates readable password. Creates `Membership`. Logs `USER_CREATE`. |
| GET | `` | owner/admin/manager | Query: `include_inactive` | `list[UserListOut]` | 200 | Filters active/inactive. |
| GET | `/active-sessions` | owner/manager | — | `list[UserListOut]` | 200 | Users active within last 5 min. |
| POST | `/bulk` | owner/admin | `UserBulkIn` (`user_ids, action, role?`) | `UserBulkOut` | 200 | Actions: activate, deactivate, block, unblock, delete, set_role. Cannot self-deactivate/block/delete. Role hierarchy gating via `actor_can_manage_target`. Revokes tokens on block/delete. |
| GET | `/{user_id}` | owner/admin/manager | — | `UserProfileOut` | 200 | Profile with stats (7d purchases, stock edits, profile stats). |
| PATCH | `/{user_id}` | owner/admin | `UserPatchIn` | `UserListOut` | 200 | Update name/email/phone/role/active/blocked/notes. Role hierarchy gating. |
| DELETE | `/{user_id}` | owner/admin | — | 204 | Cannot delete self. Soft-delete (sets `deleted_at`, `is_active=false`). Revokes tokens. |
| POST | `/{user_id}/reset-password` | owner/admin | — | `ResetPasswordOut` | 200 | Generates new readable password. Logs `PASSWORD_RESET`. |
| GET | `/{user_id}/credentials` | owner/admin | — | `{username, login_email, phone}` | 200 | Non-sensitive credential info. |
| GET | `/{user_id}/created-items` | owner/admin/manager | `limit` | `list[CreatedItemOut]` | 200 | Catalog items created by user (non-deleted). |
| GET | `/{user_id}/stock-adjustments` | owner/manager | `limit` | `list[StockAdjustmentOut]` | 200 | Stock audits by user. |
| GET | `/{user_id}/purchases` | owner/admin/manager | `limit` | `list[UserPurchaseBrief]` | 200 | Trade purchases by user. |
| GET | `/{user_id}/ledger` | owner/admin/manager | `limit, grouped?` | `list[LedgerEntryOut]` or `LedgerGroupedOut` | 200 | Combined activity + stock log, optionally grouped (today/yesterday/this_week). |
| GET | `/{user_id}/permissions` | owner/admin | — | `PermissionsOut` | 200 | Current role + permission map. |
| PATCH | `/{user_id}/permissions` | owner/admin | `PermissionsPatchIn` | `PermissionsOut` | 200 | Granular permission override. Merges with role defaults. |

### Activity Log (`/v1/businesses/{business_id}/activity-log`)

| Method | Path | Auth | Request | Response | Status | Business Rules |
|--------|------|------|---------|----------|--------|---------------|
| POST | `` | Membership | `ActivityLogIn` | `ActivityLogOut` | 201 | Logs arbitrary staff action. Updates `last_active_at`. |
| GET | `` | Membership | `user_id?, period/days?, page, per_page` | `list[ActivityLogOut]` | 200 | Filter by user, time range. Paginated. |

**Services:** `passwords.hash_password`, `permissions.*`, `readable_password.generate_readable_password`, `staff_audit.*`, `user_username.allocate_username`, `staff_view.*`

---

## 5. Catalog (`/v1/businesses/{business_id}`)

### Categories

| Method | Path | Auth | Request | Response | Status | Business Rules |
|--------|------|------|---------|----------|--------|---------------|
| GET | `/item-categories` | Membership | — | `list[ItemCategoryOut]` | 200 | Sorted case-insensitive. |
| POST | `/item-categories` | Membership | `ItemCategoryCreate` | `ItemCategoryOut` | 201 | Dup check on normalized name. Auto-creates "General" `CategoryType`. |
| GET | `/item-categories/{category_id}` | Membership | — | `ItemCategoryOut` | 200 | 404 if not in business. |
| PATCH | `/item-categories/{category_id}` | Membership | `ItemCategoryUpdate` | `ItemCategoryOut` | 200 | Dup check on name change. |
| DELETE | `/item-categories/{category_id}` | Owner | — | 204 | Guarded: cannot delete if items exist. |
| GET | `/item-categories/{category_id}/trade-summary` | Membership | — | `CategoryTradeSummaryOut` | 200 | Aggregates from confirmed trade lines only. Per-item: line total, qty bags, weight kg. Category totals. |
| GET | `/item-categories/{category_id}/insights` | Membership | `from, to` | `CategoryInsightsOut` | 200 | Item count, linked line count, total profit, top/worst items. |

### Category Types (Subcategories)

| Method | Path | Auth | Request | Response | Status | Business Rules |
|--------|------|------|---------|----------|--------|---------------|
| GET | `/item-categories/{category_id}/category-types` | Membership | — | `list[CategoryTypeOut]` | 200 | Sorted case-insensitive. |
| POST | `/item-categories/{category_id}/category-types` | Membership | `CategoryTypeCreate` | `CategoryTypeOut` | 201 | Dup check within category. |
| PATCH | `/item-categories/{category_id}/category-types/{type_id}` | Membership | `CategoryTypeUpdate` | `CategoryTypeOut` | 200 | Must belong to category + business. Dup check. |
| DELETE | `/item-categories/{category_id}/category-types/{type_id}` | Owner | — | 204 | Guarded: cannot delete if items reference it. |
| GET | `/category-types-index` | Membership | — | `list[CategoryTypeIndexOut]` | 200 | Flat list with parent category name for quick-add/search. |

### Catalog Items

| Method | Path | Auth | Request | Response | Status | Business Rules |
|--------|------|------|---------|----------|--------|---------------|
| GET | `/catalog-items` | Membership | `category_id?, type_id?, page, per_page` | `list[CatalogItemOut]` | 200 | Paginated, cached (`catalog_items_list_cache_key`). Enriches with default suppliers/brokers, last purchase dates, delivery status. Role-based financial redaction for staff. |
| POST | `/catalog-items` | Membership | `CatalogItemCreate` | `CatalogItemOut` | 201 | Resolves type (auto-creates "General" type if omitted). Dup check. Auto-generates `item_code` (ITM-NNNN) + `barcode`. Seeds `SupplierItemDefault`. Runs unit resolution. Invalidates read caches. |
| POST | `/catalog-items/from-scan` | Membership | `CatalogItemFromScanIn` | `CatalogItemOut` | 201 | Minimal create after unknown barcode scan. Validates type in business. Dup checks barcode, item_code, name. Runs unit resolution. |
| POST | `/catalog-items/batch` | Membership | `CatalogBatchCreate` | `CatalogBatchOut` | 201 | Batch create (≤80 items). Skips duplicates/errors. Returns `created` + `skipped` counts. |
| GET | `/catalog-items/{item_id}` | Membership | — | `CatalogItemOut` | 200 | Full detail with suppliers, brokers, purchase dates. |
| PATCH | `/catalog-items/{item_id}/item-code` | Membership | `ItemCodePatchIn` | `CatalogItemOut` | 200 | Validates format (A-Z, 0-9, -, _). Uniqueness check. |
| PATCH | `/catalog-items/{item_id}/barcode` | `stock_edit` | `BarcodePatchIn` | `CatalogItemOut` | 200 | Uniqueness check. |
| POST | `/catalog-items/{item_id}/generate-code` | Membership | — | `CatalogItemOut` | 200 | Auto-generates ITM-NNNN. Errors if code already exists. |
| GET | `/catalog-items/{item_id}/supplier-purchase-defaults` | Membership | `supplier_id` | `SupplierPurchaseDefaultsOut` | 200 | Last price/discount/payment_days from `SupplierItemDefault`. |
| GET | `/catalog-items/{item_id}/trade-supplier-prices` | Membership | — | `CatalogItemTradeSupplierPricesOut` | 200 | Latest landed price per supplier from trade lines. Volume-weighted avg. Best supplier detection (≥2 deals). Last 5 prices. |
| GET | `/catalog-items/{item_id}/insights` | Membership | `from, to` | `CatalogItemInsightsOut` | 200 | Line count, profit, avg landing/selling, profit margin %. |
| GET | `/catalog-items/{item_id}/lines` | Membership | `from, to, limit, offset` | `list[CatalogItemLineRow]` | 200 | Trade purchase lines for item. Paginated. Financial redaction for staff. Unit resolution per line. |
| GET | `/catalog/fuzzy-check` | Membership | `name, supplier_id?, category_id?, type_id?` | `CatalogFuzzyCheckOut` | 200 | RapidFuzz token_sort_ratio vs same-category/type/supplier items. Returns hits with scores. |
| GET | `/catalog/duplicate-clusters` | Owner | `min_score` | `{pairs: [...]}` | 200 | Cross-business item similarity (token_sort_ratio). For owner duplicate review. |
| POST | `/catalog/items/bulk-archive` | Owner | `BulkItemIdsIn` | 204 | Sets `deleted_at`. Invalidates caches. |
| PATCH | `/catalog/items/bulk-reorder` | Owner | `BulkReorderIn` | `{updated}` | 200 | Sets `reorder_level` on multiple items. |

### Variants

| Method | Path | Auth | Request | Response | Status | Business Rules |
|--------|------|------|---------|----------|--------|---------------|
| GET | `/catalog-items/{item_id}/variants` | Membership | — | `list[CatalogVariantOut]` | 200 | List variants (name + default_kg_per_bag). |
| POST | `/catalog-items/{item_id}/variants` | Membership | `CatalogVariantCreate` | `CatalogVariantOut` | 201 | Dup check on name within item. |
| PATCH | `/catalog-items/{item_id}/variants/{variant_id}` | Membership | `CatalogVariantUpdate` | `CatalogVariantOut` | 200 | Update name/weight. Dup check. |
| DELETE | `/catalog-items/{item_id}/variants/{variant_id}` | Owner | — | 204 | Guarded: checks no linked trade lines or archived entry lines. |

**Services:** `trade_query.*`, `fuzzy_catalog.rank_ids_by_token_sort`, `staff_view.*`, `unit_resolution_service.*`, `app_cache.*`, `read_cache_generation.*`, `db_schema_compat.*`, `db_resilience.*`, `legacy_archive.*`

---

## 6. Contacts (`/v1/businesses/{business_id}`)

### Suppliers

| Method | Path | Auth | Request | Response | Status | Business Rules |
|--------|------|------|---------|----------|--------|---------------|
| GET | `/suppliers` | Membership | `compact?, limit?` | `list[SupplierOut]` or `list[SupplierOutCompact]` | 200 | Compact skips `address`/`notes` columns. Enriches with `broker_ids` via `BrokerSupplierLink`. |
| POST | `/suppliers` | Membership | `SupplierCreate` | `SupplierOut` | 201 | Dup check. Validates `freight_type` (included|separate). Merges `broker_id` + `broker_ids`. Validates broker existence. |
| GET | `/suppliers/{supplier_id}` | Membership | — | `SupplierOut` | 200 | Full detail with broker IDs and last purchase date. |
| PATCH | `/suppliers/{supplier_id}` | Membership | `SupplierUpdate` | `SupplierOut` | 200 | Partial update. Broker link management (delete + re-add). |
| DELETE | `/suppliers/{supplier_id}` | Owner | — | 204 | Guarded: cannot delete if non-cancelled purchases exist. |
| GET | `/suppliers/{supplier_id}/metrics` | Membership | `from, to` | `SupplierMetricsOut` | 200 | Deals, qty, avg landing, profit, margin from confirmed trades. |

### Brokers

| Method | Path | Auth | Request | Response | Status | Business Rules |
|--------|------|------|---------|----------|--------|---------------|
| GET | `/brokers` | Membership | — | `list[BrokerOut]` | 200 | Enriches with `supplier_ids` via `BrokerSupplierLink`. |
| POST | `/brokers` | Membership | `BrokerCreate` | `BrokerOut` | 201 | Dup check. Links suppliers. Sets `broker_id` on linked suppliers. |
| GET | `/brokers/{broker_id}` | Membership | — | `BrokerOut` | 200 | Full detail with supplier IDs and last purchase date. |
| PATCH | `/brokers/{broker_id}` | Membership | `BrokerUpdate` | `BrokerOut` | 200 | Partial update. Supplier link management. |
| DELETE | `/brokers/{broker_id}` | Owner | — | 204 | Guarded: cannot delete if linked to purchases or assigned to suppliers. |
| GET | `/brokers/{broker_id}/metrics` | Membership | `from, to` | `BrokerMetricsOut` | 200 | Deals, total commission, total profit. |
| GET | `/brokers/{broker_id}/linked-suppliers` | Membership | — | `list[LinkedSupplierOut]` | 200 | Suppliers appearing on confirmed-scope trade purchases with this broker. |

### Search

| Method | Path | Auth | Request | Response | Status | Business Rules |
|--------|------|------|---------|----------|--------|---------------|
| GET | `/contacts/search` | Membership | `q, limit, scope?` | `SearchOut` | 200 | Scoped search: suppliers, brokers, items, categories, catalog_types. Sorts by prefix match then alpha. |
| GET | `/contacts/category-items` | Membership | `category, from, to` | `list[CategoryItemRow]` | 200 | Per-item breakdown by category from confirmed trade lines. |

**Services:** `trade_query.*`, `db_resilience.execute_with_retry`

---

## 7. Trade Purchases (`/v1/businesses/{business_id}/trade-purchases`)

### Draft

| Method | Path | Auth | Request | Response | Status | Business Rules |
|--------|------|------|---------|----------|--------|---------------|
| GET | `/draft` | Membership | — | `TradeDraftOut` | 200/404 | One draft per user per business. |
| PUT | `/draft` | Membership | `TradeDraftUpsertRequest` | `TradeDraftOut` | 200 | Upsert by `step` + `payload`. |
| DELETE | `/draft` | Membership | — | 204 | Delete draft. |

### Preview & Validation

| Method | Path | Auth | Request | Response | Status | Business Rules |
|--------|------|------|---------|----------|--------|---------------|
| POST | `/preview-lines` | Membership | raw dict | `TradePurchasePreviewOut` | 200 | Non-mutating SSOT totals for wizard. |
| POST | `/validate` | Membership | raw dict | `TradePurchaseValidateOut` | 200 | Full validation without persisting. |
| POST | `/check-duplicate` | Membership | `TradeDuplicateCheckRequest` | `TradeDuplicateCheckResponse` | 200 | Detects duplicate by supplier + date + amount proximity. |

### CRUD

| Method | Path | Auth | Request | Response | Status | Business Rules |
|--------|------|------|---------|----------|--------|---------------|
| GET | `` | Membership | `limit, offset, status, q, supplier_id, broker_id, catalog_item_id, purchase_from, purchase_to, include_lines` | `list[TradePurchaseOut]` or `list[TradePurchaseListItemOut]` | 200 | Cached (`purchase_list_cache_key`). Wide filter set. Status normalization (handles legacy int codes). Role-based financial redaction. |
| POST | `` | `purchase_create` | `TradePurchaseCreateRequest` + `Idempotency-Key` header | `TradePurchaseOut` | 201 | Idempotency support. Validates stock levels. Returns 409 on duplicate. Publishes `purchase.changed` + `stock.changed` SSE events. |
| GET | `/{purchase_id}` | Membership | — | `TradePurchaseOut` | 200 | Full detail with lines. |
| PUT | `/{purchase_id}` | `purchase_edit` | `TradePurchaseUpdateRequest` | `TradePurchaseOut` | 200 | State conflict detection. Validates against lifecycle status. |
| DELETE | `/{purchase_id}` | owner/manager | — | 204 | Soft-delete. Requires `TradePurchaseStateConflictError` check. |
| GET | `/next-human-id` | Membership | — | `TradeNextHumanIdOut` | 200 | Next `PUR-YYYY-NNNN`. |
| GET | `/last-defaults` | Membership | `catalog_item_id, supplier_id?, broker_id?` | dict | 200 | Last purchase defaults for item+supplier combo. |

### Delivery Pipeline

| Method | Path | Auth | Request | Response | Status | Business Rules |
|--------|------|------|---------|----------|--------|---------------|
| GET | `/delivery-pipeline` | Membership | — | `TradePurchaseDeliveryPipelineOut` | 200 | Pipeline state (dispatched, arrived, stock_committed, etc.). |
| PATCH | `/{purchase_id}/delivery` | `stock_edit` | `TradePurchaseDeliveryPatch` | `TradePurchaseOut` | 200 | Update delivery fields. Negative stock check. |
| POST | `/{purchase_id}/dispatch` | owner/manager | `TradePurchaseDispatchIn` | `TradePurchaseOut` | 200 | Marks as dispatched. |
| POST | `/{purchase_id}/arrive` | `stock_edit` | `TradePurchaseArriveIn` | `TradePurchaseOut` | 200 | Marks as arrived. |
| POST | `/{purchase_id}/commit-stock` | owner/manager/admin + `stock_edit` | — | `TradePurchaseOut` | 200 | Stock commitment. Returns `STALE_STOCK_VERSION_CONFLICT` on version mismatch. Returns `UNIT_SETUP_REQUIRED` if items lack unit config. |
| POST | `/{purchase_id}/auto-commit` | owner/manager/admin + `stock_edit` | — | `TradePurchaseOut` | 400 | Auto-commit if conditions met. |
| POST | `/{purchase_id}/verify` | `stock_edit` | `TradePurchaseVerifyIn` | `TradePurchaseOut` | 200 | Staff delivery verification. Stale stock conflict. |

### Payment

| Method | Path | Auth | Request | Response | Status | Business Rules |
|--------|------|------|---------|----------|--------|---------------|
| PATCH | `/{purchase_id}/payment` | `purchase_edit` | `TradePurchasePaymentPatch` | `TradePurchaseOut` | 200 | Partial or full payment update. Negative stock check. |
| POST | `/{purchase_id}/mark-paid` | `purchase_edit` | `TradeMarkPaidRequest` | `TradePurchaseOut` | 200 | Convenience: sets paid_amount = total_amount. |
| POST | `/{purchase_id}/cancel` | `purchase_edit` | — | `TradePurchaseOut` | 200 | Cancel purchase. |

### Lifecycle & Damage

| Method | Path | Auth | Request | Response | Status | Business Rules |
|--------|------|------|---------|----------|--------|---------------|
| GET | `/{purchase_id}/lifecycle-events` | Membership | — | `list[PurchaseLifecycleEventOut]` | 200 | Event-sourced state transitions. |
| POST | `/{purchase_id}/lifecycle` | owner/manager | `PurchaseLifecycleTransitionIn` | `TradePurchaseOut` | 200 | Explicit lifecycle transition. |
| POST | `/{purchase_id}/damage-reports` | `stock_edit` | `PurchaseDamageReportIn` | `PurchaseDamageReportOut` | 201 | Report damage on purchase lines. |
| GET | `/{purchase_id}/damage-reports` | Membership | — | `list[PurchaseDamageReportOut]` | 200 | List damage reports for purchase. |

**Services:** `trade_purchase_service.*`, `trade_preview_service.*`, `purchase_damage_service.*`, `staff_view.*`, `realtime_events.*`, `stock_movement_service.*`, `app_cache.*`, `read_cache_generation.*`

---

## 8. Damage Reports (`/v1/businesses/{business_id}/damage-reports`)

| Method | Path | Auth | Request | Response | Status | Business Rules |
|--------|------|------|---------|----------|--------|---------------|
| GET | `/pending-count` | Membership | — | `PendingDamageReportsCountOut` | 200 | Count of damage reports with pending status. |
| PATCH | `/{report_id}` | owner/manager | `PurchaseDamageReportStatusPatch` | `PurchaseDamageReportOut` | 200 | Update damage report status + notes. |

**Services:** `purchase_damage_service.*`

---

## 9. Dashboard (`/v1/businesses/{business_id}/dashboard`)

| Method | Path | Auth | Request | Response | Status | Business Rules |
|--------|------|------|---------|----------|--------|---------------|
| GET | `/dashboard` | Membership | `month` (YYYY-MM) | `DashboardOut` | 200 | In-memory cache (22s TTL). Degreeaded mode fallback. Filters by confirmed trade purchases within month. Returns: total purchase, paid, pending, profit, top 20 items, top 12 categories (heuristic name splitting). |

**Services:** `trade_query.*`, `async_budget.run_read_budget_bounded`, `app_cache.*`, `read_cache_generation.*`

---

## 10. Reports (`/v1/businesses/{business_id}/reports`)

### Trade Reports

| Method | Path | Auth | Request | Response | Status | Business Rules |
|--------|------|------|---------|----------|--------|---------------|
| GET | `/reports/trade` | Membership | `from, to, group_by, supplier_id?, broker_id?, category_id?, type_id?, catalog_item_id?` | `TradeReportOut` | 200 | Aggregated trade report with line-item drill-down. Financial redaction for staff. |

### Report Views

| Method | Path | Auth | Request | Response | Status | Business Rules |
|--------|------|------|---------|----------|--------|---------------|
| GET | `/reports/saved-views` | Membership | — | `list[ReportSavedViewOut]` | 200 | |
| POST | `/reports/saved-views` | Membership | `ReportSavedViewIn` | `ReportSavedViewOut` | 201 | |
| PATCH | `/reports/saved-views/{view_id}` | Membership | `ReportSavedViewUpdate` | `ReportSavedViewOut` | 200 | |
| DELETE | `/reports/saved-views/{view_id}` | Membership | — | 204 | |

---

## 11. Stock Audits (`/v1/businesses/{business_id}/stock-audits`)

| Method | Path | Auth | Request | Response | Status | Business Rules |
|--------|------|------|---------|----------|--------|---------------|
| GET | `` | Membership | — | `list[StockAuditOut]` | 200 | |
| POST | `` | `stock_edit` | `StockAuditCreateIn` | `StockAuditOut` | 201 | |
| GET | `/{audit_id}` | Membership | — | `StockAuditOut` | 200 | Full detail with items. |
| PATCH | `/{audit_id}` | `stock_edit` | `StockAuditUpdateIn` | `StockAuditOut` | 200 | |
| POST | `/{audit_id}/items` | `stock_edit` | `StockAuditItemIn` | `StockAuditItemOut` | 201 | Add item count. |
| POST | `/{audit_id}/complete` | owner/manager | — | `StockAuditOut` | 200 | Finalize audit. |
| POST | `/{audit_id}/resolve-discrepancies` | owner/manager | — | `StockAuditOut` | 200 | Auto-resolve. |

**Services:** `stock_audit_service.*`

---

## 12. Stock (`/v1/businesses/{business_id}/stock`) — sub-router (5 sub-modules)

Auth: All endpoints require `Membership` unless noted. `stock_edit` permission required for mutating stock.

### 12a. Stock List (`GET /list`, `/shell-bundle`, `/delivery-indicator-counts`, `/alerts/summary`, etc.)

| Method | Path | Auth | Request | Response | Status | Business Rules |
|--------|------|------|---------|----------|--------|---------------|
| GET | `/list` | Membership | `page, per_page, q, category, subcategory, status, sort, include_period, period_start, period_end, include_today, purchased_in_period, missing_barcode, missing_item_code, reorder_only, unit` | `StockListOut` | 200 | Cached (ETag + in-memory). Enriches with trade meta, physical counts, delivery indicators. |
| GET | `/shell-bundle` | Membership | Same as `/list` + `audit_limit` | `StockShellBundleOut` | 200 | Bundled payload: list + status counts + delivery counts + recent audit. Cached. |
| GET | `/delivery-indicator-counts` | Membership | Same filter params | `StockDeliveryIndicatorCountsOut` | 200 | Global pending/delivered truck counts (not page-limited). |
| GET | `/list/compact` | Membership | `page, per_page, q, category, subcategory, status, sort` | `StockListCompactOut` | 200 | Slim mobile version (minimal fields). |
| GET | `/search` | Membership | `page, per_page, q, category, subcategory, status, sort` | `StockListOut` | 200 | Search stock list. |
| GET | `/low` | Membership | `page, per_page` | `StockListOut` | 200 | **Deprecated.** Low stock filter. |
| GET | `/critical` | Membership | `page, per_page` | `StockListOut` | 200 | **Deprecated.** Critical stock filter. |
| GET | `/alerts/summary` | Membership | — | `StockAlertsSummaryOut` | 200 | Stock-only alert counts (low, critical, missing barcode, missing usage, eviction). |
| GET | `/warehouse/alerts-summary` | Membership | — | `WarehouseAlertsSummaryOut` | 200 | Collapsed owner-home alert summary: pending deliveries, verifications, checklists. |
| GET | `/low-stock/summary` | Membership | `q, category, subcategory, period_start, period_end` | `LowStockOpsSummaryOut` | 200 | KPIs for low-stock operations header. |
| GET | `/low-stock/operations` | Membership | `page, per_page, q, filter, category, subcategory, supplier_id, sort, period_start, period_end` | `LowStockOpsOut` | 200 | Paginated low-stock priority-sorted list with enrichment. |

### 12b. Stock Detail & Item Ops (`GET /{item_id}`, `PATCH /{item_id}`, etc.)

| Method | Path | Auth | Request | Response | Status | Business Rules |
|--------|------|------|---------|----------|--------|---------------|
| GET | `/items/{item_id}/purchase-intelligence` | Membership | — | `{suggested_qty, avg_interval_days, default_supplier}` | 200 | Analyzes last 12 purchases for avg qty + interval. |
| GET | `/{item_id}/activity` | Membership | `limit, offset, kind?` | `StockItemActivityOut` | 200 | Combined movements, staff purchases, staff activity. Filterable by kind. |
| GET | `/{item_id}/intelligence` | Membership | `period_start, period_end` | `StockIntelligenceOut` | 200 | Stock tracking profile, recent purchases, adjustments, variance. Financial redaction for staff. |
| GET | `/item/{item_id}/summary` | Membership | — | `{current_stock, physical_stock_qty, stock_version, ...}` | 200 | Lightweight row for list patch reconciliation after write. |
| GET | `/{item_id}/bundle` | Membership | `period_start, period_end` | `{detail, activity, intelligence, catalog_snapshot}` | 200 | Single round-trip warm-up: detail + activity + intelligence + catalog. |
| GET | `/{item_id}` | Membership | `period_start, period_end` | `StockDetailOut` | 200 | Full item detail with recent purchases. Financial redaction for staff. |
| POST | `/{item_id}/opening-stock` | owner/super_admin | `OpeningStockIn` | `StockDetailOut` | 200 | Set opening stock. Requires reason on change. Uses stock movement with `opening_stock` kind. |
| POST | `/{item_id}/physical-count` | `stock_edit` | `PhysicalStockCountIn` | `PhysicalStockCountOut` | 201 | Observation-only count (no stock mutation). Idempotency support. Logs `PHYSICAL_STOCK_COUNT`. |
| POST | `/{item_id}/physical-update` | `stock_edit` | `StockPhysicalUpdateIn` | `StockPhysicalUpdateOut` | 200 | Mutates stock to counted qty. Stale version conflict → 409. Creates `StockPhysicalCount` entry. |
| POST | `/{item_id}/verify-count` | `stock_edit` | `StockVerifyCountIn` | `StockDetailOut` | 200 | Barcode scan count verify. Reason required on variance. |
| PATCH | `/{item_id}` | `stock_edit` | `StockPatchIn` | `StockDetailOut` | 200 | Stock adjust (verification/damage/correction/sale). Stale version → 409. Opening stock lock gate. |
| POST | `/{item_id}/undo-last` | `stock_edit` | — | `StockDetailOut` | 200 | Revert user's last adjustment within 15 min. |
| POST | `/{item_id}/notify-owner` | Membership | `alert` (reorder\|missing_barcode) | `{ok, notifications_created}` | 201 | Staff/manager alert — pings owners/managers. Deduped daily. |

### 12c. Stock Ops (Inventory, Reorder, Opening, Quick Purchase)

| Method | Path | Auth | Request | Response | Status | Business Rules |
|--------|------|------|---------|----------|--------|---------------|
| GET | `/opening/setup` | Membership | `page, per_page, q, status, stock_status, category, subcategory, missing_barcode, missing_item_code, supplier_id, unit, updated_today, updated_by` | `OpeningStockSetupOut` | 200 | Paginated opening stock setup with summary (pending/completed/total). |
| GET | `/inventory-summary` | Membership | — | `InventorySummaryOut` | 200 | On-hand stock valuation (landing cost × qty) + unit buckets. |
| GET | `/totals` | Membership | `period_start, period_end` | `StockTotalsOut` | 200 | On-hand totals by default; with period, purchased qty in range. |
| GET | `/reorder` | Membership | `status` (pending\|ordered\|done\|all) | `ReorderListOut` | 200 | Reorder list entries with item + supplier details. |
| PATCH | `/reorder/{entry_id}` | Membership | `ReorderListPatchIn` | `ReorderListEntryOut` | 200 | Update reorder entry status. |
| DELETE | `/reorder/{entry_id}` | Membership | — | 204 | Delete reorder entry. |
| GET | `/opening/missing` | Membership | `limit` | `OpeningStockMissingOut` | 200 | Items without opening stock set. |
| POST | `/{item_id}/quick-purchase` | `stock_edit` | `QuickPurchaseIn` | `QuickPurchaseOut` | 200 | Staff purchase entry + stock movement. Returns purchase log + movement + item. |
| POST | `/{item_id}/reorder` | Membership | — | `{ok, item_id, status}` | 201 | Add item to reorder list (upsert by pending status). |

### 12d. Stock Audit & Staff Purchases

| Method | Path | Auth | Request | Response | Status | Business Rules |
|--------|------|------|---------|----------|--------|---------------|
| GET | `/audit/feed` | Membership | `limit, on` | `list[StockAdjustmentOut]` | 200 | Owner-wide stock change feed (alias for recent). |
| GET | `/audit/recent` | Membership | `limit, on` | `list[StockAdjustmentOut]` | 200 | Recent adjustments with item enrichment + variance expected qty. |
| GET | `/variances/today` | Membership | — | `list[StockVarianceOut]` | 200 | Today's stock variance notifications. |
| GET | `/audit/{item_id}` | Membership | — | `list[StockAdjustmentOut]` | 200 | Adjustment history for one item. |
| GET | `/staff-purchases` | Membership | `item_id?, limit` | `list[StaffPurchaseLogOut]` | 200 | Staff purchase log entries. |
| POST | `/staff-purchases` | `stock_edit` | `StaffPurchaseLogIn` | `StaffPurchaseLogOut` | 201 | Create staff purchase + stock movement (quick_purchase kind). Idempotent. |

### 12e. Barcode

| Method | Path | Auth | Request | Response | Status | Business Rules |
|--------|------|------|---------|----------|--------|---------------|
| GET | `/barcode/lookup` | Membership | `code` | `BarcodeLookupOut` | 200 | Lookup by barcode or item_code. Cached (30s in-memory). |
| GET | `/barcode/{item_id}` | Membership | — | `BarcodeLabelOut` | 200 | Barcode label data for print. |
| POST | `/barcode/batch` | `barcode_print` | `BarcodeBatchIn` | `BarcodeBatchOut` | 200 | Bulk label data for batch print. |

**Services:** `stock_inventory.*`, `stock_helpers.*`, `stock_movement_service.*`, `stock_variance_notifications.*`, `stock_tracking_profile.*`, `unit_normalization.*`, `staff_audit.*`, `realtime_events.*`, `read_cache_generation.*`

---

## 13. Search (`/v1/businesses/{business_id}/search`)

| Method | Path | Auth | Request | Response | Status | Business Rules |
|--------|------|------|---------|----------|--------|---------------|
| GET | `/search` | Membership | `q, scope?, limit` | `UnifiedSearchOut` | 200 | Cross-entity search (catalog, suppliers, purchases). |

---

## 14. Operations (`/v1/businesses/{business_id}/operations`)

| Method | Path | Auth | Request | Response | Status | Business Rules |
|--------|------|------|---------|----------|--------|---------------|
| GET | `/daily-usage` | Membership | `date?` | `list[DailyUsageOut]` | 200 | Daily item usage logs. |
| POST | `/daily-usage` | Membership | `DailyUsageIn` | `DailyUsageOut` | 201 | Log usage. |
| GET | `/checklists` | Membership | — | `list[ChecklistTemplateOut]` | 200 | Staff checklist templates. |
| POST | `/checklists/completions` | Membership | `ChecklistCompletionIn` | `ChecklistCompletionOut` | 201 | |
| GET | `/checklists/completions` | Membership | `date?, user_id?` | `list[ChecklistCompletionOut]` | 200 | |

---

## 15. Notifications (`/v1/businesses/{business_id}/notifications`)

| Method | Path | Auth | Request | Response | Status | Business Rules |
|--------|------|------|---------|----------|--------|---------------|
| GET | `` | Membership | `page, per_page, kind?, category?, priority?, unread_only?, q?` | `list[NotificationOut]` | 200 | Role-based visibility filter. |
| GET | `/summary` | Membership | — | `NotificationSummaryOut` | 200 | Unread count by category + priority. |
| GET | `/unread-count` | Membership | — | `UnreadCountOut` | 200 | Total unread. |
| PATCH | `/{notification_id}` | Membership | `NotificationReadPatch` | `NotificationOut` | 200 | Mark read/unread. |
| POST | `/mark-all-read` | Membership | `kind?` | `NotificationBulkActionOut` | 200 | |
| DELETE | `/clear-all` | Membership | `kind?` | `NotificationBulkActionOut` | 200 | |
| POST | `/client-event` | Membership | `ClientNotificationEventIn` | `NotificationBulkActionOut` | 200 | Client-side failure events (export_failed, sync_failed, print_failed). |

**Services:** `notification_emitter.*`

---

## 16. Exports (`/v1/businesses/{business_id}/exports`)

| Method | Path | Auth | Request | Response | Status | Business Rules |
|--------|------|------|---------|----------|--------|---------------|
| POST | `/backup` | `export_access` | `BackupRequest` | ZIP bytes | 200 | Backup: purchases_summary.pdf, orders/*.pdf, ledgers/*.pdf, stock/*.xlsx, Summary.txt. |
| GET | `/stock-inventory.xlsx` | `export_access` | — | XLSX bytes | 200 | Current inventory snapshot. |
| GET | `/purchases-month.pdf` | `export_access` | — | PDF bytes | 200 | Current month purchase rollup. |
| GET | `/backup/export` | `export_access` | — | JSON bytes | 200 | JSON bundle: catalog, suppliers, 90d purchases, recent audits. |

**Services:** `export_files.*`

---

## 17. Media (`/v1/businesses/{business_id}/media`)

| Method | Path | Auth | Request | Response | Status | Business Rules |
|--------|------|------|---------|----------|--------|---------------|
| POST | `/ocr` | Membership | `OcrRequest` | `OcrResponse` | 200 | OCR or paste-text extraction. Extracts line items via `bill_line_extract`. Stub when OCR disabled. Always requires user confirmation. |

**Services:** `bill_line_extract.extract_purchase_lines_from_text`

---

## 18. Public Items (`/v1/public/items`)

| Method | Path | Auth | Request | Response | Status | Business Rules |
|--------|------|------|---------|----------|--------|---------------|
| GET | `/v1/public/items/{public_token}` | None | — | `PublicItemOut` | 200 | Rate-limited public view of catalog item. |

---

## 19. Real-time (`/v1/businesses/{business_id}/realtime`)

| Method | Path | Auth | Request | Response | Status | Business Rules |
|--------|------|------|---------|----------|--------|---------------|
| GET | `/realtime/events` | Membership | — | SSE stream | 200 | Server-sent events for live updates (purchase.changed, stock.changed, notification.changed). |

**Services:** `realtime_events.publish_business_event`

---

## Cross-Cutting Concerns

### Auth Guards (in `app.deps`)
| Dependency | Effect |
|-----------|--------|
| `get_current_user` | Validates Bearer JWT, checks `is_active`, `is_blocked`, `deleted_at`, `token_version` |
| `require_membership` | User must have membership in business |
| `require_owner_membership` | Membership role == "owner" |
| `require_role("owner", "admin", ...)` | Membership role in allowed set |
| `require_permission("stock_edit")` | Membership has specific permission key |

### Financial Redaction (in `app.services.staff_view`)
Staff role users have financial fields zeroed/nulled in catalog items, trade purchases, and reports.

### Caching Strategy
- `catalog_items_list_cache_key` + TTL for `/catalog-items` list
- `purchase_list_cache_key` + TTL for trade purchase lists
- `dashboard_month_cache` in-memory dict (22s TTL, LRU 128)
- All caches invalidated by `trade_read_cache_generation` bump on write

### Real-time Events (SSE)
- `purchase.changed` — emitted on create/update/payment/delivery/cancel
- `stock.changed` — emitted on stock-affecting operations
- `notification.changed` — emitted on notification mutations
