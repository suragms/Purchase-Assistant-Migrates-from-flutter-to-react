import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/hexa_ds_tokens.dart';
import '../../../../core/design_system/hexa_operational_tokens.dart';
import '../../../../core/json_coerce.dart';
import '../../../../core/providers/home_dashboard_provider.dart';
import '../../../../core/providers/stock_providers.dart';
import '../../../../core/theme/hexa_colors.dart';
import '../../../../core/widgets/friendly_load_error.dart';

/// Owner home: compact on-hand totals + period movement row.
class HomeStockTotalsCard extends ConsumerWidget {
  const HomeStockTotalsCard({super.key});

  static String _fmtNum(double n) {
    if (n == n.roundToDouble()) return n.round().toString();
    return n.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totalsAsync = ref.watch(stockTotalsProvider);
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
        final items = coerceToInt(totals['total_items']);

        final purchasedBags = dash.snapshot.data.totalBags;
        final variance = bags - purchasedBags;
        final pct = purchasedBags > 0
            ? (variance.abs() / purchasedBags * 100)
            : 0.0;
        final alert = purchasedBags <= 0
            ? 'No purchases in period'
            : pct > 25
                ? 'High variance — audit'
                : pct > 10
                    ? 'Variance — check staff'
                    : 'Normal';
        final alertColor = purchasedBags <= 0
            ? HexaDsColors.textMuted
            : pct > 25
                ? HexaColors.loss
                : pct > 10
                    ? const Color(0xFFE65100)
                    : const Color(0xFF2E7D32);

        Widget miniStat(String label, String value) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Column(
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                Text(
                  label,
                  style: HexaDsType.label(10, color: HexaDsColors.textMuted),
                ),
              ],
            ),
          );
        }

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(HexaOp.cardPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Stock on hand',
                  style: HexaOp.cardTitle(context),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    miniStat('Bags', _fmtNum(bags)),
                    miniStat('Kg', _fmtNum(kg)),
                    miniStat('Box', _fmtNum(boxes)),
                    miniStat('Tin', _fmtNum(tins)),
                  ],
                ),
                Text(
                  '$items items',
                  style: HexaOp.caption(context),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: HexaColors.brandPrimary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _movementCell(
                          'Purchased',
                          '${_fmtNum(purchasedBags)} bags',
                        ),
                      ),
                      Expanded(
                        child: _movementCell(
                          'Current',
                          '${_fmtNum(bags)} bags',
                        ),
                      ),
                      Expanded(
                        child: _movementCell(
                          'Variance',
                          '${variance >= 0 ? '+' : ''}${_fmtNum(variance)}',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  alert,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: alertColor,
                  ),
                ),
              ],
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
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
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
}
