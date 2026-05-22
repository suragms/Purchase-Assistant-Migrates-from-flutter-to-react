# 🏭 HARISREE PURCHASE ASSISTANT — MASTER REFERENCE
## Infrastructure · UX Design System · Costs · Deploy · Cursor Rules · All Pages
## Version: May 2026 · Production Readiness Score: 72/100

> **READ THIS FIRST EVERY SESSION.** Cursor must read this file before touching any code.  
> No guessing. No assumptions. Every decision references this document.

---

## 📊 PROJECT STATUS SNAPSHOT

| Item | Status |
|------|--------|
| Build started | April 8, 2026 |
| Today | May 20, 2026 |
| Days building | 42 days |
| Production score | 72 / 100 |
| Backend | Render.com — `my-purchases-api` ✅ (`/health`, `/health/ready`) |
| Frontend (Harisree Flutter) | Vercel — **https://purchase-assiastant.vercel.app** ✅ (note spelling: `assiastant`, not `assistant`) |
| Wrong domain | `purchase-assistant.vercel.app` is a **different** app — do not use for Harisree |
| Mobile app | Flutter — iOS 16+ / Android ✅ |
| Database | Supabase PostgreSQL (free tier) |
| Migrations | Alembic head `030_catalog_barcode` (029 StockEase ops + 030 barcode on Supabase) |
| Active blockers | 5 (see ALL_REMAINING_BLOCKERS.md) |
| Doc hub | `docs/harisree/` (this file) |

### Owner visibility (shipped 2026-05-19)

- Today's stock movement feed on home + full page `/stock/today-feed`
- Stock page 3-section scroll (Eviction / Low / All) + Wrap filters + today movement fields
- Daily usage log + staff checklist (`/operations/usage`, `/operations/checklist`)
- Purchase confirm returns `stock_updates`; save sheet + live stock preview in line entry
- Stock variance detection + home card + `GET /stock/variances/today`
- Daily stock report sheet (home quick action) + client health score badge (home + stock)

---

---

## 🚨 STEP 0 — RENDER + VERCEL SMOKE (before device QA)

**If the API was manually suspended**, resume it first. When healthy:

```
curl https://my-purchases-api.onrender.com/health
curl https://my-purchases-api.onrender.com/health/ready
# Expected: {"status":"ok"} and {"status":"ok","db":"ok",...}

powershell -File scripts/verify-deploy.ps1
# Expected: Render + Vercel smoke OK
```

**Vercel build:** `bash scripts/vercel-flutter-build.sh` (set `API_BASE_URL` + `GOOGLE_OAUTH_CLIENT_ID` in Vercel Production env).  
**CORS:** Production API allows `https://purchase-assiastant.vercel.app` and `https://purchase-assastant.vercel.app` (code + set `CORS_ORIGINS` on Render).

**Schema parity:** Alembic head `024_harisree_sql_parity` runs `backend/sql/021–026` + `supabase_019/020`. If pages 500 with “column does not exist”, run `python backend/scripts/schema_audit.py` with production `DATABASE_URL`, then apply missing SQL via Supabase SQL editor or `AUTO_MIGRATE=1` on Render deploy.

---

---

## 🏗️ INFRASTRUCTURE DEEP DIVE

### Current Stack

```
LAYER           SERVICE           PLAN          COST/MONTH
─────────────────────────────────────────────────────────
Mobile app      Flutter           N/A           $0
Web admin       Vercel            Free Hobby    $0
API backend     Render.com        Starter       $7
Database        Supabase          Free          $0
File storage    Supabase Storage  Free (1GB)    $0
Auth/Realtime   Supabase          Free          $0
SMS OTP         AuthKey           Pay-as-go     ~$1-2
AI/OCR          OpenAI            API pay-go    ~$2-5
WhatsApp        Cloud API         Free (Meta)   $0
─────────────────────────────────────────────────────────
TOTAL CURRENT                                   ~$10-14/mo
```

### Render Starter Plan — What You Get ($7/month)

```
CPU:     0.5 vCPU shared
RAM:     512 MB
Storage: Ephemeral (no persistent disk)
Network: 100 GB outbound/month
Uptime:  Always-on (no sleep on Starter+)
Deploy:  Auto-deploy from GitHub main branch
Region:  Oregon (US West) — latency ~180ms from Kerala

LIMITATIONS:
  - 512 MB RAM: FastAPI + SQLAlchemy uses ~200-300MB → you have ~200MB headroom
  - Shared CPU: PDF generation and bulk barcode print will be slow (2-5 seconds)
  - Ephemeral storage: never write files to disk on Render — use Supabase Storage
  - Cold start: first request after deploy takes 30-60s (not after that)

WHEN TO UPGRADE ($25/mo Standard):
  - When you add 3+ paying clients
  - When PDF generation takes > 5 seconds
  - When RAM usage exceeds 400MB (check Render metrics)
```

### Supabase Free Plan — Production Limits

```
DATABASE:
  Storage: 500 MB (you're likely using 20-50 MB now — safe for 1-2 years)
  Connections: 60 concurrent max
  Compute: Nano (shared) — 500ms query limit before timeout
  Backup: Daily backups (7-day retention on free)
  
REALTIME:
  Max connections: 200 simultaneous websockets
  Messages/second: 200 broadcast messages
  
STORAGE:
  Free: 1 GB
  
AUTH (you're using JWT, not Supabase Auth):
  N/A — you handle JWT yourself
  
EDGE FUNCTIONS: Not used — N/A

WHEN TO UPGRADE ($25/mo Pro):
  - When DB exceeds 400 MB
  - When you need > 60 DB connections (multi-client)
  - When you need daily backups older than 7 days

IMPORTANT: Supabase free pauses after 7 days of inactivity.
  FIX: Add a cron job that pings the DB every 3 days.
  Add to backend/app/main.py startup: schedule a daily health check query.
```

### Render Logs Not Showing — Why & Fix

