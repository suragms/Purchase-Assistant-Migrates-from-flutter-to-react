import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/providers/catalog_providers.dart';
import '../../../core/providers/home_owner_dashboard_providers.dart';
import '../../../core/providers/reorder_list_provider.dart';
import '../../../core/providers/analytics_kpi_provider.dart'
    show analyticsDateRangeProvider;
import '../../../core/providers/stock_providers.dart';
import 'package:intl/intl.dart';
import '../../../core/providers/suppliers_list_provider.dart';
import '../../home/presentation/widgets/stock_health_score.dart';
import 'widgets/stock_today_feed.dart';
import '../../../core/router/navigation_ext.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/utils/unit_utils.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../../../core/widgets/list_skeleton.dart';
import '../../../shared/widgets/operational_ui.dart';
import 'update_stock_sheet.dart';
import 'widgets/stock_filter_bottom_sheet.dart';

class StockPage extends ConsumerStatefulWidget {
  const StockPage({super.key});

  @override
  ConsumerState<StockPage> createState() => _StockPageState();
}

final stockPageLowListProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return [];
  final m = await ref.read(hexaApiProvider).listStockLow(
        businessId: session.primaryBusiness.id,
        page: 1,
        perPage: 100,
      );
  final items = m['items'];
  if (items is! List) return [];
  return [
    for (final e in items)
      if (e is Map) Map<String, dynamic>.from(e),
  ];
});

