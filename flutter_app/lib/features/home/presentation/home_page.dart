import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/json_coerce.dart';
import '../../../core/models/session.dart';
import '../../../core/models/trade_purchase_models.dart';
import '../../../core/providers/home_dashboard_provider.dart'
    show bustHomeDashboardVolatileCaches, homeDashboardDataProvider;
import '../../../core/providers/home_owner_dashboard_providers.dart'
    show
        activeSessionsCountProvider,
        activeStaffSessionsProvider,
        homeMonthDashboardDataProvider,
        homeRecentActivityFeedProvider,
        homeRecentPurchasesCompactProvider,
        homeTodayDashboardDataProvider,
        stockAlertCountsProvider,
        stockAuditDayProvider,
        stockCriticalCountProvider,
        stockLowCountProvider,
        stockLowTopHomeProvider,
        stockVariancesTodayProvider;
import 'widgets/home_owner_dashboard_sections.dart';
import 'widgets/daily_stock_report_sheet.dart';
import 'widgets/stock_health_score.dart';
import '../../stock/presentation/widgets/stock_today_feed.dart';
import '../../../core/providers/purchase_post_save_provider.dart';
import '../../../core/notifications/local_notifications_service.dart';
import '../../../core/providers/connectivity_provider.dart';
import '../../../core/providers/notifications_provider.dart'
    show notificationsUnreadCountProvider;
import '../../../core/providers/prefs_provider.dart';
import '../../../core/providers/server_notifications_provider.dart';
import '../../../core/providers/catalog_providers.dart';
import '../../../core/providers/stock_providers.dart';
import '../../../core/providers/suppliers_list_provider.dart';
import '../../../core/providers/reports_provider.dart';
import '../../../core/providers/trade_purchases_provider.dart'
    show invalidateTradePurchaseCaches, invalidateTradePurchaseCachesFromContainer;
import '../../../core/theme/hexa_colors.dart';
import '../../../shared/widgets/operational_ui.dart';
import '../../../shared/widgets/shell_quick_ref_actions.dart';
import '../../purchase/presentation/widgets/purchase_saved_sheet.dart';
import '../../purchase/presentation/widgets/resume_purchase_draft_banner.dart';

String _inr(num n) =>
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
        .format(n);

bool _sessionIsOwner(Session s) {
  final r = s.primaryBusiness.role.toLowerCase();
  return r == 'owner' || r == 'super_admin' || s.isSuperAdmin;
}

DateTime _todayDate() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

