import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/design_system/hexa_ds_tokens.dart';
import '../../../../core/design_system/hexa_operational_tokens.dart';
import '../../../../core/json_coerce.dart';
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
    if (n == n.roundToDouble()) return n.round().toString();
    return n.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totalsAsync = ref.watch(stockTotalsProvider);
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
        onRetry: () => ref.invalidate(stockTotalsProvider),
      ),
      data: (totals) {
        final bags = coerceToDouble(totals['total_bags']);
        final kg = coerceToDouble(totals['total_kg']);
        final boxes = coerceToDouble(totals['total_boxes']);
        final tins = coerceToDouble(totals['total_tins']);
        final inv = invAsync.valueOrNull ?? HomeInventorySummary.empty;
        final items = inv.itemCount > 0
            ? inv.itemCount
            : coerceToInt(totals['total_items']);

        final purchasedBags = dash.snapshot.data.totalBags;
        final moved = (purchasedBags - bags).clamp(0, double.infinity).toDouble();
        final totalForBar = [
          purchasedBags,
          bags,
          moved,
        ].fold<double>(0, (a, b) => a + b);

        Widget miniStat(String label, String value) {
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
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                Text(
                  label,
                  style: HexaDsType.label(10, color: HexaDsColors.textMuted),
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
                      miniStat('Bags', _fmtNum(bags)),
                      miniStat('KG', _fmtNum(kg)),
                      miniStat('Boxes', _fmtNum(boxes)),
                      miniStat('Tins', _fmtNum(tins)),
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
                        Row(
                          children: [
                            Expanded(
                              child: _movementCell(
                                'Purchased this period',
                                '${_fmtNum(purchasedBags)} bags',
                              ),
                            ),
                            Expanded(
                              child: _movementCell(
                                'Current warehouse stock',
                                '${_fmtNum(bags)} bags',
                              ),
                            ),
                            Expanded(
                              child: _movementCell(
                                'Moved/sold',
                                '${_fmtNum(moved)} bags',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
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
                                  totalForBar == 0 ? 1 : bags / totalForBar,
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
