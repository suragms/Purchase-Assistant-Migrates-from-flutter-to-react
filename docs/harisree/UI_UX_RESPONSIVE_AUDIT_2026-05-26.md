# Harisree UI/UX Responsive Audit + Fix Report

Date: 2026-05-26  
Scope: Flutter Harisree app under `flutter_app/` only.

## Route Coverage

Audited the route map in `flutter_app/lib/core/router/app_router.dart` and grouped every routed surface into: auth/onboarding, owner shell, staff shell, home, stock, purchase, catalog, contacts, reports/analytics, barcode, operations, settings, notifications, and drilldown/detail pages.

## Fixed Issues

### 1. Fragmented Responsive Rules

- Exact page/component: shared Flutter layout primitives.
- Root cause: breakpoints, gutters, max widths, sheet heights, and tap targets were scattered across page files.
- Why it breaks UX: fixes drift per page; desktop and mobile behavior becomes inconsistent.
- Severity: High.
- Exact fix: added `HexaBreakpoints`, `HexaResponsive`, `HexaResponsiveCenter`, `HexaResponsiveSheetViewport`, and `HexaAccessibleFilterChip`.
- Updated code: `flutter_app/lib/core/design_system/hexa_responsive.dart`, exported from `flutter_app/lib/core/design_system/design_system.dart`.
- Better responsive approach: mobile-first breakpoints with explicit compact phone, phone, tablet, desktop, and ultra-wide classes.
- UI/UX improvement suggestion: migrate future routed pages to these primitives before adding local layout logic.

### 2. Stock Filters Below Tap Target Minimum

- Exact page/component: `StockPage` status filters.
- Root cause: 36dp horizontal chip lane plus `MaterialTapTargetSize.shrinkWrap`.
- Why it breaks UX: hard to tap on 320px devices and violates Harisree touch target rules.
- Severity: High.
- Exact fix: replaced horizontal chip lane with wrapping `HexaAccessibleFilterChip` controls.
- Updated code: `flutter_app/lib/features/stock/presentation/stock_page.dart`.
- Better responsive approach: use `Wrap` for filter groups; reserve horizontal scroll for dense read-only data only.
- UI/UX improvement suggestion: use the same filter chip primitive for category/status/unit filters.

### 3. Stock Rows Squeeze At 320px

- Exact page/component: `StockTableRow`.
- Root cause: fixed stock/status/desktop metric columns and sub-11px metadata styles.
- Why it breaks UX: item names become unreadable, status competes with stock value, and older users lose scanability.
- Severity: High.
- Exact fix: row now uses responsive gutters, compact column widths under narrow constraints, desktop metrics only when width allows, and 11px minimum metadata.
- Updated code: `flutter_app/lib/features/stock/presentation/widgets/stock_table_row.dart`.
- Better responsive approach: phone rows prioritize Item, Stock, Status; desktop adds metrics only with enough width.
- UI/UX improvement suggestion: next upgrade can add desktop split-pane details for selected stock rows.

### 4. Keyboard-Sensitive Stock Sheets Could Overflow

- Exact page/component: stock update, quick purchase, quick edit, item code, barcode, reorder, row actions, and preview sheets.
- Root cause: several sheets used `Column(mainAxisSize: min)` with independent `viewInsets` padding and no unified max-height scroll container.
- Why it breaks UX: landscape, large text, and keyboard-open states can hide CTAs or crop content.
- Severity: High.
- Exact fix: moved sheets to `HexaResponsiveSheetViewport` with animated keyboard inset, safe area, max height, max width, and scroll behavior.
- Updated code: `stock_compact_update_sheet.dart`, `stock_quick_purchase_sheet.dart`, `stock_quick_edit_sheet.dart`, `edit_item_code_sheet.dart`, `assign_barcode_sheet.dart`, `reorder_level_sheet.dart`, `stock_row_actions.dart`, `stock_row_preview_sheet.dart`.
- Better responsive approach: all keyboard/operation sheets should use the shared sheet viewport.
- UI/UX improvement suggestion: future complex sheets should use draggable sheets only when they have persistent tabs or long async sections.

### 5. Shell Navigation Had Tight Compact-Phone Geometry

