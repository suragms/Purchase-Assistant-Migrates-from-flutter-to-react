import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/hexa_operational_tokens.dart';
import '../../../../core/providers/home_dashboard_provider.dart';
import '../../../../core/providers/stock_providers.dart';
import '../../stock_period_utils.dart';
/// Pinned sticky filter chrome: row 1 search, row 2 period + Filters.
class StockPageFilterHeader extends ConsumerWidget {
  const StockPageFilterHeader({
    super.key,
    required this.searchController,
    required this.onOpenFilters,
    this.showYearPeriod = true,
  });

  final TextEditingController searchController;
  final VoidCallback onOpenFilters;
  final bool showYearPeriod;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(stockPagePeriodProvider);
    final op = ref.watch(stockOperationalFiltersProvider);
    final q = ref.watch(stockListQueryProvider);
    final listData = ref.watch(stockListProvider).valueOrNull;
    final filterCount = countOperationalActiveFilters(q, op);
    final loaded = (listData?['items'] as List?)?.length ?? 0;
    final total = listData?['total'] ?? loaded;

    final periodLabels = showYearPeriod
        ? const ['Today', 'Week', 'Month', 'Year']
        : const ['Today', 'Week', 'Month'];
    final periodValues = showYearPeriod
        ? [
            HomePeriod.today,
            HomePeriod.week,
            HomePeriod.month,
            HomePeriod.year,
          ]
        : [HomePeriod.today, HomePeriod.week, HomePeriod.month];

    return ColoredBox(
      color: const Color(0xFFF5F3EE),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              HexaOp.pageGutter,
              6,
              HexaOp.pageGutter,
              4,
            ),
            child: TextField(
              controller: searchController,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Name, code, barcode, category…',
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                prefixIcon: const Icon(Icons.search, size: 20),
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
                          onSelected: (_) =>
                              applyStockPagePeriod(ref, periodValues[i]),
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
                _summaryChip('Loaded $loaded / $total'),
                if (filterCount > 0) _summaryChip('$filterCount filters'),
                _summaryChip(period.label),
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
    required this.showYearPeriod,
  });

  final TextEditingController searchController;
  final VoidCallback onOpenFilters;
  final bool showYearPeriod;

  @override
  double get minExtent => _extent;

  @override
  double get maxExtent => _extent;

  double get _extent => 32.0 * 2 + 52 + 42;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return StockPageFilterHeader(
      searchController: searchController,
      onOpenFilters: onOpenFilters,
      showYearPeriod: showYearPeriod,
    );
  }

  @override
  bool shouldRebuild(covariant StockPageFilterSliverDelegate old) {
    return old.showYearPeriod != showYearPeriod;
  }
}
