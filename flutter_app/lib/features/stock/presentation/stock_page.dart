import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/json_coerce.dart';
import '../../../core/providers/home_owner_dashboard_providers.dart';
import '../../../core/providers/stock_providers.dart';
import '../../../core/router/post_auth_route.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../../../core/widgets/list_skeleton.dart';
import '../stock_list_merge.dart';
import '../stock_period_utils.dart';
import 'quick_stock_patch_sheet.dart';
import 'stock_item_intelligence_page.dart';
import 'widgets/assign_barcode_sheet.dart';
import 'widgets/operational_stock_filter_sheet.dart';
import 'widgets/stock_changes_tab.dart';
import 'widgets/stock_list_column_header.dart';
import 'widgets/stock_operational_row.dart';
import 'widgets/stock_page_filter_header.dart';
import 'widgets/stock_pagination_bar.dart';
import 'widgets/stock_row_preview_sheet.dart';

enum StockPageMode { auto, staff, owner }

const _kStockDetailPaneBreakpoint = 1100.0;

class StockPage extends ConsumerStatefulWidget {
  const StockPage({super.key, this.mode = StockPageMode.auto});

  final StockPageMode mode;

  @override
  ConsumerState<StockPage> createState() => _StockPageState();
}

class _StockPageState extends ConsumerState<StockPage>
    with SingleTickerProviderStateMixin {
  final _searchCtrl = TextEditingController();
  final _subcatCtrl = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;
  bool _loadingMore = false;
  bool _fabVisible = true;
  Map<String, dynamic>? _mergedData;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(() {
        if (!_tabController.indexIsChanging) setState(() {});
      });
    final initialQuery = ref.read(stockListQueryProvider);
    _searchCtrl.text = initialQuery.q.trim();
    _searchCtrl.addListener(_onSearchChanged);
    _subcatCtrl.text = initialQuery.subcategory;
    _scroll.addListener(_onScroll);
    applyStockPagePeriod(ref, ref.read(stockPagePeriodProvider));
    final q = ref.read(stockListQueryProvider);
    if (q.perPage != 50) {
      ref.read(stockListQueryProvider.notifier).state =
          q.copyWith(perPage: 50, page: 1);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _tabController.dispose();
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

  void _resetMerged() {
    _mergedData = null;
  }

  void _clearSearch() {
    _searchCtrl.clear();
    ref.read(stockSelectedItemIdProvider.notifier).state = null;
    ref.read(stockListQueryProvider.notifier).state =
        ref.read(stockListQueryProvider).copyWith(q: '', page: 1);
    _resetMerged();
    ref.invalidate(stockListProvider);
  }

  void _onSearchChanged() {
    final raw = _searchCtrl.text.trim();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      ref.read(stockSelectedItemIdProvider.notifier).state = null;
      final q = ref.read(stockListQueryProvider);
      if (q.q == raw) return;
      _resetMerged();
      ref.read(stockListQueryProvider.notifier).state =
          q.copyWith(q: raw, page: 1);
    });
  }

  void _onScroll() {
    if (_tabController.index == 0) {
      _onScrollLoadMore();
    }
    if (!_scroll.hasClients) return;
    final dir = _scroll.position.userScrollDirection;
    if (dir == ScrollDirection.reverse && _fabVisible) {
      setState(() => _fabVisible = false);
    } else if ((dir == ScrollDirection.forward ||
            _scroll.position.pixels <= 24) &&
        !_fabVisible) {
      setState(() => _fabVisible = true);
    }
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
    ref.read(stockListQueryProvider.notifier).state =
        q.copyWith(page: newPage);
  }

  List<Map<String, dynamic>> _prepareItems(List<Map<String, dynamic>> raw) {
    final op = ref.read(stockOperationalFiltersProvider);
    final q = ref.read(stockListQueryProvider);
    var items = filterStockListClient(raw, op);
    // Server handles `q=` — client filter only for supplier (no API param).
    if (q.supplier.isNotEmpty) {
      items = items
          .where(
            (it) =>
                (it['supplier_name']?.toString() ?? '').trim() == q.supplier,
          )
          .toList();
    }
    sortStockListOperational(
      items,
      searchQuery: q.q.trim().toLowerCase(),
      sort: q.sort,
      prioritizePeriodPurchases:
          op.purchasedInPeriodOnly || q.purchasedInPeriod,
    );
    return items;
  }

  void _openItemPreview(Map<String, dynamic> item) {
    unawaited(
      showStockRowPreviewSheet(
        context: context,
        ref: ref,
        item: item,
        isStaffMode: _isStaffMode,
      ),
    );
  }

  Future<void> _openStockActions(Map<String, dynamic> item) async {
    final id = item['id']?.toString();
    final name = item['name']?.toString() ?? 'Item';
    if (id == null || id.isEmpty) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: const Text('Choose stock action'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_note_rounded),
              title: const Text('Update stock'),
              onTap: () => ctx.pop('update'),
            ),
            ListTile(
              leading: const Icon(Icons.qr_code_scanner_rounded),
              title: const Text('Scan'),
              onTap: () => ctx.pop('scan'),
            ),
            ListTile(
              leading: const Icon(Icons.history_rounded),
              title: const Text('Purchase history'),
              onTap: () => ctx.pop('history'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_rounded),
              title: const Text('Edit item'),
              onTap: () => ctx.pop('edit'),
            ),
            ListTile(
              leading: const Icon(Icons.qr_code_2_rounded),
              title: const Text('Assign barcode'),
              onTap: () => ctx.pop('barcode'),
            ),
            ListTile(
              leading: const Icon(Icons.print_outlined),
              title: const Text('Print labels'),
              onTap: () => ctx.pop('print'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'update':
        final saved = await showQuickStockPatchSheet(
          context: context,
          ref: ref,
          item: item,
        );
        if (saved && mounted) {
          _resetMerged();
          ref.invalidate(stockListProvider);
          ref.invalidate(stockAuditPeriodProvider);
          ref.invalidate(stockChangesFeedProvider);
          ref.invalidate(stockItemIntelligenceProvider(id));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Stock updated')),
          );
        }
        break;
      case 'scan':
        context.push('/barcode/scan?return=stock');
        break;
      case 'history':
      case 'edit':
        context.push('/catalog/item/$id');
        break;
      case 'barcode':
        await showAssignBarcodeSheet(
          context: context,
          ref: ref,
          itemId: id,
          itemName: name,
        );
        break;
      case 'print':
        context.push('/barcode/bulk-print');
        break;
    }
  }

  Widget _buildAllTabBody({
    required Map<String, dynamic> data,
    required bool includePeriod,
    required bool isReloading,
    required bool purchasedFilterOnly,
  }) {
    final raw = [
      for (final e in (data['items'] as List? ?? []))
        if (e is Map) Map<String, dynamic>.from(e),
    ];
    final items = _prepareItems(raw);
    final listQ = ref.watch(stockListQueryProvider);
    final total = coerceToInt(data['total']);
    final maxPage = stockListMaxPage(total, listQ.perPage);
    final bottomPad = MediaQuery.paddingOf(context).bottom + 16;

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
            delegate: StockPageFilterSliverDelegate(
              searchController: _searchCtrl,
              onClearSearch: _clearSearch,
              onOpenFilters: () => showOperationalStockFilter(
                context: context,
                ref: ref,
                subcategoryCtrl: _subcatCtrl,
                isStaffMode: _isStaffMode,
                bottomNavInset: bottomPad,
              ),
              showYearPeriod: !_isStaffMode,
              isReloading: isReloading,
              showingCount: raw.length,
              totalCount: total,
              includeInlineCategory: true,
              subcategoryController: _subcatCtrl,
              onFiltersCleared: _resetMerged,
            ),
          ),
          if (items.isNotEmpty) ...[
            const SliverToBoxAdapter(child: StockListColumnHeader()),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) {
                  final item = items[i];
                  return RepaintBoundary(
                    child: StockOperationalRow(
                      item: item,
                      includePeriod: includePeriod,
                      canEdit: true,
                      bordered: true,
                      isFirstRow: i == 0,
                      onTap: () => _openItemPreview(item),
                      onAction: () => unawaited(_openStockActions(item)),
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
                  purchasedFilterOnly
                      ? 'No purchases in this period — try All time or clear Purchased'
                      : 'No items match filters',
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
      if (prev.page == 1 && next.page == 1 &&
          (prev.q != next.q ||
              prev.category != next.category ||
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
    final selectedId = ref.watch(stockSelectedItemIdProvider);
    final width = MediaQuery.sizeOf(context).width;
    final useSplit = width >= _kStockDetailPaneBreakpoint && _tabController.index == 0;
    final includePeriod = listQ.includePeriod;
    final data = _mergedData ?? listAsync.valueOrNull;
    final isReloading = listAsync.isLoading && data != null;

    Widget allTabBody;
    if (data == null && listAsync.isLoading) {
      allTabBody = const ListSkeleton(rowCount: 10);
    } else if (listAsync.hasError && data == null) {
      allTabBody = FriendlyLoadError(
        onRetry: () {
          _resetMerged();
          ref.invalidate(stockListProvider);
        },
      );
    } else if (data != null) {
      allTabBody = _buildAllTabBody(
        data: data,
        includePeriod: includePeriod,
        isReloading: isReloading,
        purchasedFilterOnly: op.purchasedInPeriodOnly,
      );
    } else {
      allTabBody = const ListSkeleton(rowCount: 10);
    }

    final tabViews = TabBarView(
      controller: _tabController,
      children: [
        allTabBody,
        StockChangesTab(isStaffMode: _isStaffMode),
      ],
    );

    final Widget body;
    if (useSplit && data != null && _tabController.index == 0) {
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 3, child: allTabBody),
          const VerticalDivider(width: 1),
          Expanded(
            flex: 2,
            child: selectedId == null
                ? const Center(
                    child: Text(
                      'Select an item',
                      style: TextStyle(fontSize: 13, color: Colors.black45),
                    ),
                  )
                : StockItemIntelligencePage(
                    itemId: selectedId,
                    embedded: true,
                    hideOwnerAnalytics: _isStaffMode,
                  ),
          ),
        ],
      );
    } else {
      body = tabViews;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F3EE),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F3EE),
        foregroundColor: const Color(0xFF1A1A1A),
        leading: IconButton(
          icon: const Icon(Icons.home_outlined),
          tooltip: 'Home',
          onPressed: () => context.go(_isStaffMode ? '/staff/home' : '/home'),
        ),
        title: const Text('Stock', style: TextStyle(fontSize: 18)),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: 'All items'),
            Tab(text: 'Changes'),
          ],
        ),
        actions: [
          if (!_isStaffMode)
            IconButton(
              icon: const Icon(Icons.swap_vert_rounded),
              tooltip: 'Stock movement',
              onPressed: () => context.push('/stock/movement'),
            ),
          IconButton(
            icon: const Icon(Icons.qr_code_2_rounded),
            tooltip: 'Scan',
            onPressed: () => context.push('/barcode/scan?return=stock'),
          ),
          if (!_isStaffMode)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Add item',
              onPressed: () => context.push('/catalog/quick-add'),
            ),
        ],
      ),
      body: body,
    );
  }
}
