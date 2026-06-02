import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/auth/auth_failure_policy.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/models/session.dart';
import '../../../core/providers/stock_list_exceptions.dart';
import '../../../core/services/stock_list_pdf.dart';
import '../../../core/services/pdf_actions.dart';
import '../../../core/json_coerce.dart';
import '../../../core/providers/business_write_event.dart';
import '../../../core/providers/home_dashboard_provider.dart';
import '../../../core/providers/stock_providers.dart';
import '../../../core/design_system/hexa_responsive.dart';
import '../../../core/router/post_auth_route.dart';
import '../../../core/router/shell_navigation.dart';
import '../../../features/shell/shell_branch_provider.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../../../core/widgets/list_skeleton.dart';
import '../../../shared/widgets/hexa_empty_state.dart';
import '../stock_list_merge.dart';
import '../stock_period_utils.dart';
import 'widgets/stock_pagination_bar.dart';
import 'widgets/stock_operational_top_bar.dart';
import 'widgets/stock_changes_tab.dart';
import 'widgets/stock_row_actions.dart';
import 'widgets/stock_warehouse_row.dart';
import 'widgets/stock_warehouse_table_header.dart';
import 'widgets/stock_inline_search_bar.dart';
import 'widgets/stock_desktop_detail_pane.dart';
import 'widgets/operational_stock_filter_sheet.dart'
    show showOperationalStockFilter, stockActiveFilterSummary;
import 'widgets/stock_warehouse_filter_sheet.dart'
    show countWarehouseActiveFilters;
import 'widgets/stock_delivery_filter_chips.dart';
import 'widgets/stock_status_quick_chips.dart';
import 'widgets/stock_row_metrics.dart';

enum StockPageMode { auto, staff, owner }

class StockPage extends ConsumerStatefulWidget {
  const StockPage({
    super.key,
    this.mode = StockPageMode.auto,
    this.initialTab,
  });

  final StockPageMode mode;
  /// `list` | `activity`
  final String? initialTab;

  @override
  ConsumerState<StockPage> createState() => _StockPageState();
}