class _StockPageState extends ConsumerState<StockPage>
    with TickerProviderStateMixin {
  final _searchCtrl = TextEditingController();
  final _subcatCtrl = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;
  Timer? _liveRefresh;
  bool _loadingMore = false;
  late final TabController _mainTabs;
  late final AnimationController _livePulse;
  DateTime? _lastRefreshedAt;

  @override
  void initState() {
    super.initState();
    _mainTabs = TabController(length: 5, vsync: this);
    _livePulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _lastRefreshedAt = DateTime.now();
    _liveRefresh = Timer.periodic(const Duration(seconds: 60), (_) {
      if (!mounted) return;
      ref.invalidate(stockListProvider);
      ref.invalidate(stockAlertCountsProvider);
      setState(() => _lastRefreshedAt = DateTime.now());
    });
    _searchCtrl.addListener(_onSearchChanged);
    _subcatCtrl.text = ref.read(stockListQueryProvider).subcategory;
    _scroll.addListener(_onScrollLoadMore);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final range = ref.read(analyticsDateRangeProvider);
      final fmt = DateFormat('yyyy-MM-dd');
      ref.read(stockListQueryProvider.notifier).state =
          ref.read(stockListQueryProvider).copyWith(
                includePeriod: true,
                periodStart: fmt.format(range.from),
                periodEnd: fmt.format(range.to),
              );
    });
  }

  void _onScrollLoadMore() {
    if (!_scroll.hasClients || _loadingMore) return;
    if (_scroll.position.extentAfter > 200) return;
    final q = ref.read(stockListQueryProvider);
    final data = ref.read(stockListProvider).valueOrNull;
    if (data == null) return;
    final total = (data['total'] as num?)?.toInt() ?? 0;
    final perPage = (data['per_page'] as num?)?.toInt() ?? q.perPage;
    final page = (data['page'] as num?)?.toInt() ?? 1;
    final pages = (total / perPage).ceil().clamp(1, 99999);
    if (page >= pages) return;
    setState(() => _loadingMore = true);
    ref.read(stockListQueryProvider.notifier).state =
        q.copyWith(page: page + 1);
  }

  bool _isShellStockRoot(BuildContext context) {
    final p = GoRouterState.of(context).uri.path;
    return p == '/stock' || p == '/staff/stock';
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      ref.read(stockListQueryProvider.notifier).state =
          ref.read(stockListQueryProvider).copyWith(
                q: _searchCtrl.text.trim(),
                page: 1,
              );
    });
  }

  @override
  void dispose() {
    _mainTabs.dispose();
    _livePulse.dispose();
    _liveRefresh?.cancel();
    _debounce?.cancel();
    _scroll.dispose();
    _searchCtrl.dispose();
    _subcatCtrl.dispose();
    super.dispose();
  }

  String _timeAgo(dynamic raw) {
    final at = raw is String ? DateTime.tryParse(raw) : null;
    if (at == null) return '';
    final diff = DateTime.now().difference(at.toLocal());
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  String _fmtQty(dynamic v) {
    if (v == null) return '—';
    if (v is num) {
      return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
    }
    return '$v';
  }

  Color _statusColor(String st, ColorScheme cs) {
    switch (st) {
      case 'out':
        return cs.error;
      case 'critical':
        return const Color(0xFFC62828);
      case 'low':
        return const Color(0xFFE65100);
      case 'healthy':
        return const Color(0xFF2E7D32);
      default:
        return cs.onSurfaceVariant;
    }
  }

  Color _stockQtyColor(String st, dynamic curStock, ColorScheme cs) {
    final isZero = curStock is num
        ? curStock <= 0
        : curStock == null || curStock.toString() == '0';
    if (st == 'out' || st == 'critical' || isZero) {
      return _statusColor(st, cs);
    }
    if (st == 'low') return const Color(0xFFE65100);
    return HexaDsColors.textPrimary;
  }

  bool _updatedToday(dynamic raw) {
    final at = raw is String ? DateTime.tryParse(raw)?.toLocal() : null;
    if (at == null) return false;
    final now = DateTime.now();
    return at.year == now.year && at.month == now.month && at.day == now.day;
  }

  String _liveStatsLine(int total, int lowN) {
    final at = _lastRefreshedAt;
    final ago = at == null
        ? 'just now'
        : () {
            final d = DateTime.now().difference(at);
            if (d.inSeconds < 60) return 'just now';
            if (d.inMinutes < 60) return '${d.inMinutes}m ago';
            return '${d.inHours}h ago';
          }();
    return '$total items · $lowN low · updated $ago';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final q = ref.watch(stockListQueryProvider);
    final listAsync = ref.watch(stockListProvider);
    final catsAsync = ref.watch(itemCategoriesListProvider);
    final suppliersAsync = ref.watch(suppliersListProvider);

    ref.listen<StockListQuery>(stockListQueryProvider, (prev, next) {
      if (prev?.subcategory == next.subcategory) return;
      final text = next.subcategory;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _subcatCtrl.text == text) return;
        _subcatCtrl.text = text;
      });
    });

    final shellStock = _isShellStockRoot(context);
    final lowN = ref.watch(stockLowCountProvider).valueOrNull ?? 0;
    final critN = ref.watch(stockCriticalCountProvider).valueOrNull ?? 0;
    final reorderN = ref.watch(reorderPendingCountProvider).valueOrNull ?? 0;
    final alertCounts = ref.watch(stockAlertCountsProvider).valueOrNull;
    final stockHealth = StockHealthScore.compute(
      lowCount: alertCounts?.low ?? lowN,
      criticalCount: alertCounts?.critical ?? critN,
      outCount: 0,
    );
    final now = DateTime.now();
    final todayDay = DateTime(now.year, now.month, now.day);
    final todayAudits = ref.watch(stockAuditDayProvider(todayDay));
    final todayCount = todayAudits.valueOrNull?.length ?? 0;
    final listTotal = listAsync.valueOrNull?['total'] as int? ?? 0;
    final lowTabCount = lowN + critN;

    ref.listen(stockListProvider, (prev, next) {
      if (!next.hasValue || !_loadingMore) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_loadingMore) return;
        setState(() => _loadingMore = false);
      });
    });

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !shellStock,
        leading: shellStock
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => context.popOrGo('/catalog'),
              ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Stock', style: HexaDsType.h2(context)),
            const SizedBox(width: 8),
            FadeTransition(
              opacity: _livePulse,
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
                    'LIVE',
                    style: HexaDsType.label(10).copyWith(
                      color: const Color(0xFF2E7D32),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            if (listTotal > 0) ...[
              const SizedBox(width: 8),
              Badge(
                label: Text('$listTotal'),
                backgroundColor: HexaColors.brandPrimary,
              ),
            ],
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Filter',
            icon: const Icon(Icons.tune_rounded),
            onPressed: () => showStockFilterBottomSheet(
              context: context,
              ref: ref,
              initial: q,
              subcategoryCtrl: _subcatCtrl,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Center(
              child: StockHealthScoreBadge(health: stockHealth, compact: true),
            ),
          ),
          IconButton(
            tooltip: 'Reorder list',
            onPressed: () => context.push('/stock/reorder'),
            icon: Badge(
              isLabelVisible: reorderN > 0,
              label: Text('$reorderN'),
              child: const Icon(Icons.playlist_add_check_rounded),
            ),
          ),
          IconButton(
            tooltip: 'Scan barcode',
            icon: const Icon(Icons.qr_code_scanner_rounded),
            onPressed: () => context.push('/barcode/scan'),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TabBar(
            controller: _mainTabs,
            isScrollable: true,
            tabs: [
              Tab(text: 'All ($listTotal)'),
              Tab(text: 'Low ($lowTabCount)'),
              Tab(text: 'Today ($todayCount)'),
              const Tab(text: 'Category'),
              const Tab(text: 'Scan'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _mainTabs,
              children: [
                _buildAllTab(
                  theme: theme,
                  cs: cs,
                  q: q,
                  listAsync: listAsync,
                  catsAsync: catsAsync,
                  suppliersAsync: suppliersAsync,
                  listTotal: listTotal,
                  lowN: lowN,
                  critN: critN,
                ),
                _buildLowTab(lowN: lowN, critN: critN),
                _buildTodayTab(todayDay: todayDay, todayAudits: todayAudits),
                _buildCategoryTab(listAsync: listAsync, theme: theme, cs: cs),
                _buildScanTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAllTab({
    required ThemeData theme,
    required ColorScheme cs,
    required StockListQuery q,
    required AsyncValue<Map<String, dynamic>> listAsync,
    required AsyncValue<List<Map<String, dynamic>>> catsAsync,
    required AsyncValue<List<Map<String, dynamic>>> suppliersAsync,
    required int listTotal,
    required int lowN,
    required int critN,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Search name or item code',
              prefixIcon: const Icon(Icons.search_rounded),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              isDense: true,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                FilterChip(
                  label: Text('All $listTotal'),
                  selected: q.status == 'all' && q.sort != 'recent',
                  onSelected: (_) {
                    ref.read(stockListQueryProvider.notifier).state =
                        ref.read(stockListQueryProvider).copyWith(
                              status: 'all',
                              sort: 'name',
                              page: 1,
                            );
                  },
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: Text('Low $lowN'),
                  selected: q.status == 'low',
                  onSelected: (_) {
                    ref.read(stockListQueryProvider.notifier).state =
                        ref.read(stockListQueryProvider).copyWith(
                              status: 'low',
                              sort: 'name',
                              page: 1,
                            );
                  },
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: Text('Critical $critN'),
                  selected: q.status == 'critical',
                  onSelected: (_) {
                    ref.read(stockListQueryProvider.notifier).state =
                        ref.read(stockListQueryProvider).copyWith(
                              status: 'critical',
                              sort: 'name',
                              page: 1,
                            );
                  },
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Out 0'),
                  selected: q.status == 'out',
                  onSelected: (_) {
                    ref.read(stockListQueryProvider.notifier).state =
                        ref.read(stockListQueryProvider).copyWith(
                              status: 'out',
                              sort: 'name',
                              page: 1,
                            );
                  },
                ),
                const SizedBox(width: 8),
                FilterChip(
                  avatar: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Recent'),
                  selected: q.sort == 'recent',
                  onSelected: (_) {
                    ref.read(stockListQueryProvider.notifier).state =
                        ref.read(stockListQueryProvider).copyWith(
                              status: 'all',
                              sort: 'recent',
                              page: 1,
                            );
                  },
                ),
              ],
            ),
          ),
        ),
        if (stockHasActiveFilters(q))
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Container(
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: HexaColors.brandPrimary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: HexaColors.brandPrimary.withValues(alpha: 0.18),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      stockActiveFilterSummary(q),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: HexaColors.brandPrimary,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      ref.read(stockListQueryProvider.notifier).state =
                          const StockListQuery();
                      _subcatCtrl.clear();
                    },
                    icon: const Icon(Icons.close_rounded, size: 16),
                    label: const Text('Clear'),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(44, 30),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (q.status == 'low' || q.status == 'critical')
          Material(
            color: const Color(0xFFFFF3E0),
            child: InkWell(
              onTap: () => context.push('/stock/reorder'),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: Color(0xFFE65100)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$lowN low · $critN critical — tap for reorder list',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 4),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(stockListProvider);
              ref.invalidate(stockAlertCountsProvider);
              await ref.read(stockListProvider.future);
              if (mounted) {
                setState(() => _lastRefreshedAt = DateTime.now());
              }
            },
            child: listAsync.when(
              loading: () => const ListSkeleton(),
              error: (_, __) => FriendlyLoadError(
                message: 'Could not load stock',
                onRetry: () => ref.invalidate(stockListProvider),
              ),
              data: (data) {
                var items = (data['items'] as List?) ?? const [];
                if (q.supplier.isNotEmpty) {
                  final sup = q.supplier.toLowerCase();
                  items = [
                    for (final e in items)
                      if (e is Map &&
                          (e['supplier_name']?.toString().toLowerCase() ??
                                  '') ==
                              sup)
                        e,
                  ];
                }
                final total = (data['total'] as num?)?.toInt() ?? 0;
                final page = (data['page'] as num?)?.toInt() ?? 1;
                final perPage =
                    (data['per_page'] as num?)?.toInt() ?? q.perPage;
                final pages = (total / perPage).ceil().clamp(1, 99999);

                if (items.isEmpty) {
                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 120),
                      Center(
                        child: Text(
                          'No items match these filters.',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  );
                }

                return Column(
                  children: [
                    OperationalLiveBanner(
                      pulse: _livePulse,
                      statsLine: _liveStatsLine(
                        q.supplier.isEmpty ? total : items.length,
                        lowN,
                      ),
                    ),
                    const _StockTableHeader(),
                    Expanded(
                      child: ListView.builder(
                        controller: _scroll,
                        padding: EdgeInsets.zero,
                        itemCount: items.length + (_loadingMore ? 1 : 0),
                        itemBuilder: (ctx, i) {
                          if (_loadingMore && i == items.length) {
                            return const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            );
                          }
                          final row = Map<String, dynamic>.from(
                            items[i] as Map,
                          );
                          final id = row['id']?.toString() ?? '';
                          final name = row['name']?.toString() ?? '';
                          final updatedBy =
                              row['last_stock_updated_by']?.toString();
                          final updatedAgo = _timeAgo(
                            row['last_stock_updated_at'],
                          );

                          Widget line = _StockTableRow(
                            row: row,
                            fmtQty: _fmtQty,
                            statusColor: (st) => _statusColor(st, cs),
                            stockQtyColor: (st, cur) =>
                                _stockQtyColor(st, cur, cs),
                            updatedSubtitle:
                                updatedBy != null && updatedBy.isNotEmpty
                                    ? 'by $updatedBy · $updatedAgo'
                                    : null,
                            updatedToday:
                                _updatedToday(row['last_stock_updated_at']),
                            onTap: () {
                              if (id.isNotEmpty) {
                                context.push('/stock/intelligence/$id');
                              }
                            },
                            onLongPress: () {
                              if (id.isEmpty) return;
                              showModalBottomSheet<void>(
                                context: context,
                                showDragHandle: true,
                                builder: (ctx) => SafeArea(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      ListTile(
                                        leading: const Icon(
                                            Icons.inventory_2_outlined),
                                        title: const Text('Update stock'),
                                        onTap: () {
                                          Navigator.pop(ctx);
                                          showUpdateStockSheet(
                                            context: context,
                                            ref: ref,
                                            itemId: id,
                                            itemName: name,
                                            stockRow: row,
                                          );
                                        },
                                      ),
                                      ListTile(
                                        leading: const Icon(
                                            Icons.insights_outlined),
                                        title: const Text('Stock intelligence'),
                                        onTap: () {
                                          Navigator.pop(ctx);
                                          context.push(
                                              '/stock/intelligence/$id');
                                        },
                                      ),
                                      ListTile(
                                        leading:
                                            const Icon(Icons.history_rounded),
                                        title: const Text('Stock history'),
                                        onTap: () {
                                          Navigator.pop(ctx);
                                          context.push(
                                            '/stock/$id/history?name=${Uri.encodeComponent(name)}',
                                          );
                                        },
                                      ),
                                      ListTile(
                                        leading:
                                            const Icon(Icons.print_rounded),
                                        title: const Text('Print barcode'),
                                        onTap: () {
                                          Navigator.pop(ctx);
                                          context.push(
                                            '/barcode/print/${Uri.encodeComponent(id)}',
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );

                          if (id.isNotEmpty) {
                            line = Dismissible(
                              key: ValueKey('stock_swipe_$id'),
                              direction: DismissDirection.startToEnd,
                              confirmDismiss: (_) async {
                                await showUpdateStockSheet(
                                  context: context,
                                  ref: ref,
                                  itemId: id,
                                  itemName: name,
                                  stockRow: row,
                                );
                                return false;
                              },
                              background: Container(
                                color: HexaColors.brandPrimary
                                    .withValues(alpha: 0.15),
                                alignment: Alignment.centerLeft,
                                padding: const EdgeInsets.only(left: 20),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.inventory_2_outlined,
                                      color: HexaColors.brandPrimary,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Update',
                                      style: TextStyle(
                                        color: HexaColors.brandPrimary,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              child: line,
                            );
                          }
                          return line;
                        },
                      ),
                    ),
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Row(
                          children: [
                            Text(
                              'Page $page / $pages · $total items',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              tooltip: 'Previous page',
                              onPressed: page <= 1
                                  ? null
                                  : () {
                                      ref
                                          .read(stockListQueryProvider.notifier)
                                          .state = q.copyWith(page: page - 1);
                                    },
                              icon: const Icon(Icons.chevron_left),
                            ),
                            IconButton(
                              tooltip: 'Next page',
                              onPressed: page >= pages
                                  ? null
                                  : () {
                                      ref
                                          .read(stockListQueryProvider.notifier)
                                          .state = q.copyWith(page: page + 1);
                                    },
                              icon: const Icon(Icons.chevron_right),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLowTab({required int lowN, required int critN}) {
    final lowAsync = ref.watch(stockPageLowListProvider);
    final session = ref.watch(sessionProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: const Color(0xFFFFF3E0),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Text(
              '$lowN low · $critN critical — tap Order to add to reorder list',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(stockPageLowListProvider);
              await ref.read(stockPageLowListProvider.future);
            },
            child: lowAsync.when(
              loading: () => const ListSkeleton(),
              error: (_, __) => FriendlyLoadError(
                message: 'Could not load low stock',
                onRetry: () => ref.invalidate(stockPageLowListProvider),
              ),
              data: (rows) {
                if (rows.isEmpty) {
                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 120),
                      Center(child: Text('No low-stock items')),
                    ],
                  );
                }
                return ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: rows.length,
                  itemBuilder: (ctx, i) {
                    final row = rows[i];
                    final id = row['id']?.toString() ?? '';
                    final name = row['name']?.toString() ?? '—';
                    final cur = _fmtQty(row['current_stock']);
                    final ro = _fmtQty(row['reorder_level']);
                    final unit = row['unit']?.toString() ?? '';
                    return ListTile(
                      title: Text(name,
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text(
                        'Stock $cur · Reorder $ro${unit.isNotEmpty ? ' $unit' : ''}',
                      ),
                      trailing: OutlinedButton(
                        onPressed: session == null || id.isEmpty
                            ? null
                            : () async {
                                await ref
                                    .read(hexaApiProvider)
                                    .addItemToReorderList(
                                      businessId: session.primaryBusiness.id,
                                      itemId: id,
                                    );
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content:
                                          Text('Added $name to reorder list')),
                                );
                              },
                        child: const Text('Order'),
                      ),
                      onTap: id.isNotEmpty
                          ? () => context.push('/catalog/item/$id')
                          : null,
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTodayTab({
    required DateTime todayDay,
    required AsyncValue<List<Map<String, dynamic>>> todayAudits,
  }) {
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(stockAuditDayProvider(todayDay));
        await ref.read(stockAuditDayProvider(todayDay).future);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  "Today's stock movement",
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
              TextButton(
                onPressed: () => context.push('/stock/today-feed'),
                child: const Text('Full page'),
              ),
            ],
          ),
          todayAudits.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            error: (_, __) => const Text('Could not load today\'s activity'),
            data: (rows) => StockTodayFeed(rows: rows),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryTab({
    required AsyncValue<Map<String, dynamic>> listAsync,
    required ThemeData theme,
    required ColorScheme cs,
  }) {
    return listAsync.when(
      loading: () => const ListSkeleton(),
      error: (_, __) => FriendlyLoadError(
        message: 'Could not load stock',
        onRetry: () => ref.invalidate(stockListProvider),
      ),
      data: (data) {
        final items = (data['items'] as List?) ?? const [];
        final byCat = <String, List<Map<String, dynamic>>>{};
        for (final raw in items) {
          if (raw is! Map) continue;
          final row = Map<String, dynamic>.from(raw);
          final cat = (row['category_name'] ?? 'Uncategorized').toString();
          byCat.putIfAbsent(cat, () => []).add(row);
        }
        final keys = byCat.keys.toList()..sort();
        if (keys.isEmpty) {
          return Center(
            child: Text(
              'No items to group',
              style: theme.textTheme.bodyLarge
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: keys.length,
          itemBuilder: (ctx, i) {
            final cat = keys[i];
            final rows = byCat[cat]!;
            final withReorder = rows
                .where((r) => ((r['reorder_level'] as num?)?.toDouble() ?? 0) > 0)
                .length;
            final pct = rows.isEmpty ? 0.0 : withReorder / rows.length;
            return ExpansionTile(
              title: Text('$cat (${rows.length})',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$withReorder/${rows.length} items have reorder threshold',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: pct,
                    minHeight: 4,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ],
              ),
              children: [
                for (final row in rows.take(20))
                  ListTile(
                    dense: true,
                    title: Text(row['name']?.toString() ?? '—'),
                    trailing: Text(_fmtQty(row['current_stock'])),
                    onTap: () {
                      final id = row['id']?.toString();
                      if (id != null && id.isNotEmpty) {
                        context.push('/catalog/item/$id');
                      }
                    },
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildScanTab() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.qr_code_scanner_rounded,
                size: 64,
                color: HexaColors.brandPrimary.withValues(alpha: 0.8)),
            const SizedBox(height: 16),
            const Text(
              'Scan barcode to look up or update stock',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => context.push('/barcode/scan'),
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: const Text('Open scanner'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StockTableHeader extends StatelessWidget {
  const _StockTableHeader();

  @override
  Widget build(BuildContext context) {
    final style = HexaDsType.labelCaps(context).copyWith(
      fontWeight: FontWeight.w900,
      color: Colors.white,
      letterSpacing: 0.2,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF37474F),
        border: Border(bottom: BorderSide(color: HexaColors.brandBorder)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          Expanded(flex: 5, child: Text('Item', style: style)),
          Expanded(
              flex: 2,
              child: Text('Stock', style: style, textAlign: TextAlign.end)),
          SizedBox(
            width: 56,
            child: Text('Status', style: style, textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }
}

class _StockTableRow extends StatelessWidget {
  const _StockTableRow({
    required this.row,
    required this.fmtQty,
    required this.statusColor,
    required this.stockQtyColor,
    this.updatedSubtitle,
    required this.updatedToday,
    required this.onTap,
    required this.onLongPress,
  });

  final Map<String, dynamic> row;
  final String Function(dynamic) fmtQty;
  final Color Function(String) statusColor;
  final Color Function(String st, dynamic curStock) stockQtyColor;
  final String? updatedSubtitle;
  final bool updatedToday;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final name = row['name']?.toString() ?? '—';
    final st = row['stock_status']?.toString() ?? 'healthy';
    final unit = row['unit']?.toString() ?? '';
    final curN = double.tryParse(row['current_stock']?.toString() ?? '') ?? 0;
    final kgPerBag = double.tryParse(
      row['default_kg_per_bag']?.toString() ?? '',
    );
    final secondary = stockDisplaySecondary(
      curN,
      unit,
      kgPerBag,
      double.tryParse(row['default_weight_per_tin']?.toString() ?? ''),
    );
    final purchased =
        double.tryParse(row['period_purchased_qty']?.toString() ?? '');
    final mismatch = row['needs_verification'] == true;
    final statusLabel = switch (st) {
      'out' => 'Out',
      'critical' => 'Crit',
      'low' => 'Low',
      _ => 'OK',
    };
    final sub = [
      if ((row['category_name'] ?? '').toString().isNotEmpty)
        row['category_name'],
      if ((row['subcategory_name'] ?? '').toString().isNotEmpty)
        row['subcategory_name'],
    ].join(' · ');

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: HexaColors.brandBorder)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 4, right: 6),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: statusColor(st),
                  ),
                ),
              ),
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (updatedToday) ...[
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFF0D9488),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                        ],
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: HexaDsType.listTitle(context).copyWith(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (sub.isNotEmpty)
                      Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: HexaDsType.listSubtitle(context).copyWith(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (updatedSubtitle != null && updatedSubtitle!.isNotEmpty)
                      Text(
                        updatedSubtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            HexaDsType.bodySm(context).copyWith(fontSize: 10),
                      ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      stockDisplayPrimary(curN, unit),
                      style: HexaDsType.bodyPrimary(context).copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: stockQtyColor(st, row['current_stock']),
                      ),
                    ),
                    if (secondary != null)
                      Text(
                        secondary,
                        style: HexaDsType.bodySm(context).copyWith(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: HexaColors.brandPrimary,
                        ),
                      ),
                    if (purchased != null)
                      Text(
                        'Bought ${stockDisplayPrimary(purchased, unit)}',
                        style: HexaDsType.bodySm(context).copyWith(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: HexaDsColors.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(
                width: mismatch ? 72 : 56,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (mismatch)
                      const Padding(
                        padding: EdgeInsets.only(right: 4),
                        child: Icon(
                          Icons.warning_amber_rounded,
                          size: 14,
                          color: Color(0xFFE65100),
                        ),
                      ),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: statusColor(st),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      statusLabel,
                      style: HexaDsType.bodySm(context).copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
