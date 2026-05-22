import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/hexa_operational_tokens.dart';
import '../../../../core/providers/home_dashboard_provider.dart';
import '../../../../core/providers/stock_providers.dart';
import '../../../../shared/widgets/operational_ui.dart';
import '../../stock_period_utils.dart';

const _kUnitLabels = ['BAG', 'KG', 'BOX', 'TIN', 'PIECE'];
const _kStatusLabels = ['Low', 'Critical', 'Missing Code', 'Out', 'Reorder'];

/// Pinned sticky filter chrome for stock list.
class StockPageFilterHeader extends ConsumerWidget {
  const StockPageFilterHeader({
    super.key,
    required this.searchExpanded,
    required this.searchController,
    required this.onSearchToggle,
    this.showYearPeriod = true,
  });

  final bool searchExpanded;
  final TextEditingController searchController;
  final VoidCallback onSearchToggle;
  final bool showYearPeriod;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(stockPagePeriodProvider);
    final op = ref.watch(stockOperationalFiltersProvider);
    final q = ref.watch(stockListQueryProvider);
    final filterCount = countOperationalActiveFilters(q, op);

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

    String? selectedStatus;
    if (op.reorderOnly) {
      selectedStatus = 'Reorder';
    } else if (op.missingItemCodeOnly) {
      selectedStatus = 'Missing Code';
    } else if (q.status == 'out') {
      selectedStatus = 'Out';
    } else if (q.status == 'critical') {
      selectedStatus = 'Critical';
    } else if (q.status == 'low') {
      selectedStatus = 'Low';
    }

    return ColoredBox(
      color: const Color(0xFFF5F3EE),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OperationalPillRow(
            labels: periodLabels,
            selected: period.label,
            height: 32,
            onSelected: (label) {
              final idx = periodLabels.indexOf(label);
              if (idx < 0 || idx >= periodValues.length) return;
              applyStockPagePeriod(ref, periodValues[idx]);
            },
          ),
          OperationalPillRow(
            labels: _kUnitLabels,
            selected: op.unit.isEmpty
                ? null
                : op.unit.toUpperCase() == 'KG'
                    ? 'KG'
                    : op.unit.toUpperCase(),
            height: 32,
            onSelected: (label) {
              final key = label.toLowerCase();
              final current = ref.read(stockOperationalFiltersProvider);
              final turningOff = current.unit == key;
              ref.read(stockOperationalFiltersProvider.notifier).state =
                  current.copyWith(
                unit: turningOff ? '' : key,
                clearUnit: turningOff,
              );
            },
          ),
          OperationalPillRow(
            labels: _kStatusLabels,
            selected: selectedStatus,
            height: 32,
            onSelected: (label) => _toggleStatusFilter(ref, label),
          ),
          if (searchExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                HexaOp.pageGutter,
                4,
                HexaOp.pageGutter,
                4,
              ),
              child: TextField(
                controller: searchController,
                autofocus: true,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Name, code, barcode, category…',
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFE0DDD8)),
                  ),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: onSearchToggle,
                  ),
                ),
              ),
            ),
          if (filterCount > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                HexaOp.pageGutter,
                2,
                HexaOp.pageGutter,
                4,
              ),
              child: Text(
                'Filters active ($filterCount)',
                style: const TextStyle(fontSize: 11, color: Colors.black45),
              ),
            ),
        ],
      ),
    );
  }

  void _toggleStatusFilter(WidgetRef ref, String label) {
    final q = ref.read(stockListQueryProvider);
    final op = ref.read(stockOperationalFiltersProvider);

    if (label == 'Low') {
      final on = q.status == 'low' && !op.reorderOnly && !op.missingItemCodeOnly;
      ref.read(stockListQueryProvider.notifier).state = q.copyWith(
        status: on ? 'all' : 'low',
        page: 1,
      );
      ref.read(stockOperationalFiltersProvider.notifier).state = op.copyWith(
        reorderOnly: false,
        clearMissingItemCode: true,
      );
      return;
    }
    if (label == 'Critical') {
      final on =
          q.status == 'critical' && !op.reorderOnly && !op.missingItemCodeOnly;
      ref.read(stockListQueryProvider.notifier).state = q.copyWith(
        status: on ? 'all' : 'critical',
        page: 1,
      );
      ref.read(stockOperationalFiltersProvider.notifier).state = op.copyWith(
        reorderOnly: false,
        clearMissingItemCode: true,
      );
      return;
    }
    if (label == 'Out') {
      final on = q.status == 'out' && !op.reorderOnly && !op.missingItemCodeOnly;
      ref.read(stockListQueryProvider.notifier).state = q.copyWith(
        status: on ? 'all' : 'out',
        page: 1,
      );
      ref.read(stockOperationalFiltersProvider.notifier).state = op.copyWith(
        reorderOnly: false,
        clearMissingItemCode: true,
      );
      return;
    }
    if (label == 'Missing Code') {
      final on = op.missingItemCodeOnly;
      ref.read(stockListQueryProvider.notifier).state =
          q.copyWith(status: 'all', page: 1);
      ref.read(stockOperationalFiltersProvider.notifier).state = op.copyWith(
        missingItemCodeOnly: !on,
        reorderOnly: false,
      );
      return;
    }
    if (label == 'Reorder') {
      final on = op.reorderOnly;
      ref.read(stockListQueryProvider.notifier).state =
          q.copyWith(status: 'all', page: 1);
      ref.read(stockOperationalFiltersProvider.notifier).state = op.copyWith(
        reorderOnly: !on,
        clearMissingItemCode: true,
      );
    }
  }
}

/// Pinned header delegate wrapping [StockPageFilterHeader].
class StockPageFilterSliverDelegate extends SliverPersistentHeaderDelegate {
  StockPageFilterSliverDelegate({
    required this.searchExpanded,
    required this.searchController,
    required this.onSearchToggle,
    required this.showYearPeriod,
  });

  final bool searchExpanded;
  final TextEditingController searchController;
  final VoidCallback onSearchToggle;
  final bool showYearPeriod;

  @override
  double get minExtent => _extent;

  @override
  double get maxExtent => _extent;

  double get _extent {
    var h = 32.0 * 3 + 10;
    if (searchExpanded) h += 48;
    return h + 18;
  }

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return StockPageFilterHeader(
      searchExpanded: searchExpanded,
      searchController: searchController,
      onSearchToggle: onSearchToggle,
      showYearPeriod: showYearPeriod,
    );
  }

  @override
  bool shouldRebuild(covariant StockPageFilterSliverDelegate old) {
    return old.searchExpanded != searchExpanded ||
        old.showYearPeriod != showYearPeriod;
  }
}