/// Harisree owner home: quick actions, today stats, stock, audits, recent purchases.
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  Timer? _poll;
  Timer? _rtPoll;
  Timer? _resumeRefreshDebounce;
  bool _handlingPurchasePostSave = false;
  int _lastUnread = 0;
  int _lastNotifiedLowCount = 0;
  final _notifiedStaffPurchaseIds = <String>{};
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;
  late final AnimationController _livePulse;
  DateTime? _lastRefreshedAt;

  @override
  void initState() {
    super.initState();
    _livePulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _lastRefreshedAt = DateTime.now();
    WidgetsBinding.instance.addObserver(this);
    _poll = Timer.periodic(const Duration(minutes: 5), (_) {
      if (!mounted) return;
      bustHomeDashboardVolatileCaches();
      invalidateTradePurchaseCaches(ref);
      ref.invalidate(homeTodayDashboardDataProvider);
      ref.invalidate(stockAlertCountsProvider);
      ref.invalidate(stockLowTopHomeProvider);
      ref.invalidate(stockAuditDayProvider(_todayDate()));
      ref.invalidate(stockVariancesTodayProvider);
      ref.invalidate(activeSessionsCountProvider);
      ref.invalidate(activeStaffSessionsProvider);
      ref.invalidate(homeMonthDashboardDataProvider);
      ref.invalidate(homeRecentPurchasesCompactProvider);
      ref.invalidate(homeRecentActivityFeedProvider);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _lastUnread = ref.read(notificationsUnreadCountProvider);
      }
    });
    _rtPoll = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      setState(() => _lastRefreshedAt = DateTime.now());
      ref.invalidate(stockListProvider);
      invalidateTradePurchaseCaches(ref);
      ref.invalidate(homeTodayDashboardDataProvider);
      ref.invalidate(stockAlertCountsProvider);
      ref.invalidate(stockLowTopHomeProvider);
      ref.invalidate(stockAuditDayProvider(_todayDate()));
      ref.invalidate(stockVariancesTodayProvider);
      ref.invalidate(homeRecentPurchasesCompactProvider);
      ref.invalidate(homeMonthDashboardDataProvider);
      ref.invalidate(homeRecentActivityFeedProvider);
      ref.invalidate(activeStaffSessionsProvider);
      ref.invalidate(appNotificationUnreadCountProvider);
      _maybePushBackgroundAlert();
      _maybeNotifyStaffPurchases();
    });
  }

  void _maybeNotifyStaffPurchases() {
    final session = ref.read(sessionProvider);
    if (session == null || !_sessionIsOwner(session)) return;
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
    _livePulse.dispose();
    _poll?.cancel();
    _rtPoll?.cancel();
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
        body: delta == 1
            ? 'You have 1 new alert'
            : 'You have $delta new alerts',
        payload: 'notifications',
      ),
    );
    _lastUnread = unread;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    _lifecycle = s;
    if (s == AppLifecycleState.resumed) {
      _lastUnread = ref.read(notificationsUnreadCountProvider);
    }
    if (s != AppLifecycleState.resumed) return;
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
    bustHomeDashboardVolatileCaches();
    ref.invalidate(homeDashboardDataProvider);
    ref.invalidate(homeTodayDashboardDataProvider);
    ref.invalidate(homeMonthDashboardDataProvider);
    ref.invalidate(stockLowCountProvider);
    ref.invalidate(stockCriticalCountProvider);
    ref.invalidate(stockLowTopHomeProvider);
    ref.invalidate(stockAuditDayProvider(_todayDate()));
    ref.invalidate(stockVariancesTodayProvider);
    ref.invalidate(activeSessionsCountProvider);
    ref.invalidate(activeStaffSessionsProvider);
    ref.invalidate(homeRecentPurchasesCompactProvider);
    ref.invalidate(homeRecentActivityFeedProvider);
    invalidateTradePurchaseCaches(ref);
    ref.invalidate(reportsPurchasesPayloadProvider);
    if (mounted) setState(() => _lastRefreshedAt = DateTime.now());
  }

  String _liveStatsLine(int lowCount) {
    final at = _lastRefreshedAt;
    final ago = at == null
        ? 'just now'
        : () {
            final d = DateTime.now().difference(at);
            if (d.inSeconds < 60) return 'just now';
            if (d.inMinutes < 60) return '${d.inMinutes}m ago';
            return '${d.inHours}h ago';
          }();
    return 'Updated $ago · $lowCount low stock';
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<PurchasePostSavePayload?>(purchasePostSaveProvider, (prev, next) {
      if (next == null || _handlingPurchasePostSave) return;
      _handlingPurchasePostSave = true;
      unawaited(_doHandlePurchasePostSave(next));
    });
    ref.listen(stockLowCountProvider, (prev, next) {
      if (!ref.read(localNotificationsOptInProvider)) return;
      next.whenData((count) {
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
            detail: count == 1
                ? '1 item running low'
                : '$count items running low',
          ));
        }
      });
    });

    final session = ref.watch(sessionProvider);
    final isOwner = session != null && _sessionIsOwner(session);
    final todayAsync = ref.watch(homeTodayDashboardDataProvider);
    final monthAsync = ref.watch(homeMonthDashboardDataProvider);
    final lowN = ref.watch(stockLowCountProvider);
    final critN = ref.watch(stockCriticalCountProvider);
    final lowRows = ref.watch(stockLowTopHomeProvider);
    final todayDay = _todayDate();
    final audits = ref.watch(stockAuditDayProvider(todayDay));
    final variances = ref.watch(stockVariancesTodayProvider);
    final recentPurch = ref.watch(homeRecentPurchasesCompactProvider);
    final alertCounts = ref.watch(stockAlertCountsProvider).valueOrNull;
    final stockHealth = StockHealthScore.compute(
      lowCount: alertCounts?.low ?? lowN.valueOrNull ?? 0,
      criticalCount: alertCounts?.critical ?? critN.valueOrNull ?? 0,
      outCount: 0,
    );
    final bellCount = ref.watch(notificationsUnreadCountProvider);
    final conn = ref.watch(connectivityResultsProvider);
    final offline =
        conn.valueOrNull != null && isOfflineResult(conn.valueOrNull!);

    return Scaffold(
      backgroundColor: HexaColors.brandBackground,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: HexaColors.brandBackground,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Harisree Agency',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                    letterSpacing: -0.2,
                    color: Color(0xFF0F172A),
                  ),
                ),
                if (!offline) ...[
                  const SizedBox(width: 8),
                  FadeTransition(
                    opacity: Tween<double>(begin: 0.45, end: 1).animate(
                      CurvedAnimation(
                        parent: _livePulse,
                        curve: Curves.easeInOut,
                      ),
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F5E9),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFF2E7D32),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFF2E7D32),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Live',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: Colors.green.shade800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ] else ...[
                  const SizedBox(width: 8),
                  Text(
                    'Offline',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ],
            ),
            Text(
              DateFormat('EEE, d MMM yyyy').format(DateTime.now()),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
        actions: [
          if (isOwner)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: StockHealthScoreBadge(health: stockHealth, compact: true),
            ),
          if (session != null)
            PopupMenuButton<String>(
              tooltip: 'Account',
              offset: const Offset(0, 40),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: HexaColors.brandPrimary.withValues(alpha: 0.15),
                child: Text(
                  () {
                    final t = session.primaryBusiness.effectiveDisplayTitle;
                    return t.isNotEmpty ? t[0].toUpperCase() : 'H';
                  }(),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: HexaColors.brandPrimary,
                  ),
                ),
              ),
              onSelected: (v) async {
                if (v == 'logout') {
                  await ref.read(sessionProvider.notifier).logout();
                  if (context.mounted) context.go('/login');
                }
              },
              itemBuilder: (ctx) => [
                PopupMenuItem(
                  enabled: false,
                  child: Text(
                    session.primaryBusiness.role.toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const PopupMenuItem(
                  value: 'logout',
                  child: Text('Sign out'),
                ),
              ],
            ),
          IconButton(
            tooltip: 'Notifications',
            onPressed: () => context.push('/notifications'),
            icon: Badge(
              isLabelVisible: bellCount > 0,
              label: Text(
                bellCount > 99 ? '99+' : '$bellCount',
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
              ),
              child: const Icon(Icons.notifications_outlined),
            ),
          ),
          ShellQuickRefActions(
            onRefresh: _refresh,
            suppressToolbarSearch: true,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: true,
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
            children: [
              const ResumePurchaseDraftBanner(),
              const SizedBox(height: 6),
              _CircularQuickActionsRow(
                isOwner: isOwner,
                onScan: () => context.push('/barcode/scan'),
                onAddStock: () => context.go('/stock'),
                onPurchase: () => context.push('/purchase/new'),
                onReports: () => context.go('/reports'),
                onBulkPrint: () => context.push('/barcode/bulk-print'),
                onUsers: () => context.push('/settings/users'),
                onDailyReport: isOwner
                    ? () => DailyStockReportSheet.show(context)
                    : null,
              ),
              const SizedBox(height: 8),
              if (isOwner && !offline)
                OperationalLiveBanner(
                  pulse: _livePulse,
                  statsLine: _liveStatsLine(lowN.valueOrNull ?? 0),
                ),
              if (isOwner) ...[
                const SizedBox(height: 10),
                HomeQuickStatsRow(
                  todayAsync: todayAsync,
                  monthAsync: monthAsync,
                  lowN: lowN,
                  critN: critN,
                ),
                const SizedBox(height: 10),
                const HomeStaffActivitySection(),
                const SizedBox(height: 10),
                const HomeRecentActivitySection(),
              ],
              const SizedBox(height: 10),
              const _HomeCatalogChips(),
              const SizedBox(height: 10),
              OperationalSection(
                title: 'Low stock',
                dense: true,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () => context.push('/stock/reorder'),
                      child: const Text('Reorder', style: TextStyle(fontSize: 12)),
                    ),
                    TextButton(
                      onPressed: () {
                        ref.read(stockListQueryProvider.notifier).state =
                            const StockListQuery(status: 'low', sort: 'stock_asc');
                        context.go('/stock');
                      },
                      child: const Text('All', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
                child: _LowStockTable(rowsAsync: lowRows),
              ),
              variances.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (rows) {
                  if (rows.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Material(
                      color: const Color(0xFFFFF5F5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: Color(0xFFC62828)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.warning_amber_rounded,
                                  color: Color(0xFFC62828),
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Stock variances · ${rows.length} item(s)',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Counted stock does not match purchase qty',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            for (final v in rows.take(3))
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Text(
                                  '${v['item_name'] ?? 'Item'}: expected '
                                  '${v['expected_qty'] ?? '—'} · found '
                                  '${v['found_qty'] ?? '—'}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              OperationalSection(
                title: "Today's stock movement",
                dense: true,
                trailing: TextButton(
                  onPressed: () => context.push('/stock/today-feed'),
                  child: const Text('View all', style: TextStyle(fontSize: 12)),
                ),
                child: audits.when(
                  loading: () => const Center(
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                  error: (_, __) =>
                      const Text('Could not load stock movement'),
                  data: (rows) => StockTodayFeed(
                    rows: rows,
                    maxRows: 6,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              OperationalSection(
                title: "Today's purchases",
                dense: true,
                trailing: TextButton(
                  onPressed: () => context.go('/purchase'),
                  child: const Text('History', style: TextStyle(fontSize: 12)),
                ),
                child: _RecentPurchasesCompact(rowsAsync: recentPurch),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _doHandlePurchasePostSave(PurchasePostSavePayload payload) async {
    try {
      if (!mounted) return;
      final container = ProviderScope.containerOf(context, listen: false);
      container.invalidate(homeDashboardDataProvider);
      container.invalidate(homeTodayDashboardDataProvider);
      _invalidateOwnerCachesFromContainer(container);
      invalidateTradePurchaseCachesFromContainer(container);
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
    c.invalidate(homeTodayDashboardDataProvider);
    c.invalidate(stockAlertCountsProvider);
    c.invalidate(stockLowTopHomeProvider);
    c.invalidate(stockAuditDayProvider(_todayDate()));
    c.invalidate(stockVariancesTodayProvider);
    c.invalidate(activeSessionsCountProvider);
    c.invalidate(activeStaffSessionsProvider);
    c.invalidate(homeMonthDashboardDataProvider);
    c.invalidate(homeRecentPurchasesCompactProvider);
    c.invalidate(homeRecentActivityFeedProvider);
  }
}

class _CircularQuickActionsRow extends StatelessWidget {
  const _CircularQuickActionsRow({
    required this.isOwner,
    required this.onScan,
    required this.onAddStock,
    required this.onPurchase,
    required this.onReports,
    required this.onBulkPrint,
    required this.onUsers,
    this.onDailyReport,
  });

  final bool isOwner;
  final VoidCallback onScan;
  final VoidCallback onAddStock;
  final VoidCallback onPurchase;
  final VoidCallback onReports;
  final VoidCallback onBulkPrint;
  final VoidCallback onUsers;
  final VoidCallback? onDailyReport;

  @override
  Widget build(BuildContext context) {
    final actions = <({String label, IconData icon, VoidCallback onTap})>[
      (label: 'Scan', icon: Icons.qr_code_scanner_rounded, onTap: onScan),
      (label: 'Stock', icon: Icons.inventory_2_outlined, onTap: onAddStock),
      (label: 'Purchase', icon: Icons.add_shopping_cart_outlined, onTap: onPurchase),
      (label: 'Reports', icon: Icons.bar_chart_outlined, onTap: onReports),
      (label: 'Print', icon: Icons.print_outlined, onTap: onBulkPrint),
      if (isOwner && onDailyReport != null)
        (label: 'Daily', icon: Icons.summarize_outlined, onTap: onDailyReport!),
      if (isOwner) (label: 'Users', icon: Icons.group_outlined, onTap: onUsers),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        children: [
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            CircularQuickAction(
              icon: actions[i].icon,
              label: actions[i].label,
              onTap: actions[i].onTap,
            ),
          ],
        ],
      ),
    );
  }
}

class _HomeCatalogChips extends ConsumerWidget {
  const _HomeCatalogChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catsAsync = ref.watch(itemCategoriesListProvider);
    final suppliersAsync = ref.watch(suppliersListProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        catsAsync.when(
          loading: () => const SizedBox(height: 34),
          error: (_, __) => const SizedBox.shrink(),
          data: (cats) {
            final names = [
              for (final c in cats)
                if ((c['name'] ?? '').toString().trim().isNotEmpty)
                  c['name'].toString().trim(),
            ];
            if (names.isEmpty) return const SizedBox.shrink();
            return OperationalPillRow(
              labels: names.take(12).toList(),
              onSelected: (name) {
                ref.read(stockListQueryProvider.notifier).state =
                    StockListQuery(category: name, page: 1);
                context.go('/stock');
              },
            );
          },
        ),
        const SizedBox(height: 6),
        suppliersAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
          data: (rows) {
            final names = [
              for (final s in rows)
                if ((s['name'] ?? '').toString().trim().isNotEmpty)
                  s['name'].toString().trim(),
            ];
            if (names.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 12, bottom: 4),
                  child: Text(
                    'Suppliers',
                    style: HexaDsType.label(11, color: HexaDsColors.textMuted),
                  ),
                ),
                OperationalPillRow(
                  labels: names.take(10).toList(),
                  onSelected: (name) {
                    ref.read(stockListQueryProvider.notifier).state =
                        StockListQuery(q: name, page: 1);
                    context.go('/stock');
                  },
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _LowStockTable extends StatelessWidget {
  const _LowStockTable({required this.rowsAsync});

  final AsyncValue<List<Map<String, dynamic>>> rowsAsync;

  @override
  Widget build(BuildContext context) {
    return rowsAsync.when(
      loading: () => const Center(child: Padding(
        padding: EdgeInsets.all(16),
        child: CircularProgressIndicator(strokeWidth: 2),
      )),
      error: (e, _) => Text(
        'Could not load low stock alerts.',
        style: TextStyle(color: Colors.red.shade700, fontSize: 13),
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return Text(
            'No low-stock items',
            style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w600),
          );
        }
        return Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                title: Text(
                  rows[i]['name']?.toString() ?? '—',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                ),
                subtitle: Text(
                  '${rows[i]['current_stock'] ?? '—'} / ${rows[i]['reorder_level'] ?? '—'} ${rows[i]['unit'] ?? ''}',
                  style: const TextStyle(fontSize: 11),
                ),
                trailing: Text(
                  (rows[i]['stock_status'] ?? '').toString(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: HexaColors.brandPrimary,
                  ),
                ),
                onTap: () {
                  final id = rows[i]['id']?.toString();
                  if (id != null && id.isNotEmpty) {
                    context.push('/catalog/item/$id');
                  }
                },
              ),
              if (i < rows.length - 1)
                const Divider(height: 1, indent: 12, endIndent: 12),
            ],
          ],
        );
      },
    );
  }
}

class _RecentPurchasesCompact extends StatelessWidget {
  const _RecentPurchasesCompact({required this.rowsAsync});

  final AsyncValue<List<Map<String, dynamic>>> rowsAsync;

  @override
  Widget build(BuildContext context) {
    return rowsAsync.when(
      loading: () => const Center(child: Padding(
        padding: EdgeInsets.all(12),
        child: CircularProgressIndicator(strokeWidth: 2),
      )),
      error: (_, __) => const Text('Could not load purchases'),
      data: (rows) {
        if (rows.isEmpty) {
          return Text('No purchases today', style: TextStyle(color: Colors.grey.shade600));
        }
        return Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                title: Text(
                  rows[i]['supplier_name']?.toString() ?? rows[i]['bill_no']?.toString() ?? 'Purchase',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                  ),
                  subtitle: Text(
                    rows[i]['purchase_date']?.toString() ?? '',
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: Text(
                    _inr(coerceToDouble(rows[i]['total_amount'] ?? rows[i]['bill_total'] ?? 0)),
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                  ),
                  onTap: () {
                    final id = rows[i]['id']?.toString();
                    if (id != null && id.isNotEmpty) {
                      context.push('/purchase/detail/$id');
                    }
                  },
                ),
              if (i < rows.length - 1)
                const Divider(height: 1, indent: 12, endIndent: 12),
            ],
          ],
        );
      },
    );
  }
}
