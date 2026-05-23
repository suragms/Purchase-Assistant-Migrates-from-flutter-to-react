import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/json_coerce.dart';
import '../../../core/providers/stock_providers.dart';
import '../../../core/providers/home_owner_dashboard_providers.dart';
import '../../../core/router/post_auth_route.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../../../core/widgets/list_skeleton.dart';
import '../stock_period_utils.dart';
import 'quick_stock_patch_sheet.dart';
import 'widgets/assign_barcode_sheet.dart';
import 'widgets/operational_stock_filter_sheet.dart';
import 'widgets/stock_operational_row.dart';
import 'widgets/stock_page_filter_header.dart';
import 'stock_item_intelligence_page.dart';

enum StockPageMode { auto, staff, owner }

const _kStockDetailPaneBreakpoint = 1100.0;

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
  bool _fabVisible = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    final initialQuery = ref.read(stockListQueryProvider).q.trim();
    _searchQuery = initialQuery.toLowerCase();
    _searchCtrl.text = initialQuery;
    _searchCtrl.addListener(_onSearchChanged);
    _subcatCtrl.text = ref.read(stockListQueryProvider).subcategory;
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      applyStockPagePeriod(ref, ref.read(stockPagePeriodProvider));
      ref.read(stockListQueryProvider.notifier).state =
          ref.read(stockListQueryProvider).copyWith(
                q: '',
                perPage: 50,
                page: 1,
              );
    });
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

  void _onSearchChanged() {
    final next = _searchCtrl.text.toLowerCase().trim();
    if (next == _searchQuery) return;
    setState(() {
      _searchQuery = next;
      ref.read(stockSelectedItemIdProvider.notifier).state = null;
    });
  }

  void _onScroll() {
    _onScrollLoadMore();
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
    final q = ref.read(stockListQueryProvider);
    final data = ref.read(stockListProvider).valueOrNull;
    if (data == null) return;
    final total = coerceToInt(data['total']);
    final loaded = (data['items'] as List?)?.length ?? 0;
    if (loaded >= total) return;
    setState(() => _loadingMore = true);
    ref.read(stockListQueryProvider.notifier).state =
        q.copyWith(page: q.page + 1);
  }

  List<Map<String, dynamic>> _prepareItems(List<Map<String, dynamic>> raw) {
    final op = ref.read(stockOperationalFiltersProvider);
    final q = ref.read(stockListQueryProvider);
    var items = filterStockListClient(raw, op);
    if (_searchQuery.isNotEmpty) {
      items = items.where((it) {
        final haystack = [
          it['name'],
          it['item_code'],
          it['barcode'],
          it['category_name'],
          it['subcategory_name'],
          it['supplier_name'],
        ].map((v) => v?.toString().toLowerCase() ?? '').join(' ');
        return haystack.contains(_searchQuery);
      }).toList();
    }
    if (q.supplier.isNotEmpty) {
      items = items
          .where(
            (it) =>
                (it['supplier_name']?.toString() ?? '').trim() == q.supplier,
          )
          .toList();
    }
    sortStockListOperational(items, searchQuery: _searchQuery);
    return items;
  }

  void _openItem(Map<String, dynamic> item) {
    final id = item['id']?.toString();
    if (id == null || id.isEmpty) return;
    final wide = MediaQuery.sizeOf(context).width >= _kStockDetailPaneBreakpoint;
    if (wide) {
      ref.read(stockSelectedItemIdProvider.notifier).state = id;
    } else {
      context.push('/stock/intelligence/$id');
    }
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
          ref.invalidate(stockListProvider);
          ref.invalidate(stockAuditPeriodProvider);
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

  @override
  Widget build(BuildContext context) {
    ref.listen(stockListProvider, (prev, next) {
      if (next is! AsyncData) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _loadingMore = false);
      });
    });

    final listAsync = ref.watch(stockListProvider);
    final listQ = ref.watch(stockListQueryProvider);
    final selectedId = ref.watch(stockSelectedItemIdProvider);
    final width = MediaQuery.sizeOf(context).width;
    final useSplit = width >= _kStockDetailPaneBreakpoint;
    final includePeriod = listQ.includePeriod;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F3EE),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F3EE),
        foregroundColor: const Color(0xFF1A1A1A),
        title: const Text('Stock', style: TextStyle(fontSize: 18)),
        actions: [
          if (!_isStaffMode)
            IconButton(
              icon: const Icon(Icons.swap_vert_rounded),
              tooltip: 'Stock movement',
              onPressed: () => context.push('/stock/movement'),
            ),
          if (!_isStaffMode)
            IconButton(
              icon: const Icon(Icons.qr_code_2_rounded),
              tooltip: 'Barcode',
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
      floatingActionButton: null,
      body: listAsync.when(
        loading: () => const ListSkeleton(rowCount: 10),
        error: (e, _) => FriendlyLoadError(
          onRetry: () => ref.invalidate(stockListProvider),
        ),
        data: (data) {
          final raw = [
            for (final e in (data['items'] as List? ?? []))
              if (e is Map) Map<String, dynamic>.from(e),
          ];
          final items = _prepareItems(raw);

          final listBody = RefreshIndicator(
            onRefresh: () async {
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
                    onOpenFilters: () => showOperationalStockFilter(
                      context: context,
                      ref: ref,
                      subcategoryCtrl: _subcatCtrl,
                      isStaffMode: _isStaffMode,
                    ),
                    showYearPeriod: !_isStaffMode,
                  ),
                ),
                if (items.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text(
                        'No items match filters',
                        style: TextStyle(fontSize: 13, color: Colors.black54),
                      ),
                    ),
                  )
                else
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) {
                        if (i >= items.length) {
                          return _loadingMore
                              ? const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                )
                              : const SizedBox(height: 72);
                        }
                        final item = items[i];
                        return RepaintBoundary(
                          child: StockOperationalRow(
                            item: item,
                            includePeriod: includePeriod,
                            canEdit: true,
                            onTap: () => _openItem(item),
                            onAction: () => unawaited(_openStockActions(item)),
                          ),
                        );
                      },
                      childCount: items.length + 1,
                    ),
                  ),
              ],
            ),
          );

          if (!useSplit) {
            return listBody;
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 3, child: listBody),
              const VerticalDivider(width: 1),
              Expanded(
                flex: 2,
                child: selectedId == null
                    ? const Center(
                        child: Text(
                          'Select an item',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.black45,
                          ),
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
        },
      ),
    );
  }
}