```
PROBLEM: You see "Suspended by you" in Render — no logs when suspended.

ALSO: Render only shows last 100 lines of logs in the free log viewer.
      Older logs are lost on Starter plan.

FIXES:
  1. Resume service → logs appear immediately
  
  2. For better logs, use Render's log streaming:
     Settings → Log Streams → Add Papertrail (free tier: 100MB/month)
     OR use Better Stack (free: 1GB/month, 3-day retention)
  
  3. For errors specifically, set up Sentry:
     pip install sentry-sdk[fastapi]
     In backend/app/main.py:
       import sentry_sdk
       sentry_sdk.init(dsn="YOUR_SENTRY_DSN", traces_sample_rate=0.1)
     Sentry free: 5000 errors/month — enough for this app

MONITORING STACK (free, add now):
  Sentry.io       → error tracking (free 5k errors/mo)
  Better Stack    → log aggregation (free 1GB/mo)  
  UptimeRobot    → uptime monitoring ping every 5min (free)
  
  All 3 together cost $0 and give you production visibility.
```

### Latency Reality Check

```
Current path for Flutter app request:
  Kerala → Render Oregon → Supabase US East → back
  Round trip: ~350-500ms per API call

This is SLOW for a warehouse app where staff scans items rapidly.

MITIGATIONS (do these):
  1. API response caching: cache stockList for 30s (already have this)
  2. Preload: api_warmup.dart already warms critical endpoints on app start ✅
  3. Optimistic updates: update UI before API confirms (for stock updates)
  4. Background refresh: show stale data instantly, refresh in background

FUTURE (when revenue allows):
  Move Render to Singapore region ($7/mo same price) → ~120ms to Kerala
  Or use Fly.io Chennai region ($3/mo) → ~40ms to Kerala
```

---

---

## 🎨 UX DESIGN SYSTEM — COMPLETE SPECIFICATION

### Operational density (`HexaOp`) — warehouse home/stock/scanner/bulk print

Use `flutter_app/lib/core/design_system/hexa_operational_tokens.dart` on **operational** surfaces only (not purchase wizard — keep `HexaDsLayout.pageGutter` 24dp there).

| Token | Value | Use |
|-------|-------|-----|
| `pageGutter` | 16dp | Home, stock, bulk print, missing labels |
| `cardPadding` | 14dp | Cards, sheets |
| `sectionGap` | 16dp | Between home sections |
| `buttonHeight` | 44dp | Primary actions, bulk print sticky bar |
| `chipHeight` | 36dp | Filters, horizontal alert pills |
| `listRowMin` / `listRowMax` | 64–72dp | Stock rows, bulk print, missing labels |
| `collapsedHeader` | 52dp | Home accordions (default collapsed) |
| `bottomNavMax` | 56dp | Owner shell bottom bar (20dp nav icons) |
| `fabSize` | 56dp | Center scan FAB |

Owner home: warehouse control center. Header = avatar + short warehouse name + `WH-#### • OWNER`; live strip = `LIVE • Updated … • low stock • pending delivery`; quick grid = Scan / Stock / Purchase / Reports / Barcode / Users; alert pills use business language (`Missing barcode labels`, `Pending Delivery`, `Stock Mismatch`, `Reorder Needed`). Stock card = `Warehouse Stock Overview` with value, tracked items, Bags/KG/Boxes/Tins and Purchased / Current warehouse stock / Moved-sold comparison bar. Recent changes, Low stock, and Stock movement render directly (no empty collapsed cards). Analytics: bottom sheet preview on stock card tap; **Reports** icon opens `/reports?tab=subcategories` for full BI (ring + legend + 10 tabs). **Stock list:** single dense list (`StockOperationalRow` max ~78dp); sticky 32dp period/unit/status pills on page; status pills are Low/Critical/Missing Code/Out/Reorder (no Eviction); rows show item/code/category-supplier plus Purchased, Current, Moved, and status. **Item detail:** stock summary, purchase rows with invoice/detail navigation, barcode generate/copy/print actions, and ledger tabs (Purchases/Sales/Usage/Damage/Corrections/Transfers). Quick edit `showStockQuickEditSheet` supports +/-1, +/-5, +/-10 and ledger reasons including Sale and Transfer. Bulk print: sticky Preview/PDF/Print, compact missing-code/missing-barcode/low/reorder/category-supplier chips, desktop preview panel ≥1100px. Errors: `barcodeMessageForUser` / `friendlyApiError` — never bare "Something went wrong" on barcode/PDF/stock patch paths.

### Typography (warehouse-grade, old-person friendly)

```
SCALE (larger than typical apps — warehouse workers, older users, bright sunlight):

Page Title:       22px   Bold      HexaDsColors.textPrimary
Section Header:   13px   SemiBold  HexaDsColors.textMuted   ALL CAPS letter-spacing 1.2
Primary Data:     17px   Bold      HexaDsColors.textPrimary  (item names, amounts)
Secondary Data:   14px   Regular   HexaDsColors.textPrimary  (dates, codes)
Muted Label:      12px   Medium    HexaDsColors.textMuted    (field labels)
Small Caption:    11px   Regular   HexaDsColors.textMuted    (timestamps, subtitles)

NEVER use below 11px anywhere in the app.
NEVER use Regular weight for primary data — always SemiBold minimum.
Font family: system default (SF Pro on iOS, Roboto on Android) — do not import custom fonts.
```

### Color Scheme

```
PRIMARY PALETTE:
  Brand Primary:    HexaColors.brandPrimary    (teal-green ~#00897B)
  Brand Background: HexaColors.brandBackground (off-white ~#F7F9FA)
  Brand Dark:       HexaColors.brandDark       (dark teal ~#00695C)

STATUS COLORS (consistent everywhere):
  Healthy/Success:  #2E7D32  (dark green)
  Low Stock/Warn:   #E65100  (deep orange)
  Critical/Error:   #C62828  (dark red)
  Out of Stock:     #455A64  (blue-grey)
  Info/Neutral:     #1565C0  (blue)

TEXT COLORS:
  Primary:   #1A1A2E  (near black)
  Body:      #374151  (dark grey)
  Muted:     #6B7280  (grey)
  Disabled:  #9CA3AF  (light grey)

BACKGROUNDS:
  Page:      #F7F9FA  (off-white)
  Card:      #FFFFFF  (white)
  Subtle:    #F3F4F6  (light grey)
  TableAlt:  #FAFAFA  (zebra stripe)

NEVER use pure #000000 or #FFFFFF for text/backgrounds.
ALWAYS use the HexaColors tokens — never hardcode hex in widgets.
```

### Spacing & Sizing

