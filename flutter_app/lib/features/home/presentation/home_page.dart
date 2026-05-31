import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design_system/hexa_responsive.dart';
import '../../../core/router/shell_navigation.dart';
import '../../../features/shell/shell_branch_provider.dart';
import '../../../core/auth/dashboard_role.dart';
import '../../../core/auth/auth_failure_policy.dart';
import '../../../core/auth/session_notifier.dart'
    show hexaApiProvider, sessionProvider;
import '../../../core/models/trade_purchase_models.dart';
import '../../../core/providers/app_period_provider.dart'
    show homePeriodSyncListenerProvider;
import '../../../core/providers/home_dashboard_provider.dart'
    show bustHomeDashboardVolatileCaches, homeDashboardDataProvider;
import '../../../core/providers/delivery_pipeline_provider.dart';
import '../../../core/providers/home_owner_dashboard_providers.dart'
    show
        homeInventorySummaryProvider,
        homeRecentActivityFeedProvider,
        homeWarehouseActivityFullProvider,
        homeStockAttentionCountProvider,
        stockAlertCountsProvider,
        stockAuditPeriodProvider,
        stockLowTopHomeProvider,
        stockVariancesTodayProvider;
import '../../../core/providers/purchase_post_save_provider.dart';
import '../../../core/notifications/local_notifications_service.dart';
import '../../../core/providers/connectivity_provider.dart';
import '../../../core/providers/notifications_provider.dart'
    show notificationsUnreadCountProvider;
import '../../../core/providers/prefs_provider.dart';
import '../../../core/providers/notification_center_provider.dart'
    show notificationCenterCoordinatorProvider;
import '../../../core/providers/server_notifications_provider.dart'
    show appNotificationsListProvider;
import '../../../core/providers/stock_providers.dart'
    show
        lowStockByCategoryProvider,
        stockStatusCountsProvider;
import '../../../core/providers/warehouse_alerts_provider.dart'
    show warehouseAlertsProvider;
import '../../../core/design_system/hexa_operational_tokens.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../purchase/presentation/widgets/purchase_saved_sheet.dart';
import '../../purchase/presentation/widgets/resume_purchase_draft_banner.dart';
import 'widgets/home_compact_header.dart';
import 'widgets/home_session_data_banner.dart';
import 'widgets/home_quick_actions_grid.dart';
import 'widgets/home_live_status_bar.dart';
import 'widgets/home_owner_dashboard_body.dart';
import 'widgets/home_sticky_period_header.dart';

/// True when the Home IndexedStack tab is the active shell branch (URL + nav index).
bool _homeShellTabVisible(WidgetRef ref, BuildContext context) {
  final shell = StatefulNavigationShell.maybeOf(context);
  if (shell != null) {
    return shell.currentIndex == ShellBranch.home;
  }
  return ref.watch(shellCurrentBranchProvider) == ShellBranch.home;
}

