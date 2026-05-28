import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/services/stock_list_pdf.dart';
import '../../../core/json_coerce.dart';
import '../../../core/providers/home_dashboard_provider.dart';
import '../../../core/providers/stock_providers.dart';
import '../../../core/router/post_auth_route.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../../../core/widgets/list_skeleton.dart';
import '../stock_list_merge.dart';
import '../stock_period_utils.dart';
import 'package:go_router/go_router.dart';
import 'widgets/stock_pagination_bar.dart';
import 'widgets/stock_operational_top_bar.dart';
import 'widgets/stock_row_actions.dart';
import 'widgets/stock_warehouse_row.dart';
import 'widgets/stock_warehouse_table_header.dart';
import 'widgets/stock_status_chip_row.dart';
import 'widgets/stock_inline_search_bar.dart';
import 'widgets/stock_desktop_detail_pane.dart';
import 'widgets/operational_stock_filter_sheet.dart'
    show
        showOperationalStockFilter,
        stockActiveFilterSummary,
        kOperationalDesktopBreakpoint;
import 'widgets/stock_warehouse_filter_sheet.dart'
    show countWarehouseActiveFilters;

enum StockPageMode { auto, staff, owner }

class StockPage extends ConsumerStatefulWidget {
  const StockPage({super.key, this.mode = StockPageMode.auto});

  final StockPageMode mode;

  @override
  ConsumerState<StockPage> createState() => _StockPageState();
}

class _StockPageState extends ConsumerState<StockPage> {
  final _searchCtrl = TextEditingController();
  final _subcatCtrl = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;
  bool _loadingMore = false;
  bool _searchExpanded = false;
  String _instantSearch = '';
  Map<String, dynamic>? _mergedData;

  @override
  void initState() {
    super.initState();
    final initialQuery = ref.read(stockListQueryProvider);
    _searchCtrl.text = initialQuery.q.trim();
    _searchCtrl.addListener(_onSearchChanged);
    _searchCtrl.addListener(_onSearchUiChanged);
    _subcatCtrl.text = initialQuery.subcategory;
    _scroll.addListener(_onScrollLoadMore);

    if (ref.read(stockPagePeriodProvider) != HomePeriod.allTime) {
      applyStockPagePeriod(ref, HomePeriod.allTime);
    } else {
      applyStockPagePeriod(ref, ref.read(stockPagePeriodProvider));
    }

    final q = ref.read(stockListQueryProvider);
    if (q.perPage != 50 || q.sort != 'recent') {
      ref.read(stockListQueryProvider.notifier).state =
          q.copyWith(perPage: 50, page: 1, sort: 'recent');
    }
  }

  @override
  void dispose() {
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
    _debounce = Timer(const Duration(milliseconds: 300), () {
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
    var items = filterStockListClient(raw, op);
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
    await showStockRowActions(
      context: context,
      ref: ref,
      item: item,
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
      final result = await shareStockListPdf(bytes: bytes);
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

  Future<void> _openFilters() async {
    await showOperationalStockFilter(
      context: context,
      ref: ref,
      subcategoryCtrl: _subcatCtrl,
      isStaffMode: _isStaffMode,
    );
    _resetMerged();
    ref.invalidate(stockListProvider);
  }

  void _openHistory() {
    final route =
        _isStaffMode ? '/staff/stock/changes' : '/stock/changes';
    context.push(route);
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
    final listQ = ref.watch(stockListQueryProvider);
    final total = coerceToInt(data['total']);
    final maxPage = stockListMaxPage(total, listQ.perPage);
    final bottomPad = 24.0;
    final op = ref.watch(stockOperationalFiltersProvider);
    final filterCount = countWarehouseActiveFilters(listQ, op);

    final desktop =
        MediaQuery.sizeOf(context).width >= kOperationalDesktopBreakpoint;
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
      if (_searchExpanded)
        SliverToBoxAdapter(
          child: StockInlineSearchBar(
            controller: _searchCtrl,
            onClear: _clearSearch,
          ),
        ),
      const SliverToBoxAdapter(child: StockStatusChipRow()),
      if (items.isNotEmpty) ...[
        const SliverToBoxAdapter(child: StockWarehouseTableHeader()),
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
            showingCount: raw.length,
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
          child: Center(
            child: Text(
              filterCount > 0 || listQ.q.isNotEmpty
                  ? 'No items match filters'
                  : 'No stock items yet',
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
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

    ref.listen(stockListProvider, (prev, next) {
      if (next is! AsyncData<Map<String, dynamic>>) return;
      final q = ref.read(stockListQueryProvider);
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
      });
    });

    final listAsync = ref.watch(stockListProvider);
    final listQ = ref.watch(stockListQueryProvider);
    final op = ref.watch(stockOperationalFiltersProvider);
    final filterCount = countWarehouseActiveFilters(listQ, op);
    final data = _mergedData ?? listAsync.valueOrNull;
    final isReloading = listAsync.isLoading && data != null;

    Widget body;
    if (data == null && listAsync.isLoading) {
      body = const ListSkeleton(rowCount: 12);
    } else if (listAsync.hasError && data == null) {
      body = FriendlyLoadError(
        onRetry: () {
          _resetMerged();
          ref.invalidate(stockListProvider);
        },
      );
    } else if (data != null) {
      body = _buildListBody(data: data, isReloading: isReloading);
    } else {
      body = const ListSkeleton(rowCount: 12);
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F3EE),
      appBar: StockOperationalTopBar(
        isStaffMode: _isStaffMode,
        filterCount: filterCount,
        searchExpanded: _searchExpanded,
        isReloading: isReloading,
        onToggleSearch: () =>
            setState(() => _searchExpanded = !_searchExpanded),
        onOpenFilters: _openFilters,
        onOpenHistory: _openHistory,
        onExportPdf: _isStaffMode ? null : _exportStockPdf,
      ),
      body: body,
    );
  }
}