```
TOUCH TARGETS:
  Minimum: 44×44pt (iOS HIG) / 48×48dp (Material)
  Buttons: minimum height 52px
  List rows: minimum height 56px (48px content + 8px padding)
  Icon buttons in AppBar: 44px tap area minimum

SPACING:
  Page margins:         16px horizontal (24px on tablet 600px+)
  Section gap:          20px between major sections
  Component gap:        12px between related items
  Tight gap:            8px within a component
  List separator:       1px (never more — dense warehouse design)
  Card padding:         16px all sides
  Bottom scroll padding: MediaQuery.viewPaddingOf(context).bottom + 80px

BORDER RADIUS:
  Cards:      12px
  Chips:      20px (pill)
  Buttons:    10px
  Input fields: 8px
  Badges:     4px

ELEVATION:
  Floating sheets:  elevation 8
  Cards:            elevation 1
  Pinned headers:   elevation 2 with bottom shadow
  No arbitrary shadows — use only these 3 values
```

### Component Library (reference always)

```
BUTTONS:
  Primary:   FilledButton.styleFrom(minimumSize: Size.fromHeight(52), backgroundColor: HexaColors.brandPrimary)
  Secondary: OutlinedButton.styleFrom(minimumSize: Size.fromHeight(48))
  Text:      TextButton — only for navigation links, never for primary actions
  Danger:    FilledButton with backgroundColor: Color(0xFFC62828)
  Loading:   replace icon with SizedBox(18,18, CircularProgressIndicator(strokeWidth:2, color: white))

INPUT FIELDS:
  All use InputDecoration with:
    border: OutlineInputBorder(borderRadius: 8px)
    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14)
    labelStyle: 13px
  Suggestion overlays: NEVER position absolute — use OverlayPortal (see SUGGESTION FIELDS below)

STATUS BADGES:
  Container(padding: H:10 V:4, decoration: BoxDecoration(color: statusColor.withOpacity(0.12), border: Border.all(color: statusColor.withOpacity(0.4)), borderRadius: 4px))
  Text: 11px bold, statusColor

CHIPS (filter):
  FilterChip(
    selected: bool,
    selectedColor: HexaColors.brandPrimary.withOpacity(0.15),
    side: BorderSide(color: selected ? HexaColors.brandPrimary : Colors.grey.shade300),
    labelStyle: 13px, bold if selected
  )

LIST ROWS:
  ListTile(dense: true, minVerticalPadding: 8, contentPadding: horizontal 16)
  OR custom Container(height: 56-64px, padding: horizontal 16)
  Separator: Divider(height: 1, indent: 16, endIndent: 0)
  Never Card-per-item for lists > 20 items — use rows with separators only
```

### Suggestion Fields — The Critical UX Fix

```
THE PROBLEM: Dropdown suggestions appear BELOW the field → keyboard pushes them off screen.

THE FIX PATTERN (apply to ALL typeahead/suggestion fields):

Step 1: Wrap every suggestion-enabled TextField in a CompositedTransformTarget:
  final _layerLink = LayerLink();
  CompositedTransformTarget(link: _layerLink, child: TextField(...))

Step 2: Show suggestions using OverlayEntry positioned with CompositedTransformFollower:
  OverlayEntry(builder: (ctx) => Positioned(
    width: fieldWidth,
    child: CompositedTransformFollower(
      link: _layerLink,
      showWhenUnlinked: false,
      offset: Offset(0, isInBottomHalf ? -listHeight - fieldHeight : fieldHeight + 4),
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: 220),
          child: SingleChildScrollView(child: suggestionsList),
        ),
      ),
    ),
  ))

Step 3: isInBottomHalf detection:
  final box = context.findRenderObject() as RenderBox;
  final pos = box.localToGlobal(Offset.zero);
  final screenHeight = MediaQuery.sizeOf(context).height;
  final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;
  final availableHeight = screenHeight - keyboardHeight;
  isInBottomHalf = (pos.dy + box.size.height) > availableHeight * 0.55;

Step 4: Dismiss on tap outside:
  GestureDetector(
    onTapDown: (_) => _hideOverlay(),
    behavior: HitTestBehavior.translucent,
    child: SizedBox.expand(),
  )

AFFECTED FILES (fix ALL of these):
  - typeahead_suggestions_card.dart
  - party_inline_suggest_field.dart  
  - inline_search_field.dart
  - catalog_add_item_page.dart (supplier/category fields)
  - purchase_party_step.dart (supplier/broker fields)
```

### Mobile Viewport Rules

```
ALL SCAFFOLD WIDGETS MUST HAVE:
  resizeToAvoidBottomInset: true  ← on every Scaffold

ALL SCROLLABLE FORMS MUST:
  Wrap in SingleChildScrollView
  Last item padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom + 80)

ALL BOTTOM BUTTONS MUST:
  Never be a child of Column at fixed bottom
  Use: Scaffold's bottomNavigationBar slot OR
       sticky footer pattern:
         Column(children: [
           Expanded(child: SingleChildScrollView(child: formContent)),
           SafeArea(child: Padding(padding: EdgeInsets.all(16), child: actionButton)),
         ])

DATE FIELDS (everywhere in the app):
  NEVER use TextField for date input
  ALWAYS use this pattern:
    InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: _date ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime.now().add(Duration(days: 365)),
        );
        if (picked != null) setState(() => _date = picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Purchase Date',
          suffixIcon: Icon(Icons.calendar_today_rounded, size: 18),
        ),
        child: Text(DateFormat('dd MMM yyyy').format(_date ?? DateTime.now())),
      ),
    )

NO HORIZONTAL SCROLL IN LISTS:
  Row children must be Flexible or Expanded — never fixed width that overflows
  Exception: filter chip rows use horizontal SingleChildScrollView (allowed)
  Exception: recent scans bar (allowed)
  Test everything on 375px width iPhone SE
```

---

---

## 🔴 CRITICAL BUGS & LOGIC ERRORS FOUND IN CODEBASE

### Calculation Engine Errors

```
FILE: flutter_app/lib/core/calc_engine.dart

VERIFIED CORRECT:
  ✅ Line total = qty × rate × (1 + gst%)  for exclusive mode
  ✅ SSOT — no duplicate calculation logic
  ✅ Backend compute_totals aligned with Flutter computeTradeTotals

VERIFIED (2026-05):
  ✅ TaxMode.inclusive in lineMoneyDecimal / lineNetTaxableDecimal
  ✅ TaxMode.none handled separately from exclusive

REMAINING (optional hardening):
  ❌ Guard rate <= 0 or qty <= 0 before percentage division (avoid edge NaN)
  ❌ Audit all call sites pass taxMode consistently with purchase line entry UI
```

