import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/json_coerce.dart';
import '../../../../core/providers/analytics_breakdown_providers.dart';
import '../../../../core/providers/home_dashboard_provider.dart';
import '../../../../core/reporting/trade_report_aggregate.dart';
import '../../../../shared/widgets/warehouse_units_breakdown_line.dart';
import '../../widgets/bi/reports_bi_slice.dart';
import '../../widgets/bi/warehouse_ring_section.dart';
import '../reports_category_drill_page.dart';
import '../reports_subcategory_drill_page.dart';

List<ReportsBiSlice> _filterSlices(
  List<ReportsBiSlice> slices,
  String searchQuery,
) {
  final q = searchQuery.trim().toLowerCase();
  if (q.isEmpty) return slices;
  return [
    for (final s in slices)
      if (s.title.toLowerCase().contains(q) ||
          s.subtitle.toLowerCase().contains(q))
        s,
  ];
}

/// Categories or subcategories tab with ring + list.
class ReportsBreakdownTab extends ConsumerWidget {
  const ReportsBreakdownTab({
    super.key,
    required this.subcategories,
    required this.agg,
    this.searchQuery = '',
    this.expanded = false,
  });

  final bool subcategories;
  final TradeReportAgg agg;
  final String searchQuery;
  final bool expanded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final typesAsync = ref.watch(analyticsTypesTableProvider);
    final catsAsync = ref.watch(analyticsCategoriesTableProvider);
    final dash = ref.watch(homeDashboardDataProvider).snapshot.data;
    final units = warehouseUnitSegmentsFromTradeTotals(agg.totals);

    if (subcategories) {
      return typesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _retry(context, ref),
        data: (rows) {
          final total = rows.fold<double>(
            0,
            (s, r) => s + coerceToDouble(r['total_purchase']),
          );
          var slices = slicesFromSubcategoryMaps(rows, totalAmount: total);
          if (slices.isEmpty) {
            slices = slicesFromDashboardSubcategories(dash);
          }
          return _body(
            context,
            _filterSlices(slices, searchQuery),
            'subcategories',
            units,
          );
        },
      );
    }
    return catsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => _retry(context, ref),
      data: (rows) {
        final total = rows.fold<double>(
          0,
          (s, r) => s + coerceToDouble(r['total_purchase'] ?? r['total_amount']),
        );
        var slices = slicesFromCategoryMaps(rows, totalAmount: total);
        if (slices.isEmpty) {
          slices = slicesFromDashboardCategories(dash);
        }
        return _body(
          context,
          _filterSlices(slices, searchQuery),
          'categories',
          units,
        );
      },
    );
  }

  Widget _retry(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Unable to load analytics.', style: TextStyle(fontSize: 13)),
          TextButton(
            onPressed: () {
              ref.invalidate(
                subcategories
                    ? analyticsTypesTableProvider
                    : analyticsCategoriesTableProvider,
              );
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _body(
    BuildContext context,
    List<ReportsBiSlice> slices,
    String labelKind,
    List<WarehouseUnitSegment> units,
  ) {
    final q = searchQuery.trim();
    if (slices.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            q.isNotEmpty
                ? 'No $labelKind match "$q".\nTry another search or period.'
                : 'No purchases in selected period.\nTry changing date range.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Colors.black54),
          ),
        ),
      );
    }
    final centerLabel =
        subcategories ? 'subcategory spend' : 'category spend';
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        WarehouseRingSection(
          slices: slices,
          centerLabel: centerLabel,
          unitSegments: units,
          expanded: expanded,
          onSliceTap: (_, slice) {
            if (subcategories) {
              context.push(
                '/reports/subcategory-drill',
                extra: ReportsSubcategoryDrillPage(
                  subcategoryName: slice.title,
                ),
              );
            } else {
              context.push(
                '/reports/category-drill',
                extra: ReportsCategoryDrillPage(categoryName: slice.title),
              );
            }
          },
        ),
        if (q.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 4),
            child: Text(
              '${slices.length} match${slices.length == 1 ? '' : 'es'} for "$q"',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF64748B),
              ),
            ),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => context.push(
            '/home/breakdown-more?tab=${subcategories ? 'subcategory' : 'category'}',
          ),
          icon: const Icon(Icons.open_in_new_rounded, size: 18),
          label: const Text('View full breakdown'),
        ),
      ],
    );
  }
}