- Exact page/component: owner and staff shell bottom navigation.
- Root cause: 5 nav tabs plus FAB in a constrained row without explicit minimum tile height.
- Why it breaks UX: compact phones can make tap zones feel cramped.
- Severity: Medium.
- Exact fix: added minimum 48dp tile constraints and reduced owner FAB slot from 56 to 48 while preserving the visual button.
- Updated code: `flutter_app/lib/features/shell/shell_screen.dart`, `flutter_app/lib/features/staff/presentation/staff_shell_screen.dart`.
- Better responsive approach: keep bottom nav tap zones >=48dp, and use rail only at desktop/tablet widths.
- UI/UX improvement suggestion: unify owner/staff shell nav into one reusable shell primitive in a future cleanup.

### 6. Owner Home Stretched On Desktop

- Exact page/component: `HomePage`.
- Root cause: long dashboard `ListView` used viewport width directly.
- Why it breaks UX: cards become visually loose on 1440/1920px displays.
- Severity: Medium.
- Exact fix: centered dashboard content in a max-width responsive container while keeping operational mobile gutters.
- Updated code: `flutter_app/lib/features/home/presentation/home_page.dart`.
- Better responsive approach: dashboards get max-width containers; dense tables may use split panes instead.
- UI/UX improvement suggestion: add a future two-column owner desktop dashboard for alerts + stock movement.

### 7. Reports Filter Chips Were Small And Horizontally Trapped

- Exact page/component: `FullReportsPage` item group/sort controls.
- Root cause: 36dp horizontal scroll row with shrink-wrapped `ChoiceChip`.
- Why it breaks UX: filters are hard to tap and easy to miss on mobile.
- Severity: Medium.
- Exact fix: converted controls to wrapping accessible filter chips.
- Updated code: `flutter_app/lib/features/reports/presentation/reports_page.dart`.
- Better responsive approach: wrap controls; reserve chart/table horizontal scroll for data content.
- UI/UX improvement suggestion: promote the most common report filters into a sticky compact toolbar.

### 8. Legacy Analytics Tables Used FittedBox Scaling

- Exact page/component: `AnalyticsPage` items and broker DataTables.
- Root cause: `FittedBox(fitWidth)` scaled full tables to fit the screen.
- Why it breaks UX: text becomes tiny at phone widths and odd at tablet widths.
- Severity: Medium.
- Exact fix: replaced scaling with horizontal table widths and made legacy tabs scrollable.
- Updated code: `flutter_app/lib/features/analytics/presentation/analytics_page.dart`.
- Better responsive approach: tables scroll horizontally or become cards; never shrink text below readable size.
- UI/UX improvement suggestion: keep `FullReportsPage` as the primary reports surface and eventually retire legacy analytics.

### 9. Purchase Review Table Was Too Dense On Mobile

- Exact page/component: `PurchaseSummarySections`.
- Root cause: seven-column purchase recap table on phone widths.
- Why it breaks UX: rates, totals, and item names truncate during the final confirmation step.
- Severity: High.
- Exact fix: phone widths now render per-line summary cards with wrapped detail pills; tablet/desktop keep the table.
- Updated code: `flutter_app/lib/features/purchase/presentation/wizard/purchase_summary_step.dart`.
- Better responsive approach: card-first for operational confirmation, table only when width permits.
- UI/UX improvement suggestion: add warning/status chips for unit conversion or missing rates directly in each line card.

### 10. Bulk Barcode Print Toolbar And Preview Width Were Rigid

- Exact page/component: bulk barcode print toolbar, list rows, desktop preview pane.
- Root cause: horizontal toolbar chips, 380px fixed desktop pane, and compact icon controls.
- Why it breaks UX: 320px phones and landscape screens can lose toolbar actions; desktop pane can feel rigid.
- Severity: High.
- Exact fix: toolbar chips wrap, action buttons stack below 360px, copies control uses larger hit targets, and preview width is responsive.
- Updated code: `bulk_barcode_print_toolbar.dart`, `bulk_barcode_print_page.dart`.
- Better responsive approach: action bars wrap by width and preserve 48dp controls.
- UI/UX improvement suggestion: add saved printer presets for thermal/A4 workflows.

### 11. Barcode Scanner Had Fixed Portrait Camera Assumptions