### Data Leakage Risk — Business ID Isolation

```
RISK: Owner A can potentially see Owner B's data if business_id filter is missed.

AUDIT EVERY ENDPOINT:
  Every query MUST have WHERE business_id = :current_business_id
  
CHECK THIS PATTERN in every router file:
  ✅ SAFE:   session.primaryBusiness.id passed to every query
  ❌ UNSAFE: SELECT * FROM catalog WHERE id = :item_id  ← no business_id check!
  
FILES TO AUDIT:
  backend/app/routers/catalog.py     → every SELECT, UPDATE, DELETE
  backend/app/routers/contacts.py    → suppliers, brokers
  backend/app/routers/trade_purchase.py → purchases
  backend/app/routers/stock.py       → stock items
  
RULE: If an endpoint takes :item_id or :purchase_id as path param,
      it MUST also verify that item belongs to the requesting user's business.
      
EXAMPLE FIX:
  BAD:  WHERE id = :item_id
  GOOD: WHERE id = :item_id AND business_id = :business_id
```

### Duplicate API Requests

```
IDENTIFIED DUPLICATES (fix these):

1. stockLowCountProvider + stockCriticalCountProvider
   → FIXED: merged into stockAlertCountsProvider (home_owner_dashboard_providers.dart)

2. homeDashboardDataProvider fires on EVERY tab switch to Home
   → Add: autoDispose with keepAlive for 60 seconds
   → Use: ref.keepAlive() inside the provider

3. reports page: fetches data on every Category/Subcategory/Supplier/Items tab switch
   → Cache: only refetch when date filter changes, not when tab changes
   → Use: ref.watch(reportsPurchasesPayloadProvider) stays alive across tab switches ✅ (already fixed)

4. catalogItemDetail loads trade history AND stock audit separately (2 calls)
   → Could merge into single GET /api/catalog/:id?include=trade_history,stock_audit
   → LOW PRIORITY — not causing visible slowness

5. Shell FAB invalidates multiple providers on every open
   → Already debounced ✅

RULE: Before adding any new FutureProvider, ask:
  "Does this data already exist in another provider?"
  "Can I derive this from an existing provider?"
```

### Soft Delete Missing — Data Integrity Risk

```
PROBLEM: Some list endpoints may return deleted items if soft-delete filter is missing.
REFERENCE: GLOBAL_SOFT_DELETE_AUDIT.md (already in repo)

CHECK: Every list query must have: WHERE is_deleted = false (or is_active = true)
       For Catalog items: WHERE is_deleted = false AND business_id = :bid
       
FILES TO CHECK:
  catalog router — item listing ← most important
  contacts router — suppliers, brokers
  stock router — stock list ← critical (deleted items showing in stock)
  
AUTO-FIX PATTERN:
  In SQLAlchemy models, add a default filter:
    @classmethod
    def active(cls):
        return cls.is_deleted == False
  Use in all queries: .where(CatalogItem.active())
```

---

---

## 📱 ALL PAGES — COMPLETE MATRIX

### Every Page, Route, Status, Owner

