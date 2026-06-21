import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/business_write_event.dart';
import '../../../core/providers/catalog_providers.dart';
import '../../../core/router/navigation_ext.dart';
import '../../../core/search/catalog_fuzzy.dart';
import '../../../core/search/search_highlight.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../catalog_taxonomy_utils.dart';
import '../../../shared/widgets/trade_intel_cards.dart';
import 'widgets/quick_catalog_taxonomy_sheet.dart';

class CatalogCategoryDetailPage extends ConsumerStatefulWidget {
  const CatalogCategoryDetailPage({super.key, required this.categoryId});

  final String categoryId;

  @override
  ConsumerState<CatalogCategoryDetailPage> createState() =>
      _CatalogCategoryDetailPageState();
}

class _CatalogCategoryDetailPageState
    extends ConsumerState<CatalogCategoryDetailPage> {
  final _searchCtrl = TextEditingController();
  String _debouncedSearch = '';
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchTick);
  }

  void _onSearchTick() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      setState(() => _debouncedSearch = _searchCtrl.text);
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.removeListener(_onSearchTick);
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(categoryTypesIndexProvider);
    ref.invalidate(itemCategoriesListProvider);
    ref.invalidate(catalogItemsListProvider);
    ref.invalidate(categoryTradeSummaryProvider(widget.categoryId));
    await ref.read(itemCategoriesListProvider.future);
  }

  Future<void> _addSubcategory(BuildContext context) async {
    final r = await showQuickCatalogTaxonomySheet(
      context,
      mode: QuickCatalogTaxonomyMode.subcategoryOnly,
      preselectedCategoryId: widget.categoryId,
    );
    if (r != null) {
      ref.invalidate(categoryTypesIndexProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<BusinessWriteEvent>(businessWriteEventProvider, (prev, next) {
      if (next.revision <= (prev?.revision ?? -1)) return;
      if (!next.isGlobal && next.kind != 'purchase' && next.kind != 'aggregate') {
        return;
      }
      ref.invalidate(categoryTypesIndexProvider);
      ref.invalidate(catalogItemsListProvider);
      ref.invalidate(categoryTradeSummaryProvider(widget.categoryId));
    });

    final catsAsync = ref.watch(itemCategoriesListProvider);
    final itemsAsync = ref.watch(catalogItemsListProvider);
    final typesAsync = ref.watch(categoryTypesIndexProvider);
    final tradeSummaryAsync =
        ref.watch(categoryTradeSummaryProvider(widget.categoryId));

    final title = catsAsync.maybeWhen(
      data: (cats) {
        for (final c in cats) {
          if (c['id']?.toString() == widget.categoryId) {
            return c['name']?.toString() ?? 'Category';
          }
        }
        return 'Category';
      },
      orElse: () => 'Category',
    );

    final itemsInCat = itemsAsync.maybeWhen(
      data: (items) => items
          .where((it) => it['category_id']?.toString() == widget.categoryId)
          .toList(),
      orElse: () => <Map<String, dynamic>>[],
    );

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.popOrGo('/catalog'),
        ),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addSubcategory(context),
        icon: const Icon(Icons.add),
        label: const Text('Add subcategory'),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Category: $title',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'Total items: ${itemsInCat.length}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
            tradeSummaryAsync.when(
              skipLoadingOnReload: true,
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (sum) {
                final itemCount = (sum['item_count'] as num?)?.toInt() ?? 0;
                if (itemCount == 0) return const SizedBox.shrink();
                final tot = tradeIntelToDouble(sum['total_line_amount']);
                final kg = tradeIntelToDouble(sum['total_weight_kg']);
                final bags = tradeIntelToDouble(sum['total_qty_bags']);
                final volParts = <String>[];
                if (kg != null && kg > 1e-6) {
                  volParts.add('${tradeIntelFormatQty(kg)} KG');
                }
                if (bags != null && bags > 1e-6) {
                  volParts.add('${tradeIntelFormatQty(bags)} BAGS');
                }
                final volLine =
                    volParts.isEmpty ? '' : 'Trade volume: ${volParts.join(' • ')}';
                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                      color: Theme.of(context)
                          .colorScheme
                          .outlineVariant
                          .withValues(alpha: 0.85),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Trade pulse (confirmed bills)',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        if (tot != null && tot > 1e-6) ...[
                          const SizedBox(height: 6),
                          Text(
                            tradeIntelFormatInr(tot),
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                        ],
                        if (volLine.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            volLine,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            tradeSummaryAsync.when(
              skipLoadingOnReload: true,
              loading: () => const SizedBox.shrink(),
              error: (_, __) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Could not load trade summary.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                ),
              ),
              data: (sum) {
                final raw = sum['items'];
                if (raw is! List || raw.isEmpty) {
                  return const SizedBox.shrink();
                }
                final rows = <Map<String, dynamic>>[];
                for (final e in raw) {
                  if (e is Map) rows.add(Map<String, dynamic>.from(e));
                }
                if (rows.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Items (newest snapshot)',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(
                          color: Theme.of(context)
                              .colorScheme
                              .outlineVariant
                              .withValues(alpha: 0.85),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                        child: Column(
                          children: [
                            for (var i = 0; i < rows.length; i++) ...[
                              if (i > 0)
                                Divider(
                                  height: 1,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outlineVariant
                                      .withValues(alpha: 0.6),
                                ),
                              TradeIntelCategoryItemTile(
                                row: rows[i],
                                onTap: () {
                                  final id =
                                      rows[i]['catalog_item_id']?.toString();
                                  if (id == null || id.isEmpty) return;
                                  context.push('/catalog/item/$id');
                                },
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                );
              },
            ),
            TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Filter types',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _searchCtrl,
                  builder: (_, val, __) {
                    if (val.text.trim().isEmpty) return const SizedBox.shrink();
                    return IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        _searchDebounce?.cancel();
                        _searchCtrl.clear();
                        setState(() => _debouncedSearch = '');
                      },
                    );
                  },
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Types',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            typesAsync.when(
              skipLoadingOnReload: true,
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, __) => FriendlyLoadError(
                onRetry: () => ref.invalidate(categoryTypesIndexProvider),
              ),
              data: (index) {
                final types = typesForCategory(index, widget.categoryId);
                if (types.isEmpty) {
                  return Text(
                    'No subcategories yet — tap Add subcategory.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: HexaColors.textSecondary),
                  );
                }
                final filtered = _debouncedSearch.trim().isEmpty
                    ? types
                    : catalogFuzzyRank(
                        _debouncedSearch,
                        types,
                        (t) => t['name']?.toString() ?? '',
                        minScore: 38,
                        limit: 200,
                      );
                if (filtered.isEmpty) {
                  return Text(
                    'No matches — try another spelling.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: HexaColors.textSecondary,
                        ),
                  );
                }
                return Column(
                  children: [
                    for (final t in filtered)
                      _typeCard(
                        context,
                        typeId: t['id']?.toString() ?? '',
                        typeName: t['name']?.toString() ?? '',
                        highlightQuery: _debouncedSearch.trim(),
                        itemCount: itemsInCat
                            .where(
                              (it) =>
                                  it['type_id']?.toString() == t['id']?.toString(),
                            )
                            .length,
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _typeCard(
    BuildContext context, {
    required String typeId,
    required String typeName,
    required String highlightQuery,
    required int itemCount,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context)
              .colorScheme
              .outlineVariant
              .withValues(alpha: 0.8),
        ),
      ),
      child: InkWell(
        onTap: () => context.push(
          '/catalog/category/${widget.categoryId}/type/$typeId',
        ),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 44,
                decoration: BoxDecoration(
                  color: HexaColors.primaryMid.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: highlightSearchQuery(
                          typeName,
                          highlightQuery,
                          baseStyle: const TextStyle(fontWeight: FontWeight.w700),
                          highlightStyle: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Theme.of(context).colorScheme.primary,
                            backgroundColor: Theme.of(context)
                                .colorScheme
                                .primaryContainer
                                .withValues(alpha: 0.4),
                          ),
                        ),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      itemCount == 1 ? '1 item' : '$itemCount items',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: HexaColors.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}
