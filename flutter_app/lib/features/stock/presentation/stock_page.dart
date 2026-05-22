import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design_system/hexa_operational_tokens.dart';
import '../../../core/json_coerce.dart';
import '../../../core/providers/catalog_providers.dart';
import '../../../core/providers/stock_providers.dart';
import '../../../core/utils/operational_date_format.dart';
import '../../../core/utils/unit_utils.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../../../core/widgets/list_skeleton.dart';
import 'widgets/stock_bulk_actions_sheet.dart';
import 'widgets/stock_filter_bottom_sheet.dart';
import 'widgets/stock_row_actions.dart';

class StockPage extends ConsumerStatefulWidget {
  const StockPage({super.key});

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
  bool _filterLow = false;
  bool _filterMissingBarcode = false;
  bool _filterEviction = false;
  String? _filterUnit;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
    _subcatCtrl.text = ref.read(stockListQueryProvider).subcategory;
    _scroll.addListener(_onScrollLoadMore);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(stockListQueryProvider.notifier).state =
          const StockListQuery(perPage: 50, page: 1);
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

  List<Map<String, dynamic>> _clientFilter(List<Map<String, dynamic>> items) {
    return items.where((it) {
      if (_filterLow) {
        final st = it['stock_status']?.toString() ?? '';
        if (st != 'low' && st != 'critical' && st != 'out') return false;
      }
      if (_filterMissingBarcode && it['missing_barcode'] != true) {
        return false;
      }
      if (_filterEviction && it['needs_eviction'] != true) return false;
      if (_filterUnit != null) {
        final u = (it['unit']?.toString() ?? '').toLowerCase();
        if (u != _filterUnit) return false;
      }
      return true;
    }).toList();
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
    final categories = ref.watch(itemCategoriesListProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F3EE),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F3EE),
        foregroundColor: const Color(0xFF1A1A1A),
        title: _searchExpanded
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search stock…',
                  border: InputBorder.none,
                ),
              )
            : const Text('Stock'),
        actions: [
          IconButton(
            icon: Icon(_searchExpanded ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _searchExpanded = !_searchExpanded;
                if (!_searchExpanded) _searchCtrl.clear();
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.layers_outlined),
            tooltip: 'Bulk actions',
            onPressed: () => showStockBulkActionsSheet(context: context, ref: ref),
          ),
          IconButton(
            icon: const Icon(Icons.tune),
            onPressed: () => showStockFilterBottomSheet(
              context: context,
              ref: ref,
              initial: ref.read(stockListQueryProvider),
              subcategoryCtrl: _subcatCtrl,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Scan',
            onPressed: () => context.push('/barcode/scan?return=stock'),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Quick add',
            onPressed: () => context.push('/catalog/quick-add'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/barcode/scan?return=stock'),
        backgroundColor: const Color(0xFF3B6D11),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('Scan'),
      ),
      body: listAsync.when(
        loading: () => const ListSkeleton(rowCount: 8),
        error: (e, _) => FriendlyLoadError(
          onRetry: () => ref.invalidate(stockListProvider),
        ),
        data: (data) {
          final raw = [
            for (final e in (data['items'] as List? ?? []))
              if (e is Map) Map<String, dynamic>.from(e),
          ];
          final items = _clientFilter(raw);
          final eviction = items.where((i) => i['needs_eviction'] == true).toList();
          final low = items
              .where((i) {
                final st = i['stock_status']?.toString() ?? '';
                return (st == 'low' || st == 'critical' || st == 'out') &&
                    i['needs_eviction'] != true;
              })
              .toList();
          final all = items;

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(stockListProvider);
              await ref.read(stockListProvider.future);
            },
            child: CustomScrollView(
              controller: _scroll,
              slivers: [
                SliverToBoxAdapter(child: _buildFilterChips(categories)),
                if (eviction.isNotEmpty) ...[
                  _sectionHeader('Needs eviction', color: const Color(0xFFA32D2D)),
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) => RepaintBoundary(
                        child: _StockEaseRow(
                          item: eviction[i],
                          highlight: StockRowHighlight.eviction,
                          onMore: () => showStockRowActions(
                            context: context,
                            ref: ref,
                            item: eviction[i],
                          ),
                          onTap: () => _openIntelligence(eviction[i]),
                        ),
                      ),
                      childCount: eviction.length,
                    ),
                  ),
                ],
                if (low.isNotEmpty) ...[
                  _sectionHeader('Low stock', color: const Color(0xFFBA7517)),
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) => RepaintBoundary(
                        child: _StockEaseRow(
                          item: low[i],
                          highlight: StockRowHighlight.low,
                          onMore: () => showStockRowActions(
                            context: context,
                            ref: ref,
                            item: low[i],
                          ),
                          onTap: () => _openIntelligence(low[i]),
                        ),
                      ),
                      childCount: low.length,
                    ),
                  ),
                ],
                _sectionHeader('All items', color: const Color(0xFF3B6D11)),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) {
                      if (i >= all.length) {
                        return _loadingMore
                            ? const Padding(
                                padding: EdgeInsets.all(16),
                                child: Center(child: CircularProgressIndicator()),
                              )
                            : const SizedBox(height: 80);
                      }
                      return RepaintBoundary(
                        child: _StockEaseRow(
                          item: all[i],
                          onMore: () => showStockRowActions(
                            context: context,
                            ref: ref,
                            item: all[i],
                          ),
                          onTap: () => _openIntelligence(all[i]),
                        ),
                      );
                    },
                    childCount: all.length + 1,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _openIntelligence(Map<String, dynamic> item) {
    final id = item['id']?.toString();
    if (id != null && id.isNotEmpty) {
      context.push('/stock/intelligence/$id');
    }
  }

  Widget _buildFilterChips(AsyncValue<List<Map<String, dynamic>>> categoriesAsync) {
    final cats = categoriesAsync.valueOrNull ?? [];
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        HexaOp.pageGutter,
        8,
        HexaOp.pageGutter,
        4,
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilterChip(
            label: const Text('Low stock'),
            selected: _filterLow,
            onSelected: (v) => setState(() => _filterLow = v),
          ),
          FilterChip(
            label: const Text('Missing barcode'),
            selected: _filterMissingBarcode,
            onSelected: (v) => setState(() => _filterMissingBarcode = v),
          ),
          FilterChip(
            label: const Text('Eviction'),
            selected: _filterEviction,
            onSelected: (v) => setState(() => _filterEviction = v),
          ),
          for (final u in ['bag', 'box', 'tin', 'kg', 'piece'])
            FilterChip(
              label: Text(u.toUpperCase()),
              selected: _filterUnit == u,
              onSelected: (v) => setState(() => _filterUnit = v ? u : null),
            ),
          for (final c in cats.take(12))
            FilterChip(
              label: Text(
                c['name']?.toString() ?? '',
                overflow: TextOverflow.ellipsis,
              ),
              selected: ref.watch(stockListQueryProvider).category ==
                  (c['name']?.toString() ?? ''),
              onSelected: (_) {
                final name = c['name']?.toString() ?? '';
                final cur = ref.read(stockListQueryProvider).category;
                ref.read(stockListQueryProvider.notifier).state =
                    ref.read(stockListQueryProvider).copyWith(
                          category: cur == name ? '' : name,
                          page: 1,
                        );
              },
            ),
          ActionChip(
            avatar: const Icon(Icons.label_off_outlined, size: 18),
            label: const Text('Missing codes'),
            onPressed: () => context.push('/stock/missing-barcodes'),
          ),
        ],
      ),
    );
  }

  SliverToBoxAdapter _sectionHeader(String title, {required Color color}) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 20,
              color: color,
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum StockRowHighlight { none, low, eviction }