```
ROUTE                          PAGE FILE                          ROLE    STATUS
──────────────────────────────────────────────────────────────────────────────
/splash                        splash_page.dart                   all     ✅ done
/get-started                   get_started_page.dart              anon    ✅ done
/login                         login_page.dart                    anon    ✅ done (username or phone + password; API `identifier` field)
/forgot-password               forgot_password_page.dart          anon    ✅ done

── OWNER / MANAGER SHELL ──────────────────────────────────────────────────────
/home                          home_page.dart                     owner   ✅ done (warehouse control center: direct recent/low/movement cards; stock overview purchased/current/moved; health strip; analytics sheet)
/stock                         stock_page.dart                    owner   ✅ done (flat warehouse list; sticky Today/Week/Month/Year + unit + status pills; 72dp row; filter sheet for category/supplier; quick edit sheet; mini FAB)
/staff/stock                   stock_page.dart (staff mode)       staff   ✅ done (same list; no Year period chip; intelligence hides owner analytics)
/reports                       reports_page.dart                  owner   ✅ BI shell: 10 tabs (Overview/Categories/Subcategories/Items/…), summary card, period comparison, `?tab=` deep link
/reports/item/:catalogItemId   reports_item_bi_page.dart          owner   ✅ stock intelligence + purchase history action
/reports/category-drill        reports_category_drill_page.dart   owner   ✅ category spend drill from ring
/reports/subcategory-drill     reports_subcategory_drill_page.dart owner  ✅ subcategory spend drill (`trade-types`)
/purchase                      purchase_home_page.dart            all     ✅ done
/search                        search_page.dart                   all     ✅ done

── STAFF SHELL ────────────────────────────────────────────────────────────────
/staff/home                    staff_dashboard_page.dart          staff   ✅ done (alias of staff home; staff blocked from /reports and /settings/users)
/staff/search                  (reuses search_page.dart)          staff   ✅ done
/staff/stock                   (reuses stock_page.dart)           staff   ✅ done

── PURCHASE FLOW ──────────────────────────────────────────────────────────────
/purchase/new                  purchase_entry_wizard_v2.dart      all     ✅ done (wizard)
/purchase/:id                  purchase_detail_page.dart          all     ✅ done
/purchase/:id/edit             (reuses wizard in edit mode)       owner   ✅ done

── CATALOG / ITEMS ────────────────────────────────────────────────────────────
/catalog                       contacts_page.dart (catalog tab)   all     ✅ done
/catalog/item/:itemId          catalog_item_detail_page.dart      all     ✅ done, NEEDS PRINT WIRE
/catalog/item/:id/purchase-history  catalog_item_purchase_history_page.dart  all  ✅ done
/catalog/item/:id/ledger       (trade ledger)                     owner   ✅ done
/catalog/quick-add             catalog_add_item_page.dart         all     ✅ done, NEEDS PREFILL FIX
/catalog/new-category          (category add wizard)              owner   ✅ done
/catalog/category/:id/...      (subcategory add)                  owner   ✅ done

── BARCODE ────────────────────────────────────────────────────────────────────
/barcode/scan                  barcode_scan_page.dart             all     ✅ warehouse scanner: counted stock sheet, audit session, history
/barcode/scan-history          barcode_scan_history_page.dart     all     ✅ recent scans + pending approvals
/barcode/audit-session         stock_audit_session_page.dart      all     ✅ draft session lines + complete
/barcode/audit-summary         stock_audit_summary_page.dart      all     ✅ post-audit totals
/barcode/print/:itemId         barcode_print_page.dart            all     ✅ done (symbology=barcode, text=item_code)
/barcode/bulk-print            bulk_barcode_print_page.dart       all     ✅ done (2/4-col A4 dense, debounced search)
/catalog/quick-add-from-scan   barcode_quick_create_page.dart     all     ✅ done (no ITM auto; barcode read-only)
/stock/missing-barcodes        stock_missing_labels_page.dart     all     ✅ done (tabs: missing barcode / item code)

**Barcode vs item code (two DB columns — migration `030_catalog_barcode.sql`):**

| Field | Column | Use |
|-------|--------|-----|
| Barcode | `catalog_items.barcode` | Scanner / package EAN; lookup first; encoded on label symbology |
| Item code | `catalog_items.item_code` | Internal shelf code (`A-Z0-9_-`); shown on label text; reports |

- **Lookup:** `GET /stock/barcode/lookup` — `barcode` match, then legacy `item_code`.
- **Scan create:** `POST /catalog-items/from-scan` — requires both codes; **no** `_next_item_code()`.
- **Full add:** `/catalog/quick-add` — supplier/broker/HSN; optional ITM auto when code empty.
- **Patch:** `PATCH …/barcode`, `PATCH …/item-code`.

── STOCK ──────────────────────────────────────────────────────────────────────
/stock/today-feed              stock_today_feed_page.dart         owner   ✅ done (2026-05-19)
/stock/:itemId/history         stock_history_page.dart            all     ✅ done
/stock/reorder                 reorder_list_page.dart             all     ✅ done (2026-05)
/staff/stock/update/:itemId    (UpdateStockSheet)                 staff   ✅ done (bottom sheet)

── CONTACTS ───────────────────────────────────────────────────────────────────
/contacts                      contacts_page.dart                 all     ✅ done
/contacts/supplier/:id         supplier_detail_page.dart          owner   ✅ done (811 lines)
/contacts/supplier/new         supplier_create_wizard_page.dart   owner   ✅ done
/contacts/broker/:id           broker_detail_page.dart            owner   ✅ done
/contacts/broker/new           broker_wizard_page.dart            owner   ✅ done
/contacts/category/:id         category_items_page.dart           owner   ✅ done
/contacts/item-wizard          item_wizard_page.dart              owner   ✅ done

── REPORTS ────────────────────────────────────────────────────────────────────
/reports                       reports_page.dart                  owner   ✅ mobile BI hub: ring + legend (`features/reports/widgets/bi/`), slow/dead tabs, movement summary API
/home/breakdown/:type/:id      home_breakdown_list_page.dart      owner   ✅ done

── NOTIFICATIONS ──────────────────────────────────────────────────────────────
/notifications                 notifications_page.dart            all     ✅ done (524 lines)

── SETTINGS ───────────────────────────────────────────────────────────────────
/settings                      settings_page.dart                 owner   ✅ done (1778 lines)
/settings/users                user_management_page.dart          owner   ✅ done
/settings/users/:id            user_profile_page.dart             owner   ✅ done (7 tabs: overview, activity, stock, purchases, items, ledger, permissions)
/settings/backup               backup_page.dart                   owner   ✅ done

── ADMIN ──────────────────────────────────────────────────────────────────────
/admin                         super_admin_page.dart              super   ✅ done (health + businesses overview)
/voice                         voice_page.dart                    owner   ✅ done (AI voice)

── HIDDEN / SPECIAL ───────────────────────────────────────────────────────────
/staff/activity                staff_activity_page.dart           staff   ✅ done
/contacts/trade-ledger/:id     trade_ledger_page.dart             owner   ✅ done
```

### Pages That Are TRULY MISSING (build these)

```
✅ /stock/reorder              Reorder list (shipped 2026-05)
✅ Super admin content        Health + businesses overview (shipped 2026-05)
✅ Barcode print / bulk print UI rebuild (shipped 2026-05)
✅ Stock page swipe + updated-by + stockAlertCounts merge (shipped 2026-05)
✅ Owner today feed + /stock/today-feed + 5-tab stock shell (shipped 2026-05-19)
❌ Notifications bell realtime  Still poll/invalidation only (no Supabase realtime)
❌ Staff task board           Deferred
```

---

---

## ⚙️ CURSOR AI RULES — PREVENT AI SLOP

### The AI Slop Problem

```
Cursor generates "plausible-looking" code that:
  - Uses provider names that don't exist yet
  - Imports packages not in pubspec.yaml
  - Creates duplicate logic already in calc_engine.dart
  - Ignores existing design tokens and uses hardcoded colors
  - Breaks existing navigation when adding new routes
  - Forgets to add mounted checks after async gaps
  - Creates new providers when existing ones can be extended

RESULT: Build errors, logic drift, inconsistency.
```

### Mandatory Rules for Every Cursor Prompt

```
ALWAYS START YOUR CURSOR PROMPT WITH THIS PREAMBLE:
─────────────────────────────────────────────────
You are working on the Harisree Purchase Assistant Flutter app (PurchaseAssiastant-main).

MANDATORY RULES — follow all of these:
1. READ the file before changing it (view tool first)
2. NEVER duplicate: calc_engine.dart handles all calculations — extend it, never copy from it
3. NEVER hardcode colors — use HexaColors.* and HexaDsColors.* tokens only  
4. NEVER hardcode strings — check if existing constants exist
5. BEFORE adding a new provider, search for existing providers that return the same data
6. ALWAYS add: if (!mounted) return; after every await in StatefulWidget methods
7. ALWAYS use resizeToAvoidBottomInset: true on every Scaffold
8. ALWAYS check imports — only add packages that exist in pubspec.yaml
9. NEVER rewrite working logic — extend it with new parameters
10. RUN flutter analyze after every change — zero errors before moving on
─────────────────────────────────────────────────
```

### Skills MD Files (Cursor reads these)

