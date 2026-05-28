import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/hexa_ds_tokens.dart';
import '../../../../core/design_system/hexa_operational_tokens.dart';
import '../../../../core/json_coerce.dart';
import '../../../../core/providers/app_period_provider.dart';
import '../../../../core/providers/stock_providers.dart';
import '../../../../core/theme/hexa_colors.dart';
import '../../../../core/widgets/friendly_load_error.dart';

/// Purchased this month vs current on-hand (bags-first diff).
class StaffWarehouseDifferenceCard extends ConsumerWidget {
  const StaffWarehouseDifferenceCard({super.key});

  static String _fmtNum(double n) {
    final rounded = n.roundToDouble();
    if ((n - rounded).abs() < 0.001) return rounded.round().toString();
    return n.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onHandAsync = ref.watch(stockOnHandTotalsProvider);
    final periodAsync = ref.watch(stockTotalsProvider(AppPeriod.month));

    if (onHandAsync.isLoading || periodAsync.isLoading) {
      return const SizedBox(
        height: 56,
        child: Center(child: LinearProgressIndicator(minHeight: 2)),
      );
    }
    if (onHandAsync.hasError || periodAsync.hasError) {
      return FriendlyLoadError(
        message: 'Could not load warehouse comparison',
        onRetry: () {
          ref.invalidate(stockOnHandTotalsProvider);
          ref.invalidate(stockTotalsProvider(AppPeriod.month));
        },
      );
    }

    final onHand = onHandAsync.valueOrNull ?? {};
    final period = periodAsync.valueOrNull ?? {};
    final purchasedBags = coerceToDouble(period['total_bags']);
    final currentBags = coerceToDouble(onHand['total_bags']);
    if (purchasedBags <= 0 && currentBags <= 0) {
      return const SizedBox.shrink();
    }

    final diff = currentBags - purchasedBags;
    final diffLabel = diff >= 0 ? '+${_fmtNum(diff)}' : _fmtNum(diff);

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(HexaOp.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Warehouse difference',
              style: HexaDsType.heading(13),
            ),
            const SizedBox(height: 2),
            Text(
              'This month · bags',
              style: HexaDsType.body(11, color: HexaDsColors.textMuted),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _Col(
                    label: 'Purchased',
                    value: _fmtNum(purchasedBags),
                  ),
                ),
                Expanded(
                  child: _Col(
                    label: 'On hand',
                    value: _fmtNum(currentBags),
                  ),
                ),
                Expanded(
                  child: _Col(
                    label: 'Difference',
                    value: diffLabel,
                    valueColor: diff < 0
                        ? HexaColors.loss
                        : (diff > 0 ? const Color(0xFF3B6D11) : null),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Col extends StatelessWidget {
  const _Col({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 16,
            color: valueColor,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: HexaDsType.label(10, color: HexaDsColors.textMuted),
        ),
      ],
    );
  }
}
