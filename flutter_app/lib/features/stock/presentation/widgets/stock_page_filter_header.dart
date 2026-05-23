import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/hexa_operational_tokens.dart';
import '../../../../core/providers/home_dashboard_provider.dart';
import '../../../../core/providers/stock_providers.dart';
import '../../stock_period_utils.dart';
import 'stock_inline_category_filters.dart';

/// Pinned sticky filter chrome: search, period, Filters, summary (All tab).
class StockPageFilterHeader extends ConsumerWidget {
  const StockPageFilterHeader({
    super.key,
    required this.searchController,
    required this.onOpenFilters,
    required this.onClearSearch,
    this.showYearPeriod = true,
    this.isReloading = false,
    this.showingCount = 0,
    this.totalCount = 0,
    this.includeInlineCategory = false,
    this.subcategoryController,
    this.onFiltersCleared,
  });

  final TextEditingController searchController;
  final VoidCallback onOpenFilters;
  final VoidCallback onClearSearch;
  final bool showYearPeriod;
  final bool isReloading;
  final int showingCount;
  final int totalCount;
  final bool includeInlineCategory;
  final TextEditingController? subcategoryController;
  final VoidCallback? onFiltersCleared;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(stockPagePeriodProvider);
    final op = ref.watch(stockOperationalFiltersProvider);
    final q = ref.watch(stockListQueryProvider);
    final filterCount = countOperationalActiveFilters(q, op);
    final hasSearch = searchController.text.trim().isNotEmpty;

    final periodLabels = showYearPeriod
        ? const ['Today', 'Week', 'Month', 'Year', 'All time']
        : const ['Today', 'Week', 'Month', 'All time'];
    final periodValues = showYearPeriod
        ? [
            HomePeriod.today,
            HomePeriod.week,
            HomePeriod.month,
            HomePeriod.year,
            HomePeriod.allTime,
          ]
        : [
            HomePeriod.today,
            HomePeriod.week,
            HomePeriod.month,
            HomePeriod.allTime,
          ];

    return ColoredBox(
      color: const Color(0xFFF5F3EE),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isReloading)
            const LinearProgressIndicator(minHeight: 2),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              HexaOp.pageGutter,
              6,
              HexaOp.pageGutter,
              4,
            ),
            child: TextField(
              controller: searchController,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                hintText: 'Name, code, barcode, category…',
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: hasSearch
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        tooltip: 'Clear search',
                        onPressed: onClearSearch,
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFE0DDD8)),
                ),
              ),
            ),
          ),
          if (includeInlineCategory && subcategoryController != null)
            StockInlineCategoryFilters(
              subcategoryController: subcategoryController!,
              onFiltersCleared: onFiltersCleared,
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              HexaOp.pageGutter,
              0,
              HexaOp.pageGutter,
              6,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (var i = 0; i < periodLabels.length; i++)
                        FilterChip(
                          label: Text(
                            periodLabels[i],
                            style: const TextStyle(fontSize: 12),
                          ),
                          selected: period.label == periodLabels[i],
                          onSelected: (_) {
                            onFiltersCleared?.call();
                            applyStockPagePeriod(ref, periodValues[i]);
                          },
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: onOpenFilters,
                  icon: Badge(
                    isLabelVisible: filterCount > 0,
                    label: Text('$filterCount'),
                    child: const Icon(Icons.tune, size: 18),
                  ),
                  label: const Text('Filters'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(48, 40),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              HexaOp.pageGutter,
              0,
              HexaOp.pageGutter,
              4,
            ),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _summaryChip('Showing $showingCount of $totalCount'),
                if (filterCount > 0) _summaryChip('$filterCount filters'),
                _summaryChip(period.label),
                FilterChip(
                  label: const Text('Purchased', style: TextStyle(fontSize: 11)),
                  selected: op.purchasedInPeriodOnly,
                  onSelected: (_) {
                    onFiltersCleared?.call();
                    final next = !op.purchasedInPeriodOnly;
                    ref.read(stockOperationalFiltersProvider.notifier).state =
                        op.copyWith(purchasedInPeriodOnly: next);
                    ref.read(stockListQueryProvider.notifier).state =
                        ref.read(stockListQueryProvider).copyWith(
                              purchasedInPeriod: next,
                              page: 1,
                            );
                  },
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE0DDD8)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: Colors.black54,
        ),
      ),
    );
  }
}

/// Pinned header delegate wrapping [StockPageFilterHeader].
class StockPageFilterSliverDelegate extends SliverPersistentHeaderDelegate {
  StockPageFilterSliverDelegate({
    required this.searchController,
    required this.onOpenFilters,
    required this.onClearSearch,
    required this.showYearPeriod,
    this.isReloading = false,
    this.showingCount = 0,
    this.totalCount = 0,
    this.includeInlineCategory = false,
    this.subcategoryController,
    this.onFiltersCleared,
  });

  final TextEditingController searchController;
  final VoidCallback onOpenFilters;
  final VoidCallback onClearSearch;
  final bool showYearPeriod;
  final bool isReloading;
  final int showingCount;
  final int totalCount;
  final bool includeInlineCategory;
  final TextEditingController? subcategoryController;
  final VoidCallback? onFiltersCleared;

  @override
  double get minExtent => _extent;

  @override
  double get maxExtent => _extent;

  double get _extent {
    var h = 32.0 * 2 + 52 + 42 + (isReloading ? 2 : 0);
    if (includeInlineCategory) h += 118;
    return h;
  }

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return StockPageFilterHeader(
      searchController: searchController,
      onOpenFilters: onOpenFilters,
      onClearSearch: onClearSearch,
      showYearPeriod: showYearPeriod,
      isReloading: isReloading,
      showingCount: showingCount,
      totalCount: totalCount,
      includeInlineCategory: includeInlineCategory,
      subcategoryController: subcategoryController,
      onFiltersCleared: onFiltersCleared,
    );
  }

  @override
  bool shouldRebuild(covariant StockPageFilterSliverDelegate old) {
    return old.showYearPeriod != showYearPeriod ||
        old.isReloading != isReloading ||
        old.showingCount != showingCount ||
        old.totalCount != totalCount ||
        old.includeInlineCategory != includeInlineCategory;
  }
}