```
The repo already has MD files Cursor uses. Always reference the right one:

docs/harisree/MASTER_REFERENCE.md → read first (this file)
docs/harisree/FEATURES_DEEP_PLAN.md → feature deep specs
CURRENT_CONTEXT.md                → what was last worked on
PROGRESS_LOG.md                   → what changed when
ALL_REMAINING_BLOCKERS.md         → known blockers
CALCULATION_VALIDATION_SUITE.md   → calc engine tests
DB_CONSISTENCY_AUDIT.md           → database rules
FULL_PAGE_MATRIX.md               → all pages list
PERFORMANCE_AUDIT.md              → speed requirements
PRODUCTION_READINESS_SCORE.md     → quality score

WHEN STARTING A NEW CURSOR SESSION:
  Tell Cursor: "Read docs/harisree/MASTER_REFERENCE.md, CURRENT_CONTEXT.md, and PROGRESS_LOG.md first"
  This prevents Cursor from re-doing already-done work
```

### Progress Tracking Rules

```
AFTER EVERY COMPLETED TASK, ADD TO PROGRESS_LOG.md:
  | [today's date] | [what was done in 1-2 sentences] |

UPDATE CURRENT_CONTEXT.md:
  Last updated: [date]
  Focus: [current task]
  Key paths: [files being worked on]
  Next: [next task]

UPDATE PRODUCTION_READINESS_SCORE.md score after major features.

This prevents "I forgot what I did last session" syndrome.
```

---

---

## 🔔 NOTIFICATIONS NOT WORKING — ROOT CAUSE

```
SYMPTOM: Bell icon doesn't update. Low stock alerts don't appear.

ROOT CAUSES FOUND:
1. No backend scheduler running (Render Starter has no cron — needs APScheduler in FastAPI)
2. No Supabase Realtime subscription in Flutter for notifications table
3. bell badge in shell_screen.dart reads from provider that may not invalidate

FIX PLAN:

BACKEND (backend/app/main.py):
  Add APScheduler at startup:
    from apscheduler.schedulers.asyncio import AsyncIOScheduler
    scheduler = AsyncIOScheduler()
    
    @scheduler.scheduled_job('interval', minutes=30)
    async def check_low_stock():
        # For each business: find items below reorder level
        # Insert notification if not already inserted in last 6 hours
        pass
    
    @app.on_event("startup")
    async def startup():
        scheduler.start()
  
  Add to requirements.txt: apscheduler>=3.10.4

FLUTTER (shell_screen.dart):
  Add Supabase realtime subscription for notifications table.
  On insert: ref.invalidate(unreadNotificationCountProvider)
  
FLUTTER (notifications_page.dart):
  Pull to refresh: ref.invalidate(notificationsListProvider)
  Mark as read on tap: PATCH /api/notifications/:id/read → invalidate count provider

SUPABASE ROW LEVEL SECURITY:
  Ensure notifications table has RLS: business_id = auth.jwt()->>'business_id'
  Or pass business_id filter in API query (since you use custom JWT, not Supabase Auth)
```

---

---

## 💰 COST OF THIS PROJECT

### Development Cost (to date)

```
APRIL 8 → MAY 20 = 42 days building

If you hired a developer in Kerala:
  Junior Flutter: ₹20,000-30,000/month
  Senior Flutter: ₹50,000-80,000/month
  FastAPI dev:    ₹30,000-50,000/month
  
  Team of 2 for 42 days: ₹1,50,000-3,00,000 (6-12 lakh/year equiv)

Cursor Pro cost: $20/month × 2 months = $40 (~₹3,300)
AI API costs: ~$10-20 total for development = ₹1,600

YOU SAVED: ₹1,50,000+ by building with Cursor Pro AI
ACTUAL SPEND: ~₹3,300 (Cursor) + $14/mo infra = ₹4,500 total
```

### Project Value at Completion

```
WHAT THIS APP REPLACES FOR HARISREE AGENCY:
  Manual stock notebook:     ₹0 → your app saves 2+ hours/day staff time
  Tally stock module:        ₹10,000-20,000/year license
  Barcode label printer setup: ₹5,000-15,000 one-time
  
  ANNUAL VALUE TO CLIENT: ₹30,000-50,000 in saved time + avoided software

KERALA MARKET PRICING:
  SaaS per business/month: ₹999-2,999/month for this category
  One-time license:        ₹25,000-75,000 for small wholesale business
  Annual AMC:              ₹5,000-10,000/year

  10 clients at ₹1,499/mo = ₹14,990/month = ₹1.8L/year
  Infra cost at 10 clients: ~₹2,500/month (upgrade Render + Supabase)
  Net: ₹12,490/month profit from 10 clients
```

### Kerala Market Opportunity

```
TARGET SEGMENT: Wholesale / distribution businesses, Thrissur-Ernakulam region

MARKET SIZE:
  Thrissur district alone: 800+ wholesale/distribution businesses
  Similar to Harisree Agency: grain traders, spice wholesalers, oil distributors
  Typical problems: manual stock, Tally (expensive, complex), no barcode workflow
  
  TOTAL ADDRESSABLE (Thrissur + Ernakulam + Kozhikode): ~5,000 businesses
  
YOUR MOAT:
  Malayalam-aware: item names (Jeerakam, Unniyappam, etc.) handled correctly
  Offline-first: works in warehouses with poor WiFi
  Barcode-first: most competitors are desktop-only ERP
  Warm referral network: existing Gulf ERP clients from HexaBill

COMPETITIVE LANDSCAPE:
  Tally ERP: ₹18,000/year, complex, desktop-only — not mobile
  Vyapar: ₹4,000-8,000/year, GST focused, not warehouse workflow
  Zoho: ₹10,000-20,000/year, overkill for small wholesale
  
  YOUR POSITION: ₹1,499-2,499/mo, mobile-first, barcode, warehouse workflow
  
CHANNELS:
  1. Warm: Harisree is your reference client → referrals to similar businesses
  2. WhatsApp: demo video sent to Thrissur wholesale market groups
  3. Google Business: "warehouse management app Kerala" local SEO
```

### App Naming Analysis

