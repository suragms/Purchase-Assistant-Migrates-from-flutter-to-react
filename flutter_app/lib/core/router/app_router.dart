import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/session_notifier.dart';
import 'post_auth_route.dart'
    show authenticatedHomePath, sessionCanManageUsers, sessionIsStaff;
import '../models/trade_purchase_models.dart';
import 'page_transitions.dart';
import '../../features/analytics/presentation/full_reports_page.dart';
import '../../features/analytics/presentation/item_analytics_detail_page.dart';
import '../../features/catalog/presentation/catalog_add_category_page.dart';
import '../../features/catalog/presentation/catalog_add_item_page.dart';
import '../../features/catalog/presentation/catalog_add_subcategory_page.dart';
import '../../features/catalog/presentation/catalog_category_detail_page.dart';
import '../../features/catalog/presentation/catalog_item_detail_page.dart';
import '../../features/catalog/presentation/catalog_item_timeline_page.dart';
import '../../features/catalog/presentation/catalog_page.dart';
import '../../features/catalog/presentation/catalog_type_items_page.dart';
import '../../features/catalog/presentation/quick_add_catalog_item_page.dart';
import '../../features/catalog/presentation/batch_item_create_page.dart';
import '../../features/catalog/presentation/catalog_missing_codes_page.dart';
import '../../features/catalog/presentation/catalog_setup_reorder_levels_page.dart';
import '../../features/auth/presentation/forgot_password_page.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/auth/presentation/reset_password_page.dart';
import '../../features/contacts/presentation/broker_detail_page.dart';
import '../../features/contacts/presentation/broker_wizard_page.dart';
import '../../features/contacts/presentation/category_items_page.dart';
import '../../features/contacts/presentation/contacts_page.dart';
import '../../features/contacts/presentation/trade_ledger_page.dart';
import '../../features/contacts/presentation/supplier_create_simple.dart';
import '../../features/contacts/presentation/supplier_detail_page.dart';
import '../../features/supplier/presentation/supplier_ledger_page.dart';
import '../../features/item/presentation/item_history_page.dart';
import '../../features/broker/presentation/broker_history_page.dart';
import '../../features/home/presentation/home_breakdown_list_page.dart';
import '../../features/home/presentation/home_page.dart';
import '../providers/home_breakdown_tab_providers.dart'
    show homeBreakdownTabFromQuery, HomeBreakdownTab;
import '../../features/purchase/domain/purchase_draft.dart';
import '../../features/purchase/presentation/purchase_detail_page.dart';
import '../../features/purchase/presentation/purchase_home_page.dart';
import '../../features/purchase/presentation/purchase_entry_wizard_v2.dart';
import '../../features/purchase/presentation/purchase_scan_draft_wizard_page.dart';
import '../../features/purchase/presentation/scan_purchase_page.dart';
import '../../features/reports/presentation/reports_item_detail_page.dart';
import '../../features/reports/presentation/reports_item_bi_page.dart';
import '../../features/reports/presentation/reports_category_drill_page.dart';
import '../../features/reports/presentation/reports_subcategory_drill_page.dart';
import '../../features/notifications/presentation/notifications_page.dart';
import '../../features/settings/presentation/business_profile_page.dart';
import '../../features/settings/presentation/maintenance_history_page.dart';
import '../../features/settings/presentation/settings_page.dart';
import '../../features/settings/presentation/user_management_page.dart';
import '../../features/settings/presentation/user_profile_page.dart';
import '../../features/staff/presentation/staff_dashboard_page.dart';
import '../../features/settings/presentation/backup_page.dart';
import '../../features/search/presentation/search_page.dart';
import '../../features/barcode/presentation/barcode_print_page.dart';
import '../../features/barcode/presentation/bulk_barcode_print_page.dart';
import '../../features/barcode/presentation/barcode_scan_page.dart';
import '../../features/barcode/presentation/barcode_scan_history_page.dart';
import '../../features/barcode/presentation/stock_audit_session_page.dart';
import '../../features/barcode/presentation/stock_audit_summary_page.dart';
import '../../features/stock/presentation/stock_page.dart';
import '../../features/stock/presentation/reorder_list_page.dart';
import '../../features/stock/presentation/stock_history_page.dart';
import '../../features/stock/presentation/stock_item_intelligence_page.dart';
import '../../features/stock/presentation/stock_today_feed_page.dart';
import '../../features/stock/presentation/stock_movement_page.dart';
import '../../features/stock/presentation/reorder_suggestions_page.dart';
import '../../features/settings/presentation/ai_usage_page.dart';
import '../../features/staff/presentation/staff_shell_screen.dart';
import '../../features/staff/presentation/staff_activity_page.dart';
import '../../features/staff/presentation/staff_purchase_history_page.dart';
import '../../features/staff/presentation/staff_purchase_order_detail_page.dart';
import '../../features/shell/shell_screen.dart';
import '../../features/splash/presentation/splash_page.dart';
import '../../features/admin/presentation/super_admin_page.dart';
import '../../features/get_started/presentation/get_started_page.dart';
import '../../features/operations/presentation/daily_usage_page.dart';
import '../../features/operations/presentation/staff_checklist_page.dart';
import '../../features/catalog/presentation/barcode_quick_create_page.dart';
import '../../features/catalog/presentation/catalog_duplicates_page.dart';
import '../../features/stock/presentation/stock_missing_labels_page.dart';
import '../../features/stock/presentation/stock_operational_list_page.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

