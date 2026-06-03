# 12 — MASTER TODO LIST

**Traceability:** IDs map to audit findings (`BL-*`, `DB-*`, `CB-*`, `PERF-*`, `EH-*`, `UX-*`, `RPT-*`, `NT-*`, `PR-*`)

---

## Backend

- [ ] **P0-001** Run Alembic upgrade to **058** on Render (`DB-001`, `DB-013`)
- [ ] **P0-003** Verify index 042 + 058 on prod (`DB-004`, `PERF-001`)
- [ ] **P0-005** Confirm `version_tolerance=1` + physical-count flush deployed (`EH-002`, `EH-004`)
- [ ] **P1-002** Optional lifecycle sync on dispatch (`BL-001`, `DB-009`)
- [ ] **P1-003** Standardize commit-stock 409 JSON (`EH-003`, `DB-011`)
- [ ] **P1-006** Add ORM for `delivery_discrepancies` or remove (`DB-003`)
- [ ] **P1-007** Structured `integrity_error` codes (`EH-001`)
- [ ] **P2-002** Remove Entry-only report queries (`CB-014`, `RPT-005`)

---

## Flutter

- [x] **P0-004** Fix staff receive snackbar (`BL-007`, `UX-009`)
- [ ] **P0-005** Verify `stock_version_retry` + refresh-before-save in prod build (`PERF-002`, `EH-002`)
- [ ] **P1-004** Unify period filter Home ↔ Reports (`UX-004`, `RPT-003`)
- [ ] **P1-005** Debounce/narrow `invalidateBusinessAggregates` (`PERF-003`, `CB-004`)
- [ ] **P3-001** Stock list pending delivery badge (`STK-RD-004`)
- [ ] **P3-003** Physical/system toggle copy (`UX-007`, `STK-RD-002`)
- [ ] **P2-001** Delete 5 deprecated orphan files after zero-ref (`CB-007`–`CB-011`)

---

## Database / Ops

- [ ] **P0-001** `alembic current` = 058 on staging + prod
- [ ] **P0-002** Vercel project URL typo fix (`CB-021`)
- [ ] **P0-006** Render cron → `internal_cron` (`NT-005`)
- [x] **P2-003** Update `MIGRATION_INDEX.md` head 058 (`DB-001`, `CB-024`)
- [ ] **PR-017** Apply `suggested_indexes_trade_reports.sql` if needed (`DB-005`)
- [ ] Run `scripts/verify-deploy.ps1` after each deploy (`PR smoke`)

---

## QA

- [ ] **P0-007** Trade reports = History same period (`RPT-006`, `PR-013`)
- [ ] **P0-010**–**P0-011** Delivery E2E smoke (`BL-003`, `PR-010`, `PR-011`)
- [ ] **PR-025** Device matrix — `docs/cleanup/verification_checklist.md`
- [ ] **PR-026** Add screenshots to `docs/audit/screenshots/` (`07_UIUX`)
- [ ] `flutter analyze` (from `flutter_app/`) — zero errors (`CB-020`)
- [ ] `flutter test` (from `flutter_app/`) — pass
- [ ] `pytest tests/test_stock_workflow_rebuild.py tests/test_trade_purchases.py tests/test_physical_count_diff_sign.py -q` (from `backend/`)

---

## CI/CD

- [ ] **PR-023** PR workflow: analyze + test + pytest (`CB-020`)
- [ ] **PR-024** Monitor `/health` and `/health/db-check`

---

## WhatsApp Save & Share (accounts number only)

- [x] **WA-001** `buildPurchaseOrderWhatsAppMessage` + direct `wa.me/{accounts}` (`purchase_accounts_share.dart`)
- [x] **WA-002** Save & Share success/fail snack + Retry Send (`purchase_entry_wizard_v2.dart`)
- [x] **WA-003** Activity log `PURCHASE_WHATSAPP_SENT` / `FAILED` (`staff_activity_logger.dart`)
- [x] **WA-004** Settings toggle auto share (`purchase_whatsapp_prefs.dart`, `accounts_whatsapp_settings_card.dart`)
- [x] **WA-005** PDF footer Generated + Created by (`purchase_invoice_pdf_layout.dart`)
- [x] **WA-006** Unit tests (`test/purchase_whatsapp_message_test.dart`)

## Completed (recent commits — verify on prod)

- [x] Web compile `File` blob options (`purchase_accounts_share_web.dart`) — `fc45add`
- [x] Vercel filesystem routes + boot check — `ad50193`
- [x] Stock stale retry + version tolerance — `b5eac6a`
- [x] Staff shell branch sync — `ad50193`

---

## Finding index (quick lookup)

| Prefix | Document |
|--------|----------|
| CB-* | [01_CODEBASE_AUDIT.md](01_CODEBASE_AUDIT.md) |
| DB-* | [02_DATABASE_AUDIT.md](02_DATABASE_AUDIT.md) |
| BL-* | [03_BUSINESS_LOGIC_AUDIT.md](03_BUSINESS_LOGIC_AUDIT.md) |
| STK-RD-* | [04_STOCK_MODULE_REDESIGN.md](04_STOCK_MODULE_REDESIGN.md) |
| PERF-* | [05_PERFORMANCE_AUDIT.md](05_PERFORMANCE_AUDIT.md) |
| RPT-* | [06_REPORTS_AUDIT.md](06_REPORTS_AUDIT.md) |
| UX-* | [07_UIUX_AUDIT.md](07_UIUX_AUDIT.md) |
| NT-* | [08_NOTIFICATION_SYSTEM_AUDIT.md](08_NOTIFICATION_SYSTEM_AUDIT.md) |
| EH-* | [09_ERROR_HANDLING_AUDIT.md](09_ERROR_HANDLING_AUDIT.md) |
| PR-* | [10_PRODUCTION_READINESS_CHECKLIST.md](10_PRODUCTION_READINESS_CHECKLIST.md) |
| P0/P1/P2/P3-* | [11_IMPLEMENTATION_ROADMAP.md](11_IMPLEMENTATION_ROADMAP.md) |