```
CURRENT: "Purchase Assistant" → generic, doesn't communicate warehouse/stock

BETTER NAMES FOR KERALA MARKET:
  StockSeva     → "seva" = service in Malayalam/Hindi (memorable)
  VyaparStock   → vyapar = business (connects to Vyapar brand awareness)
  GodownApp     → godown = warehouse in Kerala business language (very local)
  StockMitra    → mitra = friend/partner (warm feeling)
  Katala        → "katala" = store/warehouse in informal Malayalam
  
RECOMMENDED: "GodownApp" or "StockMitra"
  - Immediately communicates: warehouse + mobile app
  - Easy to say in Malayalam conversation
  - .com domain likely available
  - "Harisree" as the client name is fine, app name is your product brand

FOR HARISREE SPECIFICALLY:
  Could white-label: "Harisree Stock Manager" for this client
  Generic brand: "StockMitra by HexaStack" for other clients
```

---

---

## 🚀 DEPLOYMENT — END TO END PLAN

### Backend Deploy (Render)

```
STEPS TO DEPLOY AFTER ANY CODE CHANGE:

1. Push to GitHub main branch:
   git add -A && git commit -m "feat: [what you changed]" && git push origin main

2. Render auto-deploys on push (GitHub integration already configured)
   Watch deploy: render.com → my-purchases-api → Events tab
   
3. Alembic migrations run automatically on startup (AUTO_MIGRATE=1 in .env)
   Check: render.com → my-purchases-api → Logs → look for "Alembic: Running migrations"
   
4. Verify: curl https://my-purchases-api.onrender.com/health
   Expected: {"status": "ok", "db": "connected"}

ENVIRONMENT VARIABLES (already set in Render):
  DATABASE_URL      → Supabase postgres connection string
  JWT_SECRET        → your JWT signing key
  APP_ENV           → production
  AUTO_MIGRATE      → 1
  CORS_ORIGINS      → Vercel URL + localhost

NEVER PUT IN CODE:
  Passwords, API keys, secrets — always Render environment variables
```

### Flutter App Deploy (iOS + Android)

```
iOS (TestFlight → App Store):
  1. Increment version in pubspec.yaml: version: 1.0.x+x
  2. flutter build ipa --release
  3. Open Xcode → Product → Archive
  4. Upload to App Store Connect
  5. TestFlight → add Sunil sir as tester → share install link
  
  BEFORE FIRST SUBMIT:
    - Bundle ID: com.hexastack.harisreepurchase (or similar)
    - Add NSCameraUsageDescription in Info.plist (for barcode scan)
    - App Store screenshots required (6.5" + 5.5" sizes)

Android (APK direct → Play Store later):
  1. flutter build apk --release --split-per-abi
  2. This creates: arm64-v8a, armeabi-v7a, x86_64 APKs
  3. Send arm64-v8a APK directly to Sunil sir via WhatsApp for now
  4. For Play Store: flutter build appbundle → upload .aab
  
  SIGN RELEASE BUILD:
    Create keystore: keytool -genkey -v -keystore harisree.keystore -alias harisree -keyalg RSA -keysize 2048 -validity 10000
    Add to android/key.properties (never commit this file — add to .gitignore)
```

### Super Admin Access

```
HOW TO ACCESS SUPER ADMIN:
  1. Login with an account that has role = 'super_admin' in the DB
  2. In settings page: long-press the version number text 3 times quickly
  3. /admin route opens

HOW TO GRANT SUPER_ADMIN ROLE:
  Direct DB: go to Supabase → SQL Editor → run:
    UPDATE users SET role = 'super_admin' WHERE email = 'your@email.com';
  
  OR: Via API (if you add the endpoint):
    PATCH /api/admin/users/:id/role  { role: 'super_admin' }
    This endpoint should only work from localhost or with a master key

YOUR SUPER_ADMIN ACCESS:
  You (Anandu) should have super_admin on production DB
  Sunil sir should have role = 'owner'
  Staff created by Sunil sir get role = 'staff' or 'manager'
```

### Supabase Direct DB Access for Prompts

```
SUPABASE SQL EDITOR — use for these tasks:

1. Check what data exists:
   SELECT COUNT(*), business_id FROM catalog_items GROUP BY business_id;

2. Add super_admin:
   UPDATE users SET role = 'super_admin' WHERE phone = '+91XXXXXXXXXX';

3. Check for data leakage (all items with business_id):
   SELECT id, name, business_id FROM catalog_items WHERE business_id IS NULL;

4. View stock audit:
   SELECT * FROM stock_audit ORDER BY updated_at DESC LIMIT 20;

5. Check notifications:
   SELECT * FROM notifications ORDER BY created_at DESC LIMIT 10;

6. Manual reorder list insert (for testing):
   INSERT INTO reorder_list (business_id, item_id, added_by_name, status)
   SELECT b.id, c.id, 'System', 'pending'
   FROM businesses b, catalog_items c
   WHERE c.current_stock < c.reorder_level
   LIMIT 5;

DIRECT SUPABASE CURSOR PROMPTS:
  "Go to Supabase SQL Editor → run this query: [paste SQL]"
  Cursor cannot execute SQL directly — you run these in Supabase dashboard.
```

---

---

## 📋 COMPLETE TO-DO LIST — PRIORITY ORDER

### 🔴 P0 — Do RIGHT NOW (service is broken)

```
[ ] 1. Resume Render service → https://render.com → my-purchases-api → Resume
[ ] 2. Verify: curl https://my-purchases-api.onrender.com/health returns ok
[ ] 3. Set up UptimeRobot to ping /health every 5min → email alert if down (free)
[ ] 4. Add Sentry to backend → pip install sentry-sdk[fastapi] → 5 lines in main.py
[x] 5. Add APScheduler for low-stock notifications (backend/app/main.py) — shipped
```

### 🔴 P1 — Critical UX Breaks (users can't complete tasks)

```
[ ] 6.  Fix suggestion overlay behind keyboard — ALL 4 files (Section in UX DESIGN above)
[ ] 7.  Fix date field behind keyboard — replace all date TextFields with InkWell+showDatePicker
[ ] 8.  Fix item create: stop asking supplier/broker every item (session memory)
[x] 9.  Wire barcode print button in item detail → /barcode/print/:id
[x] 10. Rebuild barcode_print_page UI with label preview + download button
```

### 🟠 P2 — Core Missing Features

