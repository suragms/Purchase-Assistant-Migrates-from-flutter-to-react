import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/design_system/hexa_operational_tokens.dart';
import '../../../../core/json_coerce.dart';
import '../../../../core/providers/home_owner_dashboard_providers.dart';
import '../../../../core/providers/stock_providers.dart';
import '../../../../core/utils/unit_utils.dart';
import '../../../../core/widgets/section_inline_error.dart';
import 'home_bold_metrics_line.dart';
import 'home_formatters.dart';
import 'home_recent_changes_section.dart' show HomeSectionSkeleton;

/// On-hand warehouse units + operational counts (quantity-first).
class HomeWarehouseSnapshotCard extends ConsumerWidget {
  const HomeWarehouseSnapshotCard({super.key});

  static String _qty(double n) =>
      n.abs() < 0.001 ? '' : formatStockQtyNumber(n);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invAsync = ref.watch(homeInventorySummaryProvider);
    final status = ref.watch(stockStatusCountsProvider);

    return invAsync.when(
      loading: () => const Card(
        child: Padding(
          padding: EdgeInsets.all(HexaOp.cardPadding),
          child: HomeSectionSkeleton(rows: 2),
        ),
      ),
      error: (_, __) => Card(
        child: SectionInlineError(
          message: 'Could not load warehouse snapshot',
          onRetry: () {
            ref.invalidate(homeInventorySummaryProvider);
            ref.invalidate(stockStatusCountsProvider);
          },
        ),
      ),
      data: (inv) {
        final statusMap = status.valueOrNull ?? const {};
        final outN = coerceToInt(statusMap['out']);

        final unitSegments = <HomeBoldMetricSegment>[];
        if (inv.bags > 0.001) {
          unitSegments.add(HomeBoldMetricSegment(
            value: _qty(inv.bags),
            unit: 'Bags',
            color: HomeMetricColors.bags,
          ));
        }
        if (inv.kg > 0.001) {
          unitSegments.add(HomeBoldMetricSegment(
            value: _qty(inv.kg),
            unit: 'KG',
            color: HomeMetricColors.kg,
          ));
        }
        if (inv.boxes > 0.001) {
          unitSegments.add(HomeBoldMetricSegment(
            value: _qty(inv.boxes),
            unit: 'Boxes',
            color: HomeMetricColors.boxes,
          ));
        }
        if (inv.tins > 0.001) {
          unitSegments.add(HomeBoldMetricSegment(
            value: _qty(inv.tins),
            unit: 'Tins',
            color: HomeMetricColors.tins,
          ));
        }

        return Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: InkWell(
            onTap: () => context.go('/stock'),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(HexaOp.cardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Warehouse snapshot',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'On-hand snapshot · live warehouse totals',
                    style: HexaOp.caption(context),
                  ),
                  const SizedBox(height: 10),
                  HomeBoldMetricsLine(segments: unitSegments, fontSize: 18),
                  if (outN > 0) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Out of stock: $outN items',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFDC2626),
                      ),
                    ),
                  ],
                  if (inv.totalValueInr > 0.01) ...[
                    const SizedBox(height: 8),
                    Text.rich(
                      TextSpan(
                        children: [
                          const TextSpan(
                            text: 'Stock value ',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: HomeMetricColors.meta,
                            ),
                          ),
                          TextSpan(
                            text: homeInr(inv.totalValueInr),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: HomeMetricColors.amount,
                            ),
                          ),
                          TextSpan(
                            text: ' · ${inv.itemCount} items',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: HomeMetricColors.meta,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