- Exact page/component: `BarcodeScanPage`.
- Root cause: scanner height was always 42% of screen height and overlay width was fixed at 260px.
- Why it breaks UX: landscape screens leave too little room for manual entry/results, and compact phones can crop overlay affordances.
- Severity: Medium.
- Exact fix: camera height is clamped by orientation and overlay width is constrained by available safe gutter width.
- Updated code: `flutter_app/lib/features/barcode/presentation/barcode_scan_page.dart`.
- Better responsive approach: scanner gets smaller in landscape; lower controls remain reachable.
- UI/UX improvement suggestion: make scan result actions a persistent bottom sheet with Count, Receive, and Cash Buy.

### 12. Item Detail Barcode And Actions Were Fixed

- Exact page/component: catalog item detail barcode card and quick actions.
- Root cause: barcode/QR row used fixed 260/80px media and action grid always had 3 columns.
- Why it breaks UX: compact phones crowd QR and barcode; desktop/tablet action density is inconsistent.
- Severity: Medium.
- Exact fix: barcode/QR stacks below compact width; quick action grid becomes 2 columns on compact phones.
- Updated code: `flutter_app/lib/features/catalog/presentation/catalog_item_detail_page.dart`.
- Better responsive approach: media should clamp to container width and action grids should adapt by constraints.
- UI/UX improvement suggestion: use a tablet/desktop item detail two-pane layout.

## Responsive QA Checklist

Mobile:
- Verify no horizontal overflow at 320, 375, 390, and 414px.
- Check all chips/buttons/icons have 48dp tap targets.
- Open keyboard on stock, purchase, catalog, barcode, and contact sheets.
- Confirm bottom nav/FAB does not cover CTA footers.
- Test portrait and landscape barcode scan.

Tablet:
- Verify tablet widths do not show stretched phone cards.
- Check filters wrap cleanly and tables scroll only where needed.
- Confirm modal/sheet max widths are comfortable.
- Validate item detail and reports remain readable.

Desktop:
- Check 1024, 1280, and 1440px for max-width content and useful rail behavior.
- Confirm data screens do not stretch text/cards across the full viewport.
- Check hover/focus/active states for toolbar and nav controls.

Ultra-wide:
- Check 1920px content max widths, dashboard balance, and preview panes.
- Ensure lists do not become low-density empty space.

Landscape:
- Check scanner, bottom sheets, purchase wizard, reports filters, and barcode toolbar.
- Verify keyboard does not hide Save/Confirm buttons.

## Design System Rules

- Spacing: operational pages use 12/16/20dp responsive gutters; form/purchase pages use 16/24/32dp gutters.
- Radius: inputs and buttons 12dp; cards 16-20dp; operational table rows may use square bordered cells where scanability matters.
- Shadows: use subtle card shadows only for elevated SaaS surfaces; operational tables prefer borders.
- Typography: never below 11px; primary data is semibold or bold; compact captions use `HexaDsType.label(11)`.
- Breakpoints: compact phone `<360`, phone `<600`, tablet `<900`, desktop `>=1100`, ultra-wide `>=1600`.
- Grid system: phone cards are 1-2 columns; tablet 2 columns; desktop 2-3 columns or split panes.
- Layout containers: dashboards max at about 1180px; forms max at about 720px; bottom sheets max at about 640px.
- Tables: no `FittedBox` table scaling; use cards on phone or horizontal scroll with readable text.
- Sheets: all keyboard-sensitive bottom sheets use a safe, scrollable, max-height-aware wrapper.

## Modern UI Upgrade Plan

- Dashboard: evolve owner home into a desktop two-column control center with alerts, stock movement, and recent activity grouped by priority.
- Stock: add desktop split pane with list left and item activity/actions right.
- Reports: keep mobile report summaries card-first; desktop can use pinned filters + chart/table split views.
- Barcode: make scanner result actions the central workflow for Count, Receive, Purchase Quantity, and Activity.
- Onboarding: add role-specific first-run checklist for Owner and Staff.
- Animation: use fast 120-180ms transitions for sheet content and filter changes; avoid heavy chart/table animations.
- Card system: define operational card, SaaS card, and dense table row variants to reduce visual drift.
- Empty states: every empty route gets a next action, not just a blank message.
- Data density: phone prioritizes the next action; desktop prioritizes comparison, auditability, and batch work.

## Validation

- `flutter analyze` passed with no issues.
- `flutter test test/responsive_layout_smoke_test.dart test/stock_row_actions_test.dart test/trade_date_range_parity_test.dart` passed.
- New responsive smoke coverage checks stock rows and bulk barcode toolbar at representative mobile, tablet, desktop, and ultra-wide widths.

