import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/design_system/hexa_ds_tokens.dart';
import '../../../../core/design_system/hexa_operational_tokens.dart';
import '../../../../core/json_coerce.dart';
import '../../../../core/providers/app_period_provider.dart';
import '../../../../core/providers/home_dashboard_provider.dart';
import '../../../../core/providers/home_owner_dashboard_providers.dart';
import '../../../../core/providers/stock_providers.dart';
import '../../../../core/theme/hexa_colors.dart';
import '../../../../core/widgets/friendly_load_error.dart';
import 'home_formatters.dart';
import 'home_warehouse_analytics_sheet.dart';

/// Owner home: compact warehouse stock overview + movement comparison.
class HomeStockTotalsCard extends ConsumerWidget {
  const HomeStockTotalsCard({super.key, this.lastUpdatedAt});

  final DateTime? lastUpdatedAt;

  static String _fmtNum(double n) {
    final rounded = n.roundToDouble();
    if ((n - rounded).abs() < 0.001) return rounded.round().toString();
    return n.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appPeriod = appPeriodFromHomePeriod(ref.watch(homePeriodProvider));
    final totalsAsync = ref.watch(stockTotalsProvider(appPeriod));
    final invAsync = ref.watch(homeInventorySummaryProvider);
    final dash = ref.watch(homeDashboardDataProvider);

    return totalsAsync.when(
      loading: () => const Card(
        child: Padding(
          padding: EdgeInsets.all(HexaOp.cardPadding),
          child: LinearProgressIndicator(minHeight: 2),
        ),
      ),
      error: (_, __) => FriendlyLoadError(
        message: 'Could not load stock totals',
        onRetry: () => ref.invalidate(stockTotalsProvider(appPeriod)),
      ),
      data: (totals) {
        final onHandBags = coerceToDouble(totals['total_bags']);
        final periodData = dash.snapshot.data;
        final bags = periodData.totalBags;
        final kg = periodData.totalKg;
        final boxes = periodData.totalBoxes;
        final tins = periodData.totalTins;
        final inv = invAsync.valueOrNull ?? HomeInventorySummary.empty;
        final items = inv.itemCount > 0
            ? inv.itemCount
            : coerceToInt(totals['total_items']);

        final period = ref.watch(homePeriodProvider);
        final purchasedBags = periodData.totalBags;
        final moved =
            (purchasedBags - onHandBags).clamp(0, double.infinity).toDouble();
        final movementCells = <Widget>[];
        if (purchasedBags > 0) {
          movementCells.add(
            Expanded(
              child: _movementCell(
                'Purchased (${period.label})',
                '${_fmtNum(purchasedBags)} bags',
              ),
            ),
          );
        }
        if (bags > 0) {
          movementCells.add(
            Expanded(
              child: _movementCell(
                'On hand now',
                '${_fmtNum(onHandBags)} bags',
              ),
            ),
          );
        }
        if (moved > 0) {
          movementCells.add(
            Expanded(
              child: _movementCell(
                'Moved/sold',
                '${_fmtNum(moved)} bags',
              ),
            ),
          );
        }
        final totalForBar = [
          purchasedBags,
          onHandBags,
          moved,
        ].fold<double>(0, (a, b) => a + b);

        Widget miniStat(String label, String value, Color color) {
          return Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding: const EdgeInsets.symmetric(vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
            child: Column(
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 24,
                    color: color,
                    letterSpacing: -0.5,
                    height: 1.1,
                  ),
                  textAlign: TextAlign.center,
                ),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10,
                    color: HexaDsColors.textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            ),
          );
        }

        return Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => showWarehouseAnalyticsSheet(context: context, ref: ref),
            child: Padding(
              padding: const EdgeInsets.all(HexaOp.cardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text(
                        'Warehouse Stock Overview',
                        style: HexaOp.cardTitle(context),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Open Reports analytics',
                        icon: const Icon(Icons.analytics_outlined, size: 20),
                        onPressed: () => context.push('/reports?tab=subcategories'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      miniStat('Bags', _fmtNum(bags), const Color(0xFF3B6D11)),
                      miniStat('KG', _fmtNum(kg), const Color(0xFF185FA5)),
                      if (boxes > 0)
                        miniStat('Boxes', _fmtNum(boxes), const Color(0xFF6D4C1B)),
                      if (tins > 0)
                        miniStat('Tins', _fmtNum(tins), const Color(0xFF7C3D3D)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Total stock value: ${homeInr(inv.totalValueInr)}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        'Items tracked: $items',
                        style: HexaOp.caption(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Last updated: ${homeRefreshAgo(lastUpdatedAt)}',
                    style: HexaOp.caption(context),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: HexaColors.brandPrimary.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        if (movementCells.isNotEmpty) ...[
                          Row(children: movementCells),
                          const SizedBox(height: 8),
                        ],
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: SizedBox(
                            height: 8,
                            child: Row(
                              children: [
                                _barSegment(
                                  totalForBar == 0 ? 1 : purchasedBags / totalForBar,
                                  const Color(0xFF1565C0),
                                ),
                                _barSegment(
                                  totalForBar == 0 ? 1 : onHandBags / totalForBar,
                                  const Color(0xFF2E7D32),
                                ),
                                _barSegment(
                                  totalForBar == 0 ? 1 : moved / totalForBar,
                                  const Color(0xFFE65100),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.info_outline, size: 14, color: Color(0xFF64748B)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Difference may include sales, transfers, wastage or adjustments.',
                          style: HexaOp.caption(context),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _movementCell(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
          textAlign: TextAlign.center,
        ),
        Text(
          label,
          style: HexaDsType.label(10, color: HexaDsColors.textMuted),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _barSegment(double flex, Color color) {
    return Expanded(
      flex: (flex * 1000).round().clamp(1, 1000).toInt(),
      child: ColoredBox(color: color),
    );
  }
}