class _StockEaseRow extends StatelessWidget {
  const _StockEaseRow({
    required this.item,
    required this.onMore,
    required this.onTap,
    this.highlight = StockRowHighlight.none,
  });

  final Map<String, dynamic> item;
  final VoidCallback onMore;
  final VoidCallback onTap;
  final StockRowHighlight highlight;

  @override
  Widget build(BuildContext context) {
    final name = item['name']?.toString() ?? '—';
    final code = item['item_code']?.toString() ?? '—';
    final unit = item['unit']?.toString() ?? '';
    final cat = item['category_name']?.toString() ?? '';
    final sub = item['subcategory_name']?.toString() ?? '';
    final cur = coerceToDouble(item['current_stock']);
    final reorder = coerceToDouble(item['reorder_level']);
    final bought = coerceToDouble(item['purchased_today_qty']);
    final used = coerceToDouble(item['usage_today_qty']);
    final days = item['days_since_last_purchase'] as int?;

    double? progress;
    Color barColor = const Color(0xFF3B6D11);
    if (reorder > 0) {
      progress = (cur / reorder).clamp(0.0, 1.0);
      if (cur <= 0) {
        barColor = const Color(0xFFA32D2D);
      } else if (cur <= reorder) {
        barColor = const Color(0xFFBA7517);
      }
    }

    final stockPrimary = stockDisplayPrimary(cur, unit);
    final stockSecondary = stockDisplaySecondary(cur, unit, null, null);
    final boughtLabel = bought > 0
        ? 'Today: +${stockDisplayPrimary(bought, unit)}'
        : 'Today: none';
    final usedLabel = used > 0
        ? 'Used: -${stockDisplayPrimary(used, unit)}'
        : 'Used: —';
    final lastLine = formatLastStockUpdateLine(
      updatedBy: item['last_stock_updated_by']?.toString(),
      updatedAtIso: item['last_stock_updated_at']?.toString(),
    );

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: HexaOp.listRowMax),
          child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: HexaOp.pageGutter,
            vertical: 8,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E0),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      unit.isEmpty ? '—' : unit.toUpperCase(),
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (highlight == StockRowHighlight.eviction)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Chip(
                        label: const Text('EVICT NOW', style: TextStyle(fontSize: 9)),
                        backgroundColor: const Color(0xFFFFEBEE),
                        padding: EdgeInsets.zero,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                ],
              ),
              Text(
                code,
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
              Text(
                [cat, sub].where((s) => s.isNotEmpty).join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
              if (progress != null) ...[
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    backgroundColor: const Color(0xFFE0DDD8),
                    color: barColor,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      stockSecondary != null
                          ? 'Stock: $stockPrimary\n$stockSecondary'
                          : 'Stock: $stockPrimary',
                      style: valueStyle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      boughtLabel,
                      style: valueStyle,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      usedLabel,
                      style: valueStyle,
                      textAlign: TextAlign.end,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.more_vert),
                    onPressed: onMore,
                    tooltip: 'Actions',
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  ),
                ],
              ),
              if (lastLine.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    lastLine,
                    style: const TextStyle(fontSize: 11, color: Colors.black45),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (days != null && highlight == StockRowHighlight.eviction)
                Text(
                  '$days days since last purchase',
                  style: const TextStyle(fontSize: 11, color: Color(0xFFA32D2D)),
                ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  static const valueStyle = TextStyle(fontSize: 12, fontWeight: FontWeight.w600);
}