/// Harisree owner/admin home — purchase-first warehouse control center.
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage>
    with WidgetsBindingObserver {
  Timer? _rtPollHome;
  Timer? _refreshDebounce;
  Timer? _resumeRefreshDebounce;
  bool _homeTimersActive = false;
  bool _handlingPurchasePostSave = false;
  int _lastUnread = 0;
  int _lastNotifiedLowCount = 0;
  final _notifiedStaffPurchaseIds = <String>{};
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;
  DateTime? _lastThrottledInvalidate;
  DateTime? _homeLastRefreshedAt;
  bool _throttleHomeInvalidate({bool force = false}) {
    if (force) {
      _lastThrottledInvalidate = DateTime.now();
      return false;
    }
    final now = DateTime.now();
    if (_lastThrottledInvalidate != null &&
        now.difference(_lastThrottledInvalidate!).inSeconds < 8) {
      return true;
    }
    _lastThrottledInvalidate = now;
    return false;
  }

  void _invalidateAlertProviders() {
    ref.invalidate(warehouseAlertsProvider);
    ref.invalidate(stockStatusCountsProvider);
    ref.invalidate(lowStockByCategoryProvider);
    ref.invalidate(deliveryPipelineProvider);
    ref.invalidate(homeStockAttentionCountProvider);
    ref.invalidate(appNotificationsListProvider);
    ref.invalidate(notificationCenterCoordinatorProvider);
  }

  void _scheduleRefresh({bool alertsOnly = false, bool force = false}) {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 500), () {
      _refreshDebounce = null;
      if (!mounted) return;
      if (ref.read(shellCurrentBranchProvider) != ShellBranch.home) return;
      if (!force && _throttleHomeInvalidate()) return;
      if (alertsOnly) {
        _invalidateAlertProviders();
      } else {
        _invalidateHomeDataProviders();
        _maybePushBackgroundAlert();
        _maybeNotifyStaffPurchases();
      }
    });
  }

  void _invalidateHomeDataProviders() {
    _homeLastRefreshedAt = DateTime.now();
    bustHomeDashboardVolatileCaches();
    ref.invalidate(homeDashboardDataProvider);
    ref.invalidate(homeInventorySummaryProvider);
    ref.invalidate(homeRecentActivityFeedProvider);
    ref.invalidate(homeWarehouseActivityFullProvider);
    ref.invalidate(stockLowTopHomeProvider);
    ref.invalidate(lowStockByCategoryProvider);
    ref.invalidate(stockVariancesTodayProvider);
    ref.invalidate(stockAuditPeriodProvider);
    _invalidateAlertProviders();
  }

  void _setHomePollingActive(bool active) {
    if (active == _homeTimersActive) return;
    _homeTimersActive = active;
    if (!active) {
      _rtPollHome?.cancel();
      _rtPollHome = null;
      return;
    }
    _rtPollHome?.cancel();
    _rtPollHome = Timer.periodic(const Duration(seconds: 60), (_) {
      if (!mounted) return;
      if (ref.read(sessionProvider) == null ||
          ref.read(authSessionExpiredProvider)) {
        _setHomePollingActive(false);
        return;
      }
      if (ref.read(shellCurrentBranchProvider) != ShellBranch.home) return;
      _scheduleRefresh();
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _lastUnread = ref.read(notificationsUnreadCountProvider);
      // IndexedStack keeps Home mounted on other tabs — never reset shell branch here
      // (ShellScreen owns branch sync). Doing so broke Reports error handling.
      if (ref.read(shellCurrentBranchProvider) == ShellBranch.home) {
        _setHomePollingActive(true);
        _scheduleRefresh(force: true);
      }
    });
  }

  void _maybeNotifyStaffPurchases() {
    final session = ref.read(sessionProvider);
    if (session == null || !sessionHasOwnerDashboard(session)) return;
    if (!ref.read(localNotificationsOptInProvider)) return;
    final bg = _lifecycle == AppLifecycleState.paused ||
        _lifecycle == AppLifecycleState.hidden ||
        _lifecycle == AppLifecycleState.inactive;
    if (!bg) return;

    ref
        .read(hexaApiProvider)
        .listActivityLog(
          businessId: session.primaryBusiness.id,
          period: 'today',
          perPage: 12,
        )
        .then((rows) {
      if (!mounted) return;
      for (final r in rows) {
        final a = (r['action_type'] ?? '').toString();
        if (a != 'PURCHASE_CREATE') continue;
        final id = r['id']?.toString() ?? '';
        if (id.isEmpty || _notifiedStaffPurchaseIds.contains(id)) continue;
        _notifiedStaffPurchaseIds.add(id);
        if (_notifiedStaffPurchaseIds.length > 40) {
          _notifiedStaffPurchaseIds.remove(_notifiedStaffPurchaseIds.first);
        }
        final user = r['user_name']?.toString() ?? 'Staff';
        final details = r['details'];
        String? amount;
        if (details is Map) {
          amount = details['total_formatted']?.toString();
        }
        unawaited(
          LocalNotificationsService.instance.showStaffPurchase(
            staffName: user,
            amountFormatted: amount,
          ),
        );
      }
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _rtPollHome?.cancel();
    _refreshDebounce?.cancel();
    _resumeRefreshDebounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _maybePushBackgroundAlert() {
    if (!ref.read(localNotificationsOptInProvider)) return;
    final bg = _lifecycle == AppLifecycleState.paused ||
        _lifecycle == AppLifecycleState.hidden ||
        _lifecycle == AppLifecycleState.inactive;
    if (!bg) return;
    final unread = ref.read(notificationsUnreadCountProvider);
    if (unread <= _lastUnread) return;
    final delta = unread - _lastUnread;
    unawaited(
      LocalNotificationsService.instance.showStockOrInAppAlert(
        title: 'Harisree Agency',
        body:
            delta == 1 ? 'You have 1 new alert' : 'You have $delta new alerts',
        payload: 'notifications',
      ),
    );
    _lastUnread = unread;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    super.didChangeAppLifecycleState(s);
    _lifecycle = s;
    if (s == AppLifecycleState.resumed) {
      _lastUnread = ref.read(notificationsUnreadCountProvider);
    }
    if (s != AppLifecycleState.resumed) return;
    if (ref.read(shellCurrentBranchProvider) != ShellBranch.home) return;
    final last = _homeLastRefreshedAt;
    if (last != null && DateTime.now().difference(last).inMinutes < 5) {
      return;
    }
    _resumeRefreshDebounce?.cancel();
    _resumeRefreshDebounce = Timer(const Duration(milliseconds: 320), () {
      if (!mounted) {
        _resumeRefreshDebounce = null;
        return;
      }
      _resumeRefreshDebounce = null;
      unawaited(_refresh());
    });
  }

  Future<void> _refresh() async {
    if (ref.read(shellCurrentBranchProvider) != ShellBranch.home) return;
    _scheduleRefresh(force: true);
  }

  Future<void> _showAccountMenu() async {
    final session = ref.read(sessionProvider);
    if (session == null || !mounted) return;
    final action = await showHexaBottomSheet<String>(
      context: context,
      compact: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(session.primaryBusiness.role.toUpperCase()),
            subtitle: Text(
              session.primaryBusiness.contactEmail ??
                  session.primaryBusiness.phone ??
                  session.primaryBusiness.name,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Sign out'),
            onTap: () => Navigator.pop(context, 'logout'),
          ),
        ],
      ),
    );
    if (action == 'logout' && mounted) {
      await ref.read(sessionProvider.notifier).logout();
      if (mounted) context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(shellCurrentBranchProvider, (prev, next) {
      final onHome = next == ShellBranch.home;
      _setHomePollingActive(onHome);
      if (onHome && prev != ShellBranch.home && !_throttleHomeInvalidate()) {
        _scheduleRefresh();
      }
    });

    if (!_homeShellTabVisible(ref, context)) {
      // IndexedStack keeps this widget mounted off-tab — avoid painting when another tab is active.
      return const SizedBox.shrink();
    }

    ref.watch(notificationCenterCoordinatorProvider);

    ref.listen<PurchasePostSavePayload?>(purchasePostSaveProvider,
        (prev, next) {
      if (next == null || _handlingPurchasePostSave) return;
      _handlingPurchasePostSave = true;
      unawaited(_doHandlePurchasePostSave(next));
    });
    ref.listen(stockAlertCountsProvider, (prev, next) {
      if (!ref.read(localNotificationsOptInProvider)) return;
      next.whenData((counts) {
        final count = counts.low + counts.critical;
        if (count <= _lastNotifiedLowCount) {
          _lastNotifiedLowCount = count;
          return;
        }
        _lastNotifiedLowCount = count;
        final rows = ref.read(stockLowTopHomeProvider).valueOrNull;
        if (rows != null && rows.isNotEmpty) {
          final r = rows.first;
          final name =
              r['name']?.toString() ?? r['item_name']?.toString() ?? 'Item';
          final qty = r['stock_qty'] ?? r['quantity'] ?? r['on_hand'];
          final unit =
              r['unit']?.toString() ?? r['stock_unit']?.toString() ?? '';
          final qtyLabel = qty != null
              ? '${qty.toString()} ${unit.trim()} left'.trim()
              : 'running low';
          unawaited(LocalNotificationsService.instance.showLowStockItem(
            itemName: name,
            detail: qtyLabel,
          ));
        } else {
          unawaited(LocalNotificationsService.instance.showLowStockItem(
            itemName: 'Inventory',
            detail:
                count == 1 ? '1 item running low' : '$count items running low',
          ));
        }
      });
    });

    ref.watch(homePeriodSyncListenerProvider);

    final session = ref.watch(sessionProvider);
    final hasDashboard = session != null && sessionHasOwnerDashboard(session);
    final conn = ref.watch(connectivityResultsProvider);
    final offline =
        conn.valueOrNull != null && isOfflineResult(conn.valueOrNull!);
    final gutter = HexaResponsive.pageGutter(context, operational: true);

    return Scaffold(
      backgroundColor: HexaColors.brandBackground,
      body: ColoredBox(
        color: HexaColors.brandBackground,
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 0),
                sliver: SliverToBoxAdapter(
                  child: HexaResponsiveCenter(
                    maxWidth: HexaResponsive.maxContentWidth,
                    padding: EdgeInsets.zero,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        HomeCompactHeader(
                          offline: offline,
                          onSettingsLongPress: _showAccountMenu,
                        ),
                        if (hasDashboard) ...[
                          const SizedBox(height: HexaOp.cardGap),
                          HomeLiveStatusBar(
                            offline: offline,
                            lastRefreshedAt: _homeLastRefreshedAt,
                            isOwner: true,
                          ),
                        ],
                        const SizedBox(height: HexaOp.cardGap),
                        const ResumePurchaseDraftBanner(),
                        if (hasDashboard) const HomeSessionDataBanner(),
                      ],
                    ),
                  ),
                ),
              ),
              if (hasDashboard)
                SliverPersistentHeader(
                  pinned: true,
                  delegate: HomeStickyPeriodHeader(),
                ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 100),
                sliver: SliverToBoxAdapter(
                  child: HexaResponsiveCenter(
                    maxWidth: HexaResponsive.maxContentWidth,
                    padding: EdgeInsets.zero,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (hasDashboard)
                          const HomeOwnerDashboardBody()
                        else
                          HomeQuickActionsGrid(
                            isOwner: false,
                            onScan: () => context.push('/barcode/scan'),
                            onStock: () => goShellTab(
                                  context,
                                  ref,
                                  branch: ShellBranch.stock,
                                  location: '/stock',
                                ),
                            onPurchase: () => context.push('/purchase/new'),
                            onReports: () => goShellTab(
                                  context,
                                  ref,
                                  branch: ShellBranch.reports,
                                  location: '/reports',
                                ),
                            onBarcode: () => context.push('/barcode/bulk-print'),
                            onUsers: () => context.push('/settings/users'),
                          ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Future<void> _doHandlePurchasePostSave(
      PurchasePostSavePayload payload) async {
    try {
      if (!mounted) return;
      final container = ProviderScope.containerOf(context, listen: false);
      container.invalidate(homeDashboardDataProvider);
      _invalidateOwnerCachesFromContainer(container);
      container.read(purchasePostSaveProvider.notifier).state = null;
      _handlingPurchasePostSave = false;
      if (!mounted) return;
      final route = await showPurchaseSavedSheet(
        context,
        ref,
        savedJson: payload.savedJson,
        wasEdit: payload.wasEdit,
      );
      if (!mounted) return;
      final sid = payload.savedJson['id']?.toString();
      if (route == 'edit_missing' && sid != null && sid.isNotEmpty) {
        context.go('/purchase/edit/$sid');
      } else if (route == 'detail' && sid != null && sid.isNotEmpty) {
        TradePurchase? seed;
        try {
          seed = TradePurchase.fromJson(
            Map<String, dynamic>.from(payload.savedJson),
          );
        } catch (_) {}
        if (!mounted) return;
        context.go('/purchase/detail/$sid', extra: seed);
      }
    } finally {
      _handlingPurchasePostSave = false;
    }
  }

  void _invalidateOwnerCachesFromContainer(ProviderContainer c) {
    bustHomeDashboardVolatileCaches();
    c.invalidate(homeInventorySummaryProvider);
    c.invalidate(stockStatusCountsProvider);
    c.invalidate(stockLowTopHomeProvider);
    c.invalidate(stockAuditPeriodProvider);
    c.invalidate(stockVariancesTodayProvider);
    c.invalidate(homeRecentActivityFeedProvider);
    c.invalidate(homeWarehouseActivityFullProvider);
    c.invalidate(homeDashboardDataProvider);
    c.invalidate(warehouseAlertsProvider);
  }
}