bool _isOwnerShellTab(String loc) {
  if (loc == '/home' || loc.startsWith('/home/')) return true;
  if (loc == '/stock') return true;
  if (loc == '/reports') return true;
  if (loc == '/purchase') return true;
  if (loc == '/search') return true;
  return false;
}

/// Staff may only open operational routes (shell + stock/barcode/catalog helpers).
bool _isStaffAllowedRoute(String loc) {
  if (loc.startsWith('/staff')) return true;
  if (loc == '/notifications') return true;
  if (loc.startsWith('/barcode/')) return true;
  if (loc == '/catalog/missing-codes' ||
      loc == '/stock/missing-barcodes' ||
      loc == '/catalog/quick-add' ||
      loc == '/catalog/quick-add-from-scan' ||
      loc.startsWith('/catalog/item/')) {
    return true;
  }
  if (loc.startsWith('/operations/')) return true;
  if (loc.startsWith('/stock/intelligence/') ||
      loc.startsWith('/stock/') && loc.endsWith('/history')) {
    return true;
  }
  if (loc.startsWith('/operations/')) return true;
  return false;
}

String _staffRedirectForBlockedRoute(String loc) {
  if (loc.startsWith('/purchase')) return '/staff/purchase-history';
  if (loc.startsWith('/stock')) return '/staff/stock';
  if (loc.startsWith('/search')) return '/staff/search';
  if (loc.startsWith('/home')) return '/staff/home';
  if (loc.startsWith('/reports') || loc.startsWith('/analytics')) {
    return '/staff/home';
  }
  if (loc.startsWith('/settings') ||
      loc == '/voice' ||
      loc.startsWith('/contacts') ||
      loc.startsWith('/supplier') ||
      loc.startsWith('/broker') ||
      loc == '/catalog' ||
      loc.startsWith('/catalog/') && !_isStaffAllowedRoute(loc) ||
      loc == '/admin') {
    return '/staff/home';
  }
  return '/staff/home';
}

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/splash',
    refreshListenable: authRefresh,
    errorBuilder: (context, state) {
      if (kDebugMode) {
        debugPrint(
          'GoRouter error: uri=${state.uri} matched=${state.matchedLocation} error=${state.error}',
        );
      }
      return GoRouterErrorScreen(
        uri: state.uri,
        routerError: state.error,
      );
    },
    redirect: (context, state) {
      final loc = state.matchedLocation;
      final public = loc == '/splash' ||
          loc == '/get-started' ||
          loc == '/login' ||
          loc == '/forgot-password' ||
          loc == '/reset-password';

      ProviderContainer container;
      try {
        container = ProviderScope.containerOf(context);
      } catch (_) {
        // Rare: router runs before ProviderScope is available. Never land on a protected shell route.
        if (!public) return '/splash';
        return null;
      }

      final session = container.read(sessionProvider);
      // No session → only public auth/onboarding routes. (JWT may still be restoring in main(); splash handles that.)
      if (session == null) {
        if (loc == '/signup') {
          return '/login?tab=signin&notice=owner_only';
        }
        if (public) return null;
        return '/login';
      }
      // Password reset from email should work even with a stale / other-tab session.
      final resetTok = state.uri.queryParameters['token']?.trim() ?? '';
      if (loc == '/reset-password' && resetTok.isNotEmpty) {
        return null;
      }
      // Allow forgot-password so users aren't bounced to /home if session state is wrong.
      if (loc == '/forgot-password') {
        return null;
      }
      if (loc == '/signup') {
        return '/login?tab=signin&notice=owner_only';
      }
      if (loc == '/assistant' || loc == '/ai') {
        return authenticatedHomePath(session);
      }
      if (loc == '/admin' && !session.isSuperAdmin) {
        return '/settings';
      }
      if (loc.startsWith('/settings/users') &&
          !sessionCanManageUsers(session)) {
        return '/settings';
      }
      if (sessionIsStaff(session)) {
        if (_isStaffAllowedRoute(loc)) return null;
        if (_isOwnerShellTab(loc)) {
          if (loc == '/stock') return '/staff/stock';
          if (loc == '/search') return '/staff/search';
          if (loc == '/home' || loc.startsWith('/home/')) return '/staff/home';
          return '/staff/home';
        }
        if (!_isStaffAllowedRoute(loc)) {
          return _staffRedirectForBlockedRoute(loc);
        }
      } else {
        if (loc.startsWith('/staff')) return '/home';
      }
      // Signed in → skip other auth / onboarding screens.
      if (public) return authenticatedHomePath(session);
      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        redirect: (context, state) => '/splash',
      ),
      GoRoute(
        path: '/splash',
        pageBuilder: (context, state) => iosPushPage(
          key: state.pageKey,
          child: const SplashPage(),
        ),
      ),
      GoRoute(
        path: '/get-started',
        pageBuilder: (context, state) => iosPushPage(
          key: state.pageKey,
          child: const GetStartedPage(),
        ),
      ),
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) => iosPushPage(
          key: state.pageKey,
          child: const LoginPage(),
        ),
      ),
      GoRoute(
        path: '/forgot-password',
        pageBuilder: (context, state) => iosPushPage(
          key: state.pageKey,
          child: const ForgotPasswordPage(),
        ),
      ),
      GoRoute(
        path: '/reset-password',
        pageBuilder: (context, state) => iosPushPage(
          key: state.pageKey,
          child: ResetPasswordPage(
            initialToken: state.uri.queryParameters['token'],
          ),
        ),
      ),
      // Aliases
      GoRoute(path: '/dashboard', redirect: (_, __) => '/home'),
      GoRoute(path: '/history', redirect: (_, __) => '/purchase'),
      GoRoute(
        path: '/contacts',
        name: 'contacts',
        pageBuilder: (context, state) => iosPushPage(
          key: state.pageKey,
          child: const ContactsPage(),
        ),
      ),
      GoRoute(
        path: '/catalog',
        pageBuilder: (context, state) => iosPushPage(
          key: state.pageKey,
          child: const CatalogPage(),
        ),
      ),
      GoRoute(
        path: '/barcode/scan',
        name: 'barcode_scan',
        pageBuilder: (context, state) => iosPushPage(
          key: state.pageKey,
          child: const BarcodeScanPage(),
        ),
      ),
      GoRoute(
        path: '/barcode/scan-history',
        name: 'barcode_scan_history',
        pageBuilder: (context, state) => iosPushPage(
          key: state.pageKey,
          child: const BarcodeScanHistoryPage(),
        ),
      ),
      GoRoute(
        path: '/barcode/audit-session',
        name: 'stock_audit_session',
        pageBuilder: (context, state) => iosPushPage(
          key: state.pageKey,
          child: const StockAuditSessionPage(),
        ),
      ),
      GoRoute(
        path: '/barcode/audit-summary',
        name: 'stock_audit_summary',
        pageBuilder: (context, state) => iosPushPage(
          key: state.pageKey,
          child: const StockAuditSummaryPage(),
        ),
      ),
      GoRoute(
        path: '/barcode/print/:itemId',
        name: 'barcode_print',
        pageBuilder: (context, state) {
          final itemId = state.pathParameters['itemId']!;
          return iosPushPage(
            key: state.pageKey,
            child: BarcodePrintPage(itemId: itemId),
          );
        },
      ),
      GoRoute(
        path: '/barcode/bulk-print',
        name: 'barcode_bulk_print',
        pageBuilder: (context, state) => iosPushPage(
          key: state.pageKey,
          child: const BulkBarcodePrintPage(),
        ),
      ),
      GoRoute(
        path: '/catalog/missing-codes',
        name: 'catalog_missing_codes',
        pageBuilder: (context, state) => iosPushPage(
          key: state.pageKey,
          child: const CatalogMissingCodesPage(),
        ),
      ),
      GoRoute(
        path: '/stock/missing-barcodes',
        pageBuilder: (context, state) => iosPushPage(
          key: state.pageKey,
          child: const StockMissingLabelsPage(),
        ),
      ),
      GoRoute(
        path: '/catalog/quick-add-from-scan',
        pageBuilder: (context, state) {
          final barcode =
              state.uri.queryParameters['barcode']?.trim() ?? '';
          return iosPushPage(
            key: state.pageKey,
            child: BarcodeQuickCreatePage(barcode: barcode),
          );
        },
      ),
      GoRoute(
        path: '/catalog/setup-reorder-levels',
        name: 'catalog_setup_reorder_levels',
        pageBuilder: (context, state) => iosPushPage(
          key: state.pageKey,
          child: const CatalogSetupReorderLevelsPage(),
        ),
      ),
      GoRoute(
        path: '/catalog/quick-add',
        name: 'catalog_quick_add',
        pageBuilder: (context, state) => iosPushPage(
          key: state.pageKey,
          child: const QuickAddCatalogItemPage(),
        ),
      ),
      GoRoute(
        path: '/catalog/new-category',
        pageBuilder: (context, state) => iosPushPage(
          key: state.pageKey,
          child: const CatalogAddCategoryPage(),
        ),
      ),
      GoRoute(
        path: '/catalog/category/:categoryId/new-subcategory',
        pageBuilder: (context, state) {
          final id = state.pathParameters['categoryId']!;
          return iosPushPage(
            key: state.pageKey,
            child: CatalogAddSubcategoryPage(categoryId: id),
          );
        },
      ),
      GoRoute(
        path: '/catalog/category/:categoryId/type/:typeId/add-item',
        pageBuilder: (context, state) {
          final cid = state.pathParameters['categoryId']!;
          final tid = state.pathParameters['typeId']!;
          final sid = state.uri.queryParameters['defaultSupplierId']?.trim();
          return iosPushPage(
            key: state.pageKey,
            child: CatalogAddItemPage(
              categoryId: cid,
              typeId: tid,
              defaultSupplierId: sid != null && sid.isNotEmpty ? sid : null,
            ),
          );
        },
      ),
      GoRoute(
        path: '/catalog/item/:itemId',
        pageBuilder: (context, state) {
          final id = state.pathParameters['itemId']!;
          return iosPushPage(
            key: state.pageKey,
            child: CatalogItemDetailPage(itemId: id),
          );
        },
      ),
      GoRoute(
        path: '/catalog/item/:itemId/timeline',
        pageBuilder: (context, state) {
          final id = state.pathParameters['itemId']!;
          return iosPushPage(
            key: state.pageKey,
            child: CatalogItemTimelinePage(itemId: id),
          );
        },
      ),
      GoRoute(
        path: '/stock/movement',
        pageBuilder: (context, state) => iosPushPage(
          key: state.pageKey,
          child: const StockMovementPage(),
        ),
      ),
      GoRoute(
        path: '/stock/reorder-suggestions',
        pageBuilder: (context, state) => iosPushPage(
          key: state.pageKey,
          child: const ReorderSuggestionsPage(),
        ),
      ),
      GoRoute(
        path: '/settings/ai-usage',
        pageBuilder: (context, state) => iosPushPage(
          key: state.pageKey,
          child: const AiUsagePage(),
        ),
      ),
      GoRoute(
        path: '/stock/reorder',
        pageBuilder: (context, state) => iosPushPage(
          key: state.pageKey,
          child: const ReorderListPage(),
        ),
      ),
      GoRoute(
        path: '/stock/today-feed',
        pageBuilder: (context, state) => iosPushPage(
          key: state.pageKey,
          child: const StockTodayFeedPage(),
        ),
      ),
      GoRoute(
        path: '/stock/intelligence/:itemId',
        pageBuilder: (context, state) {
          final id = state.pathParameters['itemId']!;
          return iosPushPage(
            key: state.pageKey,
            child: StockItemIntelligencePage(itemId: id),
          );
        },
      ),
      GoRoute(
        path: '/stock/:itemId/history',
        pageBuilder: (context, state) {
          final id = state.pathParameters['itemId']!;
          final name = state.uri.queryParameters['name'];
          return iosPushPage(
            key: state.pageKey,
            child: StockHistoryPage(itemId: id, itemName: name),
          );
        },
      ),
      GoRoute(
        path: '/catalog/item/:itemId/purchase-history',
        pageBuilder: (context, state) {
          final id = state.pathParameters['itemId']!;
          return iosPushPage(
            key: state.pageKey,
            child: ItemHistoryPage(catalogItemId: id),
          );
        },
      ),
      GoRoute(
        path: '/catalog/item/:itemId/ledger',
        pageBuilder: (context, state) {
          final id = state.pathParameters['itemId']!;
          return iosPushPage(
            key: state.pageKey,
            child: TradeLedgerPage(
              kind: TradeLedgerKind.catalogItem,
              entityId: id,
            ),
          );
        },
      ),
      GoRoute(
        path: '/catalog/category/:categoryId',
        pageBuilder: (context, state) {
          final id = state.pathParameters['categoryId']!;
          return iosPushPage(
            key: state.pageKey,
            child: CatalogCategoryDetailPage(categoryId: id),
          );
        },
      ),
      GoRoute(
        path: '/catalog/category/:categoryId/type/:typeId',
        pageBuilder: (context, state) {
          final cid = state.pathParameters['categoryId']!;
          final tid = state.pathParameters['typeId']!;
          return iosPushPage(
            key: state.pageKey,
            child: CatalogTypeItemsPage(categoryId: cid, typeId: tid),
          );
        },
      ),
      GoRoute(
        path: '/supplier/:supplierId',
        pageBuilder: (context, state) {
          final id = state.pathParameters['supplierId']!;
          return iosPushPage(
            key: state.pageKey,
            child: SupplierDetailPage(supplierId: id),
          );
        },
      ),
      GoRoute(
        path: '/supplier/:supplierId/ledger',
        pageBuilder: (context, state) {
          final id = state.pathParameters['supplierId']!;
          return iosPushPage(
            key: state.pageKey,
            child: SupplierLedgerPage(supplierId: id),
          );
        },
      ),
      GoRoute(
        path: '/supplier/:supplierId/batch-items',
        pageBuilder: (context, state) {
          final id = state.pathParameters['supplierId']!;
          return iosPushPage(
            key: state.pageKey,
            child: BatchItemCreatePage(supplierId: id),
          );
        },
      ),
      GoRoute(
        path: '/broker/:brokerId',
        pageBuilder: (context, state) {
          final id = state.pathParameters['brokerId']!;
          return iosPushPage(
            key: state.pageKey,
            child: BrokerDetailPage(brokerId: id),
          );
        },
      ),
      GoRoute(
        path: '/broker/:brokerId/ledger',
        pageBuilder: (context, state) {
          final id = state.pathParameters['brokerId']!;
          return iosPushPage(
            key: state.pageKey,
            child: BrokerHistoryPage(brokerId: id),
          );
        },
      ),
      GoRoute(
        path: '/contacts/category',
        pageBuilder: (context, state) {
          final raw = state.uri.queryParameters['name'] ?? '';
          return iosPushPage(
            key: state.pageKey,
            child: CategoryItemsPage(category: Uri.decodeComponent(raw)),
          );
        },
      ),
      GoRoute(
        path: '/item-analytics/:itemKey',
        pageBuilder: (context, state) {
          final enc = state.pathParameters['itemKey']!;
          final name = Uri.decodeComponent(enc);
          return iosPushPage(
            key: state.pageKey,
            child: ItemAnalyticsDetailPage(itemName: name),
          );
        },
      ),
      GoRoute(
        path: '/settings',
        name: 'settings',
        pageBuilder: (context, state) => iosPushPage(
          key: state.pageKey,
          child: const SettingsPage(),
        ),
      ),
      GoRoute(
        path: '/settings/business',
        name: 'settings_business',
        pageBuilder: (context, state) => iosPushPage(
          key: state.pageKey,
          child: const BusinessProfilePage(),
        ),
      ),
      GoRoute(
        path: '/settings/backup',
        name: 'settings_backup',
        pageBuilder: (context, state) => iosPushPage(
          key: state.pageKey,
          child: const BackupPage(),
        ),
      ),
      GoRoute(
        path: '/settings/maintenance/history',
        name: 'settings_maintenance_history',
        pageBuilder: (context, state) => iosPushPage(
          key: state.pageKey,
          child: const MaintenanceHistoryPage(),
        ),
      ),
      GoRoute(
        path: '/settings/users',
        name: 'settings_users',
        pageBuilder: (context, state) => iosPushPage(
          key: state.pageKey,
          child: const UserManagementPage(),
        ),
        routes: [
          GoRoute(
            path: ':userId',
            name: 'settings_user_detail',
            pageBuilder: (context, state) {
              final id = state.pathParameters['userId']!;
              return iosPushPage(
                key: state.pageKey,
                child: UserProfilePage(userId: id),
              );
            },
          ),
        ],
      ),
      GoRoute(
        path: '/admin',
        name: 'super_admin',
        pageBuilder: (context, state) => iosPushPage(
          key: state.pageKey,
          child: const SuperAdminPage(),
        ),
      ),
      GoRoute(
        path: '/staff/activity',
        name: 'staff_activity',
        pageBuilder: (context, state) => iosPushPage(
          key: state.pageKey,
          child: const StaffActivityPage(),
        ),
      ),
      GoRoute(
        path: '/staff/purchase-history/:purchaseId',
        name: 'staff_purchase_detail',
        pageBuilder: (context, state) => iosPushPage(
          key: state.pageKey,
          child: StaffPurchaseOrderDetailPage(
            purchaseId: state.pathParameters['purchaseId']!,
          ),
        ),
      ),
      GoRoute(
        path: '/entries',
        redirect: (context, state) => '/purchase',
      ),
      GoRoute(
        path: '/analytics',
        redirect: (context, state) => '/reports',
      ),
      GoRoute(
        path: '/purchase/new',
        name: 'purchase_new',
        pageBuilder: (context, state) {
          final cid = state.uri.queryParameters['catalogItemId']?.trim();
          PurchaseDraft? seed;
          bool resumeDraft =
              state.uri.queryParameters['resumeDraft'] == 'true' ||
                  state.uri.queryParameters['resume'] == '1';
          String? aiScanToken;
          Map<String, dynamic>? aiScanBaseJson;
          final ex = state.extra;
          if (ex is PurchaseDraft) {
            seed = ex;
          } else if (ex is Map) {
            try {
              final m = Map<String, dynamic>.from(ex);
              final rd = m['resumeDraft'];
              resumeDraft |= rd == true || '$rd'.toLowerCase() == 'true';
              final d = m['initialDraft'];
              if (d is PurchaseDraft) seed = d;
              final ed = m['entryDraft'];
              if (seed == null && ed is Map) {
                try {
                  seed = purchaseDraftFromAssistantEntryMap(
                    Map<String, dynamic>.from(ed),
                  );
                } catch (_) {}
              }
              final ai = m['aiScan'];
              if (ai is Map) {
                final tok = ai['token']?.toString().trim();
                if (tok != null && tok.isNotEmpty) aiScanToken = tok;
                final bs = ai['baseScan'];
                if (bs is Map) {
                  aiScanBaseJson = Map<String, dynamic>.from(bs);
                }
              }
            } catch (_) {}
          }
          return iosPushPage(
            key: ValueKey(
              'purchase_new_${seed != null ? 'seed' : resumeDraft ? 'resume' : ((cid != null && cid.isNotEmpty) ? cid : 'none')}_${aiScanToken ?? 'noai'}',
            ),
            child: PurchaseEntryWizardV2(
              initialCatalogItemId:
                  (cid != null && cid.isNotEmpty) ? cid : null,
              initialDraft: seed,
              resumeDraft: resumeDraft && seed == null,
              aiScanToken: aiScanToken,
              aiScanBaseJson: aiScanBaseJson,
            ),
          );
        },
      ),
      GoRoute(
        path: '/purchase/scan',
        name: 'purchase_scan',
        pageBuilder: (context, state) => iosPushPage(
          key: state.pageKey,
          child: const ScanPurchasePage(),
        ),
      ),
      GoRoute(
        path: '/purchase/scan-draft',
        name: 'purchase_scan_draft',
        pageBuilder: (context, state) => iosPushPage(
          key: state.pageKey,
          child: const PurchaseScanDraftWizardPage(),
        ),
      ),
      GoRoute(
        path: '/purchase/edit/:purchaseId',
        name: 'purchase_edit',
        pageBuilder: (context, state) {
          final id = state.pathParameters['purchaseId']!;
          return iosPushPage(
            key: state.pageKey,
            child: PurchaseEntryWizardV2(editingId: id),
          );
        },
      ),
      GoRoute(
        path: '/purchase/detail/:purchaseId',
        name: 'purchase_detail',
        pageBuilder: (context, state) {
          final id = state.pathParameters['purchaseId']!;
          final ex = state.extra;
          final seed = ex is TradePurchase ? ex : null;
          final seedOk = seed != null && seed.id == id;
          return iosPushPage(
            key: state.pageKey,
            child: PurchaseDetailPage(
              purchaseId: id,
              seedPurchase: seedOk ? seed : null,
            ),
          );
        },
      ),
      GoRoute(
        path: '/contacts/supplier/new',
        name: 'supplier_create',
        pageBuilder: (context, state) => iosPushPage(
          key: state.pageKey,
          child: const SupplierCreateSimple(),
        ),
      ),
      GoRoute(
        path: '/suppliers/quick-create',
        name: 'supplier_quick_create',
        pageBuilder: (context, state) => iosPushPage(
          key: state.pageKey,
          child: const SupplierCreateSimple(),
        ),
      ),
      GoRoute(
        path: '/brokers/quick-create',
        name: 'broker_quick_create',
        pageBuilder: (context, state) => iosPushPage(
          key: state.pageKey,
          child: const BrokerWizardPage(selectionReturnOnSave: true),
        ),
      ),
      GoRoute(
        path: '/notifications',
        name: 'notifications',
        pageBuilder: (context, state) => iosPushPage(
          key: state.pageKey,
          child: const NotificationsPage(),
        ),
      ),
      GoRoute(
        path: '/operations/usage',
        pageBuilder: (context, state) => iosPushPage(
          key: state.pageKey,
          child: const DailyUsagePage(),
        ),
      ),
      GoRoute(
        path: '/operations/checklist',
        pageBuilder: (context, state) => iosPushPage(
          key: state.pageKey,
          child: const StaffChecklistPage(),
        ),
      ),
      GoRoute(
        path: '/catalog/duplicates',
        pageBuilder: (context, state) => iosPushPage(
          key: state.pageKey,
          child: const CatalogDuplicatesPage(),
        ),
      ),
      GoRoute(
        path: '/stock/dead',
        pageBuilder: (context, state) => iosPushPage(
          key: state.pageKey,
          child: const StockOperationalListPage(kind: StockOperationalListKind.dead),
        ),
      ),
      GoRoute(
        path: '/stock/fast-moving',
        pageBuilder: (context, state) => iosPushPage(
          key: state.pageKey,
          child: const StockOperationalListPage(kind: StockOperationalListKind.fast),
        ),
      ),
      GoRoute(
        path: '/stock/slow-moving',
        pageBuilder: (context, state) => iosPushPage(
          key: state.pageKey,
          child: const StockOperationalListPage(kind: StockOperationalListKind.slow),
        ),
      ),
      GoRoute(
        path: '/reports/category-drill',
        name: 'reports_category_drill',
        pageBuilder: (context, state) {
          final extra = state.extra;
          if (extra is ReportsCategoryDrillPage) {
            return iosPushPage(key: state.pageKey, child: extra);
          }
          final name = Uri.decodeComponent(
            state.uri.queryParameters['name'] ?? 'Category',
          );
          return iosPushPage(
            key: state.pageKey,
            child: ReportsCategoryDrillPage(categoryName: name),
          );
        },
      ),
      GoRoute(
        path: '/reports/subcategory-drill',
        name: 'reports_subcategory_drill',
        pageBuilder: (context, state) {
          final extra = state.extra;
          if (extra is ReportsSubcategoryDrillPage) {
            return iosPushPage(key: state.pageKey, child: extra);
          }
          final name = Uri.decodeComponent(
            state.uri.queryParameters['name'] ?? 'Subcategory',
          );
          return iosPushPage(
            key: state.pageKey,
            child: ReportsSubcategoryDrillPage(subcategoryName: name),
          );
        },
      ),
      GoRoute(
        path: '/reports/item/:catalogItemId',
        name: 'reports_item_bi',
        pageBuilder: (context, state) {
          final id = state.pathParameters['catalogItemId'] ?? '';
          final name = state.uri.queryParameters['name'];
          return iosPushPage(
            key: state.pageKey,
            child: ReportsItemBiPage(
              catalogItemId: id,
              itemName: name != null ? Uri.decodeComponent(name) : null,
            ),
          );
        },
      ),
      GoRoute(
        path: '/reports/item-detail',
        name: 'reports_item_detail',
        pageBuilder: (context, state) {
          final k = state.uri.queryParameters['k'] ?? '';
          final n = Uri.decodeComponent(state.uri.queryParameters['n'] ?? '');
          return iosPushPage(
            key: state.pageKey,
            child: ReportsItemDetailPage(
              itemKey: k,
              itemName: n.isEmpty ? 'Item' : n,
            ),
          );
        },
      ),
      // Main app tabs: keep navigation in this shell only; use `navigationShell.goBranch`
      // or `context.go('/home'|'/reports'|...)` — avoid `push` onto the root stack for these paths
      // or the active tab and visible content can disagree.
      StatefulShellRoute.indexedStack(
        // Use [pageBuilder] so the shell is the [Page] child directly. The default
        // shell path (widget-only [builder] inside [MaterialPage]) can receive a
        // tiny max height on web; [Scaffold] then collapses to ~bottom bar height
        // and sits centered with a blank body. [NoTransitionPage] + expand fixes that.
        pageBuilder: (context, state, navigationShell) =>
            NoTransitionPage<void>(
          key: state.pageKey,
          name: state.name ?? state.path,
          restorationId: state.pageKey.value,
          child: SizedBox.expand(
            child: ShellScreen(navigationShell: navigationShell),
          ),
        ),
        branches: [
          // Branch 0 — Home dashboard
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                name: 'home',
                builder: (context, state) => const HomePage(),
                routes: [
                  GoRoute(
                    path: 'breakdown-more',
                    name: 'home_breakdown_more',
                    builder: (context, state) {
                      final tab = homeBreakdownTabFromQuery(
                            state.uri.queryParameters['tab'],
                          ) ??
                          HomeBreakdownTab.category;
                      return HomeBreakdownListPage(tab: tab);
                    },
                  ),
                ],
              ),
            ],
          ),
          // Branch 1 — Stock list
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/stock',
                name: 'stock_tab',
                builder: (context, state) =>
                    const StockPage(mode: StockPageMode.owner),
              ),
            ],
          ),
          // Branch 2 — Reports (full analytics UI)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/reports',
                name: 'reports_full',
                builder: (context, state) => const FullReportsPage(),
              ),
            ],
          ),
          // Branch 3 — History (purchase list)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/purchase',
                name: 'purchase',
                builder: (context, state) => const PurchaseHomePage(),
              ),
            ],
          ),
          // Branch 4 — Global search (tab); Assistant is `/assistant` full-screen push.
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/search',
                name: 'search_tab',
                builder: (context, state) =>
                    const SearchPage(embeddedInShell: true),
              ),
            ],
          ),
        ],
      ),
      StatefulShellRoute.indexedStack(
        pageBuilder: (context, state, navigationShell) =>
            NoTransitionPage<void>(
          key: state.pageKey,
          name: state.name ?? state.path,
          restorationId: state.pageKey.value,
          child: SizedBox.expand(
            child: StaffShellScreen(navigationShell: navigationShell),
          ),
        ),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/staff/home',
                name: 'staff_home',
                builder: (context, state) => const StaffDashboardPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/staff/stock',
                name: 'staff_stock',
                builder: (context, state) =>
                    const StockPage(mode: StockPageMode.staff),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/staff/scan',
                name: 'staff_scan',
                builder: (context, state) => const BarcodeScanPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/staff/purchase-history',
                name: 'staff_purchase_history',
                builder: (context, state) =>
                    const StaffPurchaseHistoryPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/staff/search',
                name: 'staff_search',
                builder: (context, state) => const SearchPage(
                  embeddedInShell: true,
                  staffShellEmbedded: true,
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

/// Full-screen fallback for unknown routes or navigation errors.
class GoRouterErrorScreen extends ConsumerWidget {
  const GoRouterErrorScreen({
    super.key,
    required this.uri,
    this.routerError,
  });

  final Uri uri;
  final Object? routerError;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Could not open this page.',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              SelectableText(
                uri.toString(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (kDebugMode && routerError != null) ...[
                const SizedBox(height: 12),
                SelectableText(
                  routerError.toString(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ],
              const Spacer(),
              FilledButton(
                onPressed: () {
                  if (session != null) {
                    context.go(authenticatedHomePath(session));
                  } else {
                    context.go('/login');
                  }
                },
                child: Text(session != null ? 'Go home' : 'Go to login'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
