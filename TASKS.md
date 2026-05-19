# Purchase Assistant — Living task board

**Last updated:** 2026-05-19  
**App:** `hexa_purchase_assistant` (Flutter + FastAPI + Supabase)  
**Product docs:** `docs/harisree/` (`MASTER_REFERENCE.md`, `FEATURES_DEEP_PLAN.md`)

---

## Master plan status (May 2026)

| Section | Status |
|---------|--------|
| 0 Repo cleanup | Done — `TASKS.md` only at root (+ `README.md`); junk MD gitignored |
| 1 Critical bugs BUG-01–14 | Done |
| 2 UI/UX 2.1–2.7 | Done |
| 3 Features 3.1–3.4 | Done |
| 4 Page audit | Done (see snapshot below) |
| 5 Cursor rules | Done — `.cursor/rules/purchase-assistant-master.mdc` |
| 6 Smart defaults | Done |
| 7 Device testing | Manual — checklist below |

**Code plan:** closed. Remaining work is **device QA** (Section 7) and **deploy** (checklist below).

---

## Post-master backlog (optional)

| Item | Notes |
|------|--------|
| FCM push | Owner alert when staff saves purchase while app is killed |
| Per-category last supplier | Wire `PurchaseSmartDefaults.loadLastSupplierForCategory` when party step has category context |
| Full `pytest` | Run `python -m pytest` in `backend/` (can be slow); health: `tests/test_health.py` |

**Local verify:** `powershell -File scripts/verify-release.ps1`

---

## Current sprint — critical bugs

| ID | Priority | Status | Summary |
|----|----------|--------|---------|
| BUG-01 | P0 | Done | Stock/shell: `ref.listen` uses post-frame |
| BUG-02 | P0 | Done | Reorder list: `FriendlyLoadError` |
| BUG-03 | P0 | Done | GET 503 retry with backoff |
| BUG-04 | P1 | Done | Stock category chips `Wrap` |
| BUG-05 | P1 | Done | Item sheet catalog loading gate |
| BUG-06 | P1 | Done | Tax Excl/Incl/No GST + preview |
| BUG-07 | P1 | Done | Staff session guards + invalidate |
| BUG-08 | P2 | Done | Reports PDF headers/fields |
| BUG-09 | P2 | Done | Barcode PDF last purchase + bags |
| BUG-10 | P2 | Done | Barcode scan web manual entry |
| BUG-11 | P2 | Done | Suggestion `LayerLink` overlay |
| BUG-12 | P3 | Done | Single primary print CTA |
| BUG-13 | P3 | Done | Cloud sync banner clears on 200 |
| BUG-14 | P3 | Done | Local notifications wired |

---

## Section 3 — Features

| Item | Status | Notes |
|------|--------|-------|
| 3.1 Live data | Done | LIVE pulse; purchase history refresh banner |
| 3.2 Bulk barcode | Done | Multi-select, S/M/L, copies, preview, **2–3 labels per A4 row** |
| 3.3 Staff activity | Done | API log on login/logout/purchase |
| 3.4 Notifications | Done | Purchase, low stock, staff auth, staff purchase (owner bg) |

**Optional later:** FCM when owner app is killed.

---

## Section 6 — Smart defaults

| Item | Status |
|------|--------|
| Last supplier / rate / qty prefs | Done |
| Ranked item search (exact → category → supplier boost) | Done |

---

## Known blockers

| Blocker | Mitigation |
|---------|------------|
| Local API 503 on stock | `HEXA_USE_SQLITE=1` + `hexa_dev.db` bootstrap |
| Flutter web blank shell | Full restart (not hot reload only) |
| `mobile_scanner` on web | Manual barcode entry |

---

## Deployment checklist

- [ ] `pytest` green in `backend/` (or at least `tests/test_health.py`)
- [x] `flutter analyze` — 0 errors (May 2026 run: warnings/info only in purchase item sheet)
- [ ] Render: `/health/ready` → `db: ok`
- [ ] Supabase migrations (if hosted Postgres)
- [ ] Env: `DATABASE_URL`, JWT, OpenAI scan key
- [ ] Smoke: login → home → stock → purchase history → reports
- [ ] Section 7 device tests (below)

---

## Section 7 — Device testing (manual)

Run on **physical** iOS 16+ and Android API 29+ before release:

- [ ] Cold start — no crash
- [ ] All bottom-nav tabs + back gesture
- [ ] Stock list loads; LIVE banner; no chip overflow
- [ ] Purchase wizard: supplier default, item search, tax preview, save
- [ ] Purchase history pull-to-refresh
- [ ] Reports overview charts
- [ ] Barcode scan — camera permission (native); manual entry (web)
- [ ] Barcode print + bulk print preview (2/row on A4)
- [ ] PDF share / print purchase + reports
- [ ] Offline purchase → sync → notification
- [ ] Staff login → home data → activity log
- [ ] Owner: staff active chips; background staff-purchase alert (if enabled)
- [ ] Keyboard + suggestion overlay above fields
- [ ] Largest system font — no critical overflow

---

## Page audit snapshot

| Page | Status |
|------|--------|
| Home (owner) | Green |
| Stock | Green |
| Reorder list | Green |
| Purchase entry / history | Green |
| Reports | Green |
| Catalog / item detail | Green |
| Barcode print / bulk | Green |
| Barcode scan | Yellow (web = manual) |
| Staff home / activity | Green |
| Notifications / Settings | Green |

---

## Agent rules (short)

- One living doc: this file + `docs/harisree/`.
- No raw `DioException` in UI — `HexaErrorCard` / `FriendlyLoadError`.
- `ref.listen` + `setState` → `addPostFrameCallback`.
- Category chips → `Wrap`.
- Financial totals on backend only.