class _StockPageState extends ConsumerState<StockPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _searchCtrl = TextEditingController();
  final _subcatCtrl = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;
  bool _loadingMore = false;
  bool _searchExpanded = false;
  String _instantSearch = '';
  Map<String, dynamic>? _mergedData;
  double? _pendingScrollOffset;

  static int _tabIndex(String? tab) {
    switch (tab) {
      case 'changes':
      case 'movement':
      case 'today':
      case 'activity':
        return 1;
      default:
        return 0;
    }
  }

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: 2,
      vsync: this,
      initialIndex: _tabIndex(widget.initialTab),
    );
    final initialQuery = ref.read(stockListQueryProvider);
    _searchCtrl.text = initialQuery.q.trim();
    _searchCtrl.addListener(_onSearchChanged);
    _searchCtrl.addListener(_onSearchUiChanged);
    _subcatCtrl.text = initialQuery.subcategory;
    _scroll.addListener(_onScrollLoadMore);

    applyStockPagePeriod(ref, ref.read(stockPagePeriodProvider));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final saved = ref.read(stockListScrollOffsetProvider);
      if (saved > 0) {
        final max = _scroll.position.maxScrollExtent;
        _scroll.jumpTo(saved.clamp(0.0, max));
      }
    });

    final q = ref.read(stockListQueryProvider);
    if (q.perPage != 50 || q.sort != 'recent') {
      ref.read(stockListQueryProvider.notifier).state =
          q.copyWith(perPage: 50, page: 1, sort: 'recent');
    }
  }

  @override
  void dispose() {
    if (_scroll.hasClients) {
      ref.read(stockListScrollOffsetProvider.notifier).state = _scroll.offset;
    }
    _tabs.dispose();
    _debounce?.cancel();
    _searchCtrl.dispose();
    _subcatCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  bool get _isStaffMode {
    if (widget.mode == StockPageMode.staff) return true;
    if (widget.mode == StockPageMode.owner) return false;
    final session = ref.read(sessionProvider);
    return session != null && sessionIsStaff(session);
  }

  void _resetMerged() => _mergedData = null;

  void _persistScrollOffset() {
    if (_scroll.hasClients) {
      ref.read(stockListScrollOffsetProvider.notifier).state = _scroll.offset;
    }
  }

  void _restoreScrollOffset() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final saved = ref.read(stockListScrollOffsetProvider);
      if (saved > 0) {
        final max = _scroll.position.maxScrollExtent;
        _scroll.jumpTo(saved.clamp(0.0, max));
      }
    });
  }

  void _clearSearch() {
    _searchCtrl.clear();
    ref.read(stockListQueryProvider.notifier).state =
        ref.read(stockListQueryProvider).copyWith(q: '', page: 1);
    _resetMerged();
    ref.invalidate(stockListProvider);
  }

  void _onSearchUiChanged() {
    final raw = _searchCtrl.text.trim();
    if (raw != _instantSearch && mounted) {
      setState(() => _instantSearch = raw);
    } else if (_searchExpanded && mounted) {
      setState(() {});
    }
  }

  void _onSearchChanged() {
    final raw = _searchCtrl.text.trim();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      final q = ref.read(stockListQueryProvider);
      if (q.q == raw) return;
      _resetMerged();
      ref.read(stockListQueryProvider.notifier).state =
          q.copyWith(q: raw, page: 1);
    });
  }

  void _onScrollLoadMore() {
    if (!_scroll.hasClients || _loadingMore) return;
    if (_scroll.position.extentAfter > 240) return;
    _goNextPage();
  }

  void _goNextPage() {
    final q = ref.read(stockListQueryProvider);
    final total = coerceToInt(_mergedData?['total']);
    final maxPage = stockListMaxPage(total, q.perPage);
    if (q.page >= maxPage) return;
    setState(() => _loadingMore = true);
    ref.read(stockListQueryProvider.notifier).state =
        q.copyWith(page: q.page + 1);
  }

  void _goPrevPage() {
    final q = ref.read(stockListQueryProvider);
    if (q.page <= 1) return;
    final newPage = q.page - 1;
    final keep = newPage * q.perPage;
    setState(() {
      if (_mergedData != null) {
        final items = (_mergedData!['items'] as List?) ?? [];
        if (items.length > keep) {
          _mergedData = {
            ..._mergedData!,
            'items': items.take(keep).toList(),
            'page': newPage,
          };
        }
      }
    });
    ref.read(stockListQueryProvider.notifier).state = q.copyWith(page: newPage);
  }

  List<Map<String, dynamic>> _prepareItems(List<Map<String, dynamic>> raw) {
    final op = ref.read(stockOperationalFiltersProvider);
    final q = ref.read(stockListQueryProvider);
    final deliveryFilter = ref.read(stockDeliveryFilterProvider);
    var items = filterStockListClient(raw, op);
    if (deliveryFilter != StockDeliveryFilter.all) {
      items = items
          .where(
            (it) => StockRowMetrics.matchesDeliveryFilter(it, deliveryFilter),
          )
          .toList();
    }
    final search = _instantSearch.isNotEmpty
        ? _instantSearch.toLowerCase()
        : q.q.trim().toLowerCase();
    sortStockListOperational(
      items,
      searchQuery: search,
      sort: q.sort,
    );
    return items;
  }

  Future<void> _openRowActions(Map<String, dynamic> item) async {
    _persistScrollOffset();
    await showStockRowActions(
      context: context,
      ref: ref,
      item: item,
      onBeforeNavigate: _persistScrollOffset,
      onAfterNavigateReturn: _restoreScrollOffset,
    );
  }

  Future<void> _exportStockPdf() async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    final data = _mergedData ?? ref.read(stockListProvider).valueOrNull;
    if (data == null) return;
    final raw = [
      for (final e in (data['items'] as List? ?? []))
        if (e is Map) Map<String, dynamic>.from(e),
    ];
    final items = _prepareItems(raw);
    if (items.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No stock rows to export.')),
      );
      return;
    }
    final listQ = ref.read(stockListQueryProvider);
    final op = ref.read(stockOperationalFiltersProvider);
    final summary = stockActiveFilterSummary(listQ, op);
    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Preparing stock PDF…')),
        );
      }
      final bytes = await buildStockListPdf(
        businessName: session.primaryBusiness.effectiveDisplayTitle,
        rows: items.take(500).toList(),
        filterSummary: summary.isEmpty ? null : summary,
      );
      final result = kIsWeb
          ? await savePdfBytes(
              buildBytes: () async => bytes,
              filename: 'harisree_stock_statement.pdf',
              subject: 'Harisree stock statement',
              source: 'stock_list_pdf',
            )
          : await shareStockListPdf(
              bytes: bytes,
              filename: 'harisree_stock_statement.pdf',
            );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.message)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not create stock PDF. Try fewer filters.'),
          ),
        );
      }
    }
  }

  Future<void> _exportStockExcel() async {
    final data = _mergedData ?? ref.read(stockListProvider).valueOrNull;
    if (data == null) return;
    final raw = [
      for (final e in (data['items'] as List? ?? []))
        if (e is Map) Map<String, dynamic>.from(e),
    ];
    final rows = _prepareItems(raw);
    if (rows.isEmpty) return;
    String esc(String s) => '"${s.replaceAll('"', '""')}"';
    final b = StringBuffer();
    b.writeln('Item,Category,Subcategory,Unit,Current Stock,Opening Stock,Purchased,Reorder Level,Last Updated');
    for (final r in rows) {
      b.writeln([
        esc(r['name']?.toString() ?? ''),
        esc(r['category_name']?.toString() ?? ''),
        esc(r['subcategory_name']?.toString() ?? ''),
        esc((r['stock_unit'] ?? r['unit'])?.toString() ?? ''),
        coerceToDouble(r['current_stock']).toString(),
        coerceToDouble(r['opening_stock_qty']).toString(),
        coerceToDouble(r['period_purchased_qty']).toString(),
        coerceToDouble(r['reorder_level']).toString(),
        esc(r['last_stock_updated_at']?.toString() ?? ''),
      ].join(','));
    }
    final bytes = utf8.encode(b.toString());
    await Share.shareXFiles(
      [
        XFile.fromData(
          bytes,
          mimeType: 'text/csv',
          name: 'harisree_stock_export.csv',
        ),
      ],
      text: 'Stock export',
    );
  }

  Future<void> _openFilters() async {
    await showOperationalStockFilter(
      context: context,
      ref: ref,
      subcategoryCtrl: _subcatCtrl,
      isStaffMode: _isStaffMode,
    );
    // Filter sheet updates query/op providers — list refetches without clearing UI.
  }

  void _openMovementTab() {
    if (_tabs.index != 1) {
      _tabs.animateTo(1);
    }
  }

  void _showPeriodPicker() {
    final current = ref.read(stockPagePeriodProvider);
    showHexaBottomSheet<void>(
      context: context,
      compact: true,
      child: _StockPeriodSheet(
        current: current,
        onPick: (p) {
          Navigator.pop(context);
          applyStockPagePeriod(ref, p);
          _resetMerged();
          ref.invalidate(stockListProvider);
        },
      ),
    );
  }

  Map<String, dynamic>? _selectedItem(List<Map<String, dynamic>> items) {
    final id = ref.read(stockSelectedItemIdProvider);
    if (id == null || id.isEmpty) {
      return items.isNotEmpty ? items.first : null;
    }
    for (final row in items) {
      if (row['id']?.toString() == id) return row;
    }
    return items.isNotEmpty ? items.first : null;
  }

  Widget _buildListBody({
    required Map<String, dynamic> data,
    required bool isReloading,
  }) {
    final raw = [
      for (final e in (data['items'] as List? ?? []))
        if (e is Map) Map<String, dynamic>.from(e),
    ];
    final items = _prepareItems(raw);
    final deliveryCounts = StockRowMetrics.countDeliveryIndicators(raw);
    final deliveryFilter = ref.watch(stockDeliveryFilterProvider);
    final listQ = ref.watch(stockListQueryProvider);
    final chipCounts =
        ref.watch(stockStatusCountsProvider).valueOrNull ?? const {};
    final chipAll = chipCounts['all'] ?? 0;
    final total = coerceToInt(data['total']);
    final maxPage = stockListMaxPage(total, listQ.perPage);
    final bottomPad = 24.0;
    final op = ref.watch(stockOperationalFiltersProvider);
    final filterCount = countWarehouseActiveFilters(listQ, op);

    final desktop =
        MediaQuery.sizeOf(context).width >= kDesktopMin;
    final selected = desktop ? _selectedItem(items) : null;
    if (desktop && items.isNotEmpty) {
      final sid = selected?['id']?.toString();
      if (sid != null &&
          ref.read(stockSelectedItemIdProvider) != sid) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ref.read(stockSelectedItemIdProvider.notifier).state = sid;
          }
        });
      }
    }

    final listSlivers = <Widget>[
      SliverToBoxAdapter(
        child: StockStatusQuickChips(
          selectedStatus: listQ.status,
          onSelected: (status) {
            ref.read(stockListQueryProvider.notifier).state =
                listQ.copyWith(status: status, page: 1);
            _resetMerged();
            ref.invalidate(stockListProvider);
          },
        ),
      ),
      if (_searchExpanded)
        SliverToBoxAdapter(
          child: StockInlineSearchBar(
            controller: _searchCtrl,
            onClear: _clearSearch,
          ),
        ),
      if (deliveryCounts.pending > 0 || deliveryCounts.delivered > 0)
        SliverToBoxAdapter(
          child: StockDeliveryFilterChips(
            selected: deliveryFilter,
            pendingCount: deliveryCounts.pending,
            deliveredCount: deliveryCounts.delivered,
            onSelected: (f) =>
                ref.read(stockDeliveryFilterProvider.notifier).state = f,
          ),
        ),
      if (items.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: const StockWarehouseTableHeader(),
        ),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (ctx, i) {
              final row = items[i];
              final id = row['id']?.toString() ?? '';
              final isSelected =
                  desktop && id.isNotEmpty && id == selected?['id']?.toString();
              return RepaintBoundary(
                child: StockWarehouseRow(
                  item: row,
                  ref: ref,
                  isStaffMode: _isStaffMode,
                  isFirstRow: i == 0,
                  isSelected: isSelected,
                  onTap: () => unawaited(_openRowActions(row)),
                  onSelect: desktop && id.isNotEmpty
                      ? () => ref
                          .read(stockSelectedItemIdProvider.notifier)
                          .state = id
                      : null,
                ),
              );
            },
            childCount: items.length,
          ),
        ),
        SliverToBoxAdapter(
          child: StockPaginationBar(
            showingCount: items.length,
            totalCount: total,
            currentPage: listQ.page,
            maxPage: maxPage,
            loading: _loadingMore,
            onPrev: listQ.page > 1 ? _goPrevPage : null,
            onNext: listQ.page < maxPage ? _goNextPage : null,
          ),
        ),
      ],
      if (items.isEmpty)
        SliverFillRemaining(
          hasScrollBody: false,
          child: HexaEmptyState(
            icon: Icons.inventory_2_outlined,
            title: chipAll > 0 &&
                    items.isEmpty &&
                    filterCount == 0 &&
                    listQ.q.isEmpty &&
                    deliveryFilter == StockDeliveryFilter.all
                ? 'Stock list did not load'
                : filterCount > 0 ||
                        listQ.q.isNotEmpty ||
                        deliveryFilter != StockDeliveryFilter.all
                    ? 'No items match filters'
                    : 'No stock items yet',
            subtitle: chipAll > 0 &&
                    items.isEmpty &&
                    filterCount == 0 &&
                    listQ.q.isEmpty
                ? 'Counts show $chipAll items but the list request failed. Tap Refresh or sign in again.'
                : filterCount > 0 ||
                        listQ.q.isNotEmpty ||
                        deliveryFilter != StockDeliveryFilter.all
                    ? 'Open Filters and tap Clear advanced, or change the status chips above.'
                    : 'Add catalog items to start tracking warehouse stock.',
            primaryActionLabel: chipAll > 0 &&
                    items.isEmpty &&
                    filterCount == 0
                ? 'Retry load'
                : filterCount > 0
                    ? 'Clear filters'
                    : 'Refresh',
            onPrimaryAction: chipAll > 0 &&
                    items.isEmpty &&
                    filterCount == 0
                ? () {
                    ref.read(authApiGateProvider.notifier).reset();
                    _resetMerged();
                    ref.invalidate(stockListProvider);
                    ref.invalidate(stockStatusCountsProvider);
                  }
                : filterCount > 0
                ? () {
                    ref.read(stockListQueryProvider.notifier).state =
                        listQ.copyWith(
                      status: 'all',
                      subcategory: '',
                      supplier: '',
                      q: '',
                      page: 1,
                    );
                    ref.read(stockOperationalFiltersProvider.notifier).state =
                        const StockOperationalFilters();
                    ref.read(stockDeliveryFilterProvider.notifier).state =
                        StockDeliveryFilter.all;
                    _searchCtrl.clear();
                    _resetMerged();
                    ref.invalidate(stockListProvider);
                  }
                : () => ref.invalidate(stockListProvider),
          ),
        ),
      SliverToBoxAdapter(child: SizedBox(height: bottomPad)),
    ];

    final scroll = RefreshIndicator(
      onRefresh: () async {
        _resetMerged();
        ref.invalidate(stockListProvider);
        await ref.read(stockListProvider.future);
      },
      child: CustomScrollView(
        key: const PageStorageKey<String>('stock_operational_list'),
        controller: _scroll,
        slivers: listSlivers,
      ),
    );

    if (!desktop) return scroll;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 5, child: scroll),
        const VerticalDivider(width: 1, thickness: 1),
        Expanded(
          flex: 4,
          child: StockDesktopDetailPane(item: selected),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(businessWriteEventProvider, (prev, next) {
      if (prev == null || prev.revision == next.revision) return;
      // Background refresh; keep scroll + merged rows until new data arrives.
      ref.invalidate(stockListProvider);
      ref.invalidate(stockChangesFeedProvider);
    });
    // Warehouse realtime fan-out lives in [ShellRealtimeListener] — avoid double invalidation here.

    ref.listen(stockListQueryProvider, (prev, next) {
      if (prev == null) return;
      if (prev.page == 1 &&
          next.page == 1 &&
          (prev.q != next.q ||
              prev.subcategory != next.subcategory ||
              prev.status != next.status ||
              prev.periodStart != next.periodStart ||
              prev.periodEnd != next.periodEnd)) {
        _resetMerged();
      }
    });

    ref.listen(stockOperationalFiltersProvider, (prev, next) {
      if (prev == null || prev == next) return;
      _resetMerged();
    });

    ref.listen<Session?>(sessionProvider, (prev, next) {
      if (prev == null && next != null) {
        _resetMerged();
        ref.invalidate(stockListProvider);
        ref.invalidate(stockStatusCountsProvider);
      }
    });

    ref.listen(stockListProvider, (prev, next) {
      if (next.isLoading &&
          prev?.hasValue == true &&
          ref.read(stockListQueryProvider).page == 1 &&
          _scroll.hasClients) {
        _pendingScrollOffset = _scroll.offset;
      }
      if (next is! AsyncData<Map<String, dynamic>>) return;
      final q = ref.read(stockListQueryProvider);
      final restoreOffset = _pendingScrollOffset;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _loadingMore = false;
          _mergedData = mergeStockListPage(
            previous: q.page > 1 ? _mergedData : null,
            incoming: next.value,
            page: q.page,
          );
        });
        if (restoreOffset != null && _scroll.hasClients) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !_scroll.hasClients) return;
            final max = _scroll.position.maxScrollExtent;
            _scroll.jumpTo(restoreOffset.clamp(0.0, max));
            _pendingScrollOffset = null;
          });
        }
      });
    });

    final listAsync = ref.watch(stockListProvider);
    final listQ = ref.watch(stockListQueryProvider);
    final op = ref.watch(stockOperationalFiltersProvider);
    final filterCount = countWarehouseActiveFilters(listQ, op);
    final data = _mergedData ?? listAsync.valueOrNull;
    final isReloading = listAsync.isLoading && data != null;
    final showDebounceProgress = _debounce?.isActive ?? false;

    final authExpired = ref.watch(authSessionExpiredProvider);
    final authCircuit = ref.watch(auth401CircuitOpenProvider);
    final sessionForAuth = ref.watch(sessionProvider);
    final authBlocked = authExpired ||
        authCircuit ||
        (sessionForAuth == null && !listAsync.isLoading);

    Widget body;
    if (authBlocked) {
      body = FriendlyLoadError(
        message: 'Sign in to load stock',
        subtitle:
            'Your session expired or could not be verified. Sign in again to see warehouse items.',
        onRetry: () async {
          ref.read(authApiGateProvider.notifier).reset();
          await ref.read(sessionProvider.notifier).logout();
          if (mounted) context.go('/login');
        },
      );
    } else if (data == null && listAsync.isLoading) {
      body = const ListSkeleton(rowCount: 12);
    } else if (listAsync.hasError && data == null) {
      final err = listAsync.error;
      final blocked = err is StockListFetchBlockedException
          ? err.reason
          : null;
      final isAuth = isStockListAuthFailure(err) ||
          (err is DioException && err.response?.statusCode == 401);
      body = FriendlyLoadError(
        message: isAuth ? 'Sign in to load stock' : 'Unable to load stock',
        subtitle: isAuth
            ? 'Warehouse list needs a valid session. Sign in and try again.'
            : blocked == 'tab_not_visible'
                ? 'Stock list paused while another tab is open. Switch back to Stock and tap Retry.'
                : null,
        onRetry: () {
          if (isAuth) {
            ref.read(authApiGateProvider.notifier).reset();
          }
          _resetMerged();
          ref.invalidate(stockListProvider);
          ref.invalidate(stockStatusCountsProvider);
        },
      );
    } else if (data != null) {
      body = _buildListBody(data: data, isReloading: isReloading);
    } else {
      body = const ListSkeleton(rowCount: 12);
    }

    final listTab = Column(
      children: [
        if (showDebounceProgress)
          const LinearProgressIndicator(minHeight: 2),
        Expanded(child: body),
      ],
    );

    final session = ref.watch(sessionProvider);
    final homePath =
        session != null ? authenticatedHomePath(session) : '/home';
    final returnBranch = ref.watch(shellReturnBranchProvider);

    final scaffold = Scaffold(
      backgroundColor: const Color(0xFFF5F3EE),
      appBar: StockOperationalTopBar(
        isStaffMode: _isStaffMode,
        filterCount: filterCount,
        searchExpanded: _searchExpanded,
        isReloading: isReloading,
        currentPeriod: ref.watch(stockPagePeriodProvider),
        onToggleSearch: () =>
            setState(() => _searchExpanded = !_searchExpanded),
        onOpenPeriod: _showPeriodPicker,
        onOpenFilters: _openFilters,
        onOpenMovement: _openMovementTab,
        onExportPdf: _isStaffMode ? null : _exportStockPdf,
        onExportExcel: _isStaffMode ? null : _exportStockExcel,
        tabController: _tabs,
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          listTab,
          StockChangesTab(isStaffMode: _isStaffMode),
        ],
      ),
    );

    if (_isStaffMode || returnBranch == null) return scaffold;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        popShellTabOrGoHome(context, ref, homePath: homePath);
      },
      child: scaffold,
    );
  }
}

class _StockPeriodSheet extends StatelessWidget {
  const _StockPeriodSheet({required this.current, required this.onPick});

  final HomePeriod current;
  final void Function(HomePeriod) onPick;

  @override
  Widget build(BuildContext context) {
    final options = [
      (HomePeriod.today, Icons.today_rounded, 'Today', 'Bought today'),
      (HomePeriod.week, Icons.view_week_rounded, 'This Week', 'Last 7 days'),
      (HomePeriod.month, Icons.calendar_month_rounded, 'This Month', 'Last 30 days'),
      (HomePeriod.year, Icons.calendar_view_month_rounded, 'This Year', 'From Jan 1'),
      (HomePeriod.allTime, Icons.all_inclusive_rounded, 'All Time', 'Full history'),
    ];
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              'Filter by period',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
          const Divider(height: 1),
          ...options.map(
            (o) => ListTile(
              leading: Icon(o.$2),
              title: Text(
                o.$3,
                style: TextStyle(
                  fontWeight: current == o.$1 ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
              subtitle: Text(o.$4),
              trailing: current == o.$1 ? const Icon(Icons.check_rounded) : null,
              onTap: () => onPick(o.$1),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