```
[x] 11. Build /stock/reorder page (reorder_list backend model exists — build Flutter page)
[ ] 12. Notifications bell — wire Supabase realtime subscription for badge count
[ ] 13. Add PDF export button to supplier_detail_page.dart (supplier_statement_pdf exists)
[ ] 14. Add PDF export to reports_page.dart AppBar (reports_pdf exists)
[ ] 15. Tax mode toggle (Exclusive/Inclusive/None) in item_entry_minimal_form.dart
[x] 16. Bulk barcode print: add category filter chips + performance fix
[x] 17. Stock page: add swipe-to-update gesture + who-edited column (+ 5-tab shell 2026-05-19)
[x] 18. Super admin page: build content (health, session, debug actions)
```

### 🟡 P3 — Quality & Polish

```
[ ] 19. Fix data leakage: audit every endpoint for missing business_id filter
[ ] 20. Fix soft-delete: audit every list query for is_deleted = false filter
[x] 21. Merge duplicate API calls: stockLowCount + stockCritical → stockAlertCountsProvider
[ ] 22. Add item create duplicate detection (fuzzy check API + UI warning)
[ ] 23. Smart unit auto-detection in catalog_add_item_page.dart
[x] 24. Fix calculation engine: TaxMode.inclusive (verify edge guards only)
[ ] 25. Add Supabase inactivity prevention (daily ping query in backend)
[ ] 26. PROGRESS_LOG.md: add entry after every completed task
[ ] 27. CURRENT_CONTEXT.md: update focus after every session
```

### 🟢 P4 — Kerala Market Launch Prep

```
[ ] 28. Rename app display name to "StockMitra" or keep "Harisree" for this client
[ ] 29. App icon: replace placeholder with Harisree/warehouse icon
[ ] 30. Generate signed APK for Android → share with Sunil sir for testing
[ ] 31. TestFlight build for iOS → Sunil sir tests on real warehouse floor
[ ] 32. Upgrade Render to Singapore region ($7/mo, much lower latency)
[ ] 33. Add rate limiting middleware (already exists in middleware/rate_limit.py — check if active)
[ ] 34. Set up Better Stack for log aggregation (free 1GB/mo)
[ ] 35. Write user manual for Sunil sir: one-page WhatsApp-friendly guide
```

---

---

## 📁 MD FILES — WHAT EACH ONE IS FOR

```
FILE                              PURPOSE                                    UPDATE WHEN
─────────────────────────────────────────────────────────────────────────────────────────
docs/harisree/MASTER_REFERENCE.md All decisions, rules, costs, infra        Major changes (canonical)
docs/harisree/README.md           Doc hub index + read order                When adding Harisree docs
docs/harisree/FEATURES_DEEP_PLAN.md Owner-visibility / feature deep specs When planning features
CURRENT_CONTEXT.md                What session is focused on                Every session start
PROGRESS_LOG.md                   What was done when                        After every task
ALL_REMAINING_BLOCKERS.md         Known issues to fix                       When blocker found or resolved
HARISREE_MASTER_REFERENCE.md      Redirect stub → docs/harisree/            N/A
HARISREE_FEATURES_DEEP_PLAN.md    Redirect stub → docs/harisree/            N/A
CALCULATION_VALIDATION_SUITE.md   Test cases for calc engine                When adding new tax modes
DB_CONSISTENCY_AUDIT.md           Database integrity rules                  When adding new tables
FULL_PAGE_MATRIX.md               All pages and routes list                 When adding new pages
PERFORMANCE_AUDIT.md              Speed benchmarks                          After performance work
PRODUCTION_READINESS_SCORE.md     Quality score                             Monthly or after major work
PROGRESS_LOG.md                   Change log by date                        After every change
ENTERPRISE_DEPLOYMENT_CHECKLIST.md Pre-launch checklist                    Before any client launch
```

---

---

## 📊 MODULE COUNT

```
BACKEND MODULES (routers):
  auth, business, catalog, contacts, stock, trade_purchase,
  reports, notifications, admin, barcode, backup, voice/ai
  TOTAL: ~12 routers

FLUTTER FEATURE MODULES:
  admin, analytics, assistant, auth, barcode, broker, catalog,
  contacts, dashboard, get_started, home, item, notifications,
  purchase, reports, search, settings, shell, splash, staff, stock,
  supplier, voice
  TOTAL: 23 feature modules

DATABASE TABLES (via Alembic migrations 001-023):
  users, businesses, memberships, catalog_items, catalog_types,
  catalog_categories, catalog_subtypes, contacts (suppliers/brokers),
  trade_purchases, trade_purchase_lines, stock_audit, notifications,
  reorder_list, backup_log, api_usage_log, admin_audit_log,
  business_subscription, billing_payment, feature_flag, ocr_scan_traces,
  + indexes tables
  TOTAL: ~20+ tables, 23 migrations

PUBSPEC PACKAGES (Flutter):
  riverpod, go_router, dio, supabase_flutter, mobile_scanner,
  barcode, qr_flutter, flutter_svg, pdf, printing, path_provider,
  share_plus, image_picker, intl, shared_preferences, lottie,
  flutter_slidable, shimmer, apscheduler (backend)
  TOTAL: ~25 Flutter packages, ~15 Python packages
```

---

---

## 🧭 HOW TO USE THIS APP — QUICK GUIDE FOR SUNIL SIR

```
STAFF DAILY FLOW:
  1. Open app → Staff Home
  2. Tap [SCAN BARCODE] → camera opens → scan item
  3. See item: current stock, low stock warning
  4. Tap [Update Stock] → enter physical count → save
  5. If low: tap [Notify Owner]

OWNER DAILY FLOW:
  1. Open app → Owner Home → see today's purchases + low stock count
  2. Tap Stock tab → filter 'Low Stock' → see what needs ordering
  3. Tap Reports → see monthly spend by category
  4. Tap Settings > Users → create/manage staff logins
  5. Tap [+ Barcode Print] → print labels for new stock received

PURCHASE ENTRY FLOW:
  1. [+] FAB → New Purchase
  2. Select supplier → Select broker (optional)
  3. Scan or search each item → enter qty + rate
  4. Review totals → Save
  5. PDF auto-generated → share to WhatsApp if needed

REORDER FLOW:
  1. Staff scans low item → taps [Add to Reorder List]
  2. Owner sees badge on Reorder icon
  3. Owner orders from supplier → marks 'Ordered'
  4. When stock arrives → staff updates stock qty → marks 'Done'
```

---

*Last updated: May 20, 2026 · Doc hub: `docs/harisree/`*  
*HexaStack Solutions — Anandu, Thrissur, Kerala*  
*Harisree Agency Purchase + Stock + Barcode System*
