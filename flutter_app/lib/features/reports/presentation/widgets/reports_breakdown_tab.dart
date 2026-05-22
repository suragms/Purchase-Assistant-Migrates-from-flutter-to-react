import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/json_coerce.dart';
import '../../../../core/providers/analytics_breakdown_providers.dart';
import '../../../../core/providers/home_dashboard_provider.dart';
import '../../../../core/reporting/trade_report_aggregate.dart';
import '../../widgets/bi/breakdown_legend_list.dart';
import '../../widgets/bi/reports_bi_slice.dart';
import '../../widgets/bi/warehouse_ring_section.dart';
import '../reports_category_drill_page.dart';
import '../reports_subcategory_drill_page.dart';

/// Categories or subcategories tab with ring + list.
class ReportsBreakdownTab extends ConsumerWidget {
  const ReportsBreakdownTab({
    super.key,
    required this.subcategories,
    required this.agg,
  });

  final bool subcategories;
  final TradeReportAgg agg;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final typesAsync = ref.watch(analyticsTypesTableProvider);
    final catsAsync = ref.watch(analyticsCategoriesTableProvider);
    final dash = ref.watch(homeDashboardDataProvider).snapshot.data;

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
          return _body(context, slices, 'Subcategory spend');
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
        return _body(context, slices, 'Category spend');
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

  Widget _body(BuildContext context, List<ReportsBiSlice> slices, String label) {
    if (slices.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No purchases in selected period.\nTry changing date range.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.black54),
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        WarehouseRingSection(
          slices: slices,
          centerLabel: label,
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
        const SizedBox(height: 8),
        BreakdownLegendList(
          slices: slices,
          onTapIndex: (i) {
            if (i < slices.length && slices[i].onTap != null) {
              slices[i].onTap!();
            }
          },
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
