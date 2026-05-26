import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/services/stock_list_pdf.dart';
import '../../../core/json_coerce.dart';
import '../../../core/providers/home_dashboard_provider.dart';
import '../../../core/providers/stock_providers.dart';
import '../../../core/design_system/hexa_responsive.dart';
import '../../../core/router/post_auth_route.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../../../core/widgets/list_skeleton.dart';
import '../stock_list_merge.dart';
import '../stock_period_utils.dart';
import '../../catalog/presentation/widgets/item_quick_view_sheet.dart';
import 'widgets/stock_list_column_header.dart';
import 'widgets/stock_pagination_bar.dart';
import 'widgets/stock_search_sliver.dart';
import 'widgets/stock_compact_top_bar.dart';
import 'widgets/stock_row_actions.dart';
import 'widgets/stock_table_row.dart';
import 'widgets/operational_stock_filter_sheet.dart'
    show stockActiveFilterSummary;
import 'widgets/stock_warehouse_filter_sheet.dart';

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

  void _openFilters() {
    unawaited(
      showStockWarehouseFilterSheet(
        context: context,
        ref: ref,
        subcategoryCtrl: _subcatCtrl,
        onApplied: () {
          _resetMerged();
          ref.invalidate(stockListProvider);
        },
      ),
    );
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
    final bottomPad = MediaQuery.paddingOf(context).bottom + 8;
    final op = ref.watch(stockOperationalFiltersProvider);
    final filterCount = countWarehouseActiveFilters(listQ, op);

    return RefreshIndicator(
      onRefresh: () async {
        _resetMerged();
        ref.invalidate(stockListProvider);
        await ref.read(stockListProvider.future);
      },
      child: CustomScrollView(
        controller: _scroll,
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: StockSearchSliverDelegate(
              expanded: _searchExpanded,
              searchController: _searchCtrl,
              onClearSearch: _clearSearch,
              onOpenFilters: _openFilters,
              filterCount: filterCount,
            ),
          ),
          SliverToBoxAdapter(
              child: _StockStatusFilterChips(isStaffMode: _isStaffMode)),
          if (items.isNotEmpty) ...[
            const SliverToBoxAdapter(child: StockListColumnHeader()),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) => RepaintBoundary(
                  child: StockTableRow(
                    item: items[i],
                    isStaffMode: _isStaffMode,
                    isFirstRow: i == 0,
                    onTap: () => unawaited(_openRowActions(items[i])),
                    onLongPress: () {
                      final id = items[i]['id']?.toString() ?? '';
                      final name = items[i]['name']?.toString() ?? 'Item';
                      if (id.isEmpty) return;
                      unawaited(
                        showItemQuickView(
                          context: context,
                          ref: ref,
                          itemId: id,
                          itemName: name,
                        ),
                      );
                    },
                  ),
                ),
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
        ],
      ),
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
      appBar: StockCompactTopBar(
        isStaffMode: _isStaffMode,
        filterCount: filterCount,
        searchExpanded: _searchExpanded,
        isReloading: isReloading,
        onToggleSearch: () =>
            setState(() => _searchExpanded = !_searchExpanded),
        onOpenFilters: _openFilters,
        onExportPdf: _exportStockPdf,
      ),
      body: body,
    );
  }
}

class _StockStatusFilterChips extends ConsumerWidget {
  const _StockStatusFilterChips({required this.isStaffMode});

  final bool isStaffMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countsAsync = ref.watch(stockStatusCountsProvider);
    final q = ref.watch(stockListQueryProvider);
    final op = ref.watch(stockOperationalFiltersProvider);

    return countsAsync.when(
      loading: () => const SizedBox(height: 40),
      error: (_, __) => const SizedBox.shrink(),
      data: (counts) {
        void applyStatus(String status) {
          ref.read(stockListQueryProvider.notifier).state = q.copyWith(
            status: status,
            page: 1,
          );
          ref.read(stockOperationalFiltersProvider.notifier).state =
              const StockOperationalFilters();
          ref.invalidate(stockListProvider);
        }

        void applyMissingCode() {
          ref.read(stockListQueryProvider.notifier).state =
              q.copyWith(status: 'all', page: 1);
          ref.read(stockOperationalFiltersProvider.notifier).state = op
              .copyWith(missingItemCodeOnly: true, clearMissingItemCode: false);
          ref.invalidate(stockListProvider);
        }

        void applyMissingBarcode() {
          ref.read(stockListQueryProvider.notifier).state =
              q.copyWith(status: 'all', page: 1);
          ref.read(stockOperationalFiltersProvider.notifier).state =
              op.copyWith(missingBarcodeOnly: true);
          ref.invalidate(stockListProvider);
        }

        final chips = <({String label, bool selected, VoidCallback onTap})>[
          (
            label: 'All (${counts['all'] ?? 0})',
            selected: q.status == 'all' &&
                !op.missingBarcodeOnly &&
                !op.missingItemCodeOnly,
            onTap: () => applyStatus('all'),
          ),
          (
            label: 'Low (${counts['low'] ?? 0})',
            selected: q.status == 'low',
            onTap: () => applyStatus('low'),
          ),
          (
            label: 'Out (${counts['out'] ?? 0})',
            selected: q.status == 'out',
            onTap: () => applyStatus('out'),
          ),
          (
            label: 'Missing code (${counts['missing_code'] ?? 0})',
            selected: op.missingItemCodeOnly,
            onTap: applyMissingCode,
          ),
          (
            label: 'Missing barcode (${counts['missing_barcode'] ?? 0})',
            selected: op.missingBarcodeOnly,
            onTap: applyMissingBarcode,
          ),
        ];

        return Padding(
          padding: EdgeInsets.fromLTRB(
            HexaResponsive.pageGutter(context, operational: true),
            4,
            HexaResponsive.pageGutter(context, operational: true),
            8,
          ),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in chips)
                HexaAccessibleFilterChip(
                  label: c.label,
                  selected: c.selected,
                  onSelected: (_) => c.onTap(),
                  compact: true,
                ),
            ],
          ),
        );
      },
    );
  }
}
