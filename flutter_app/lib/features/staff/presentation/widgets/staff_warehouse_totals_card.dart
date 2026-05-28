import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/design_system/hexa_ds_tokens.dart';
import '../../../../core/design_system/hexa_operational_tokens.dart';
import '../../../../core/json_coerce.dart';
import '../../../../core/providers/stock_providers.dart';
import '../../../../core/theme/hexa_colors.dart';
import '../../../../core/widgets/friendly_load_error.dart';

/// Staff home: on-hand warehouse totals (bags / kg / boxes / tins).
class StaffWarehouseTotalsCard extends ConsumerWidget {
  const StaffWarehouseTotalsCard({super.key});

  static String _fmtNum(double n) {
    final rounded = n.roundToDouble();
    if ((n - rounded).abs() < 0.001) return rounded.round().toString();
    return n.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onHandAsync = ref.watch(stockOnHandTotalsProvider);

    return onHandAsync.when(
      loading: () => const Card(
        child: Padding(
          padding: EdgeInsets.all(HexaOp.cardPadding),
          child: LinearProgressIndicator(minHeight: 2),
        ),
      ),
      error: (_, __) => FriendlyLoadError(
        message: 'Could not load warehouse totals',
        onRetry: () => ref.invalidate(stockOnHandTotalsProvider),
      ),
      data: (onHand) {
        final bags = coerceToDouble(onHand['total_bags']);
        final kg = coerceToDouble(onHand['total_kg']);
        final boxes = coerceToDouble(onHand['total_boxes']);
        final tins = coerceToDouble(onHand['total_tins']);

        Widget unitTile(String label, double value, Color color) {
          return Expanded(
            child: Material(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                onTap: () => context.push('/staff/stock'),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 44),
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: HexaColors.brandBorder),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _fmtNum(value),
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 22,
                          color: color,
                        ),
                      ),
                      Text(
                        label,
                        style: HexaDsType.label(11, color: HexaDsColors.textMuted),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        return Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              children: [
                unitTile('Bags', bags, HexaColors.brandPrimary),
                const SizedBox(width: 6),
                unitTile('KG', kg, const Color(0xFF1565C0)),
                const SizedBox(width: 6),
                unitTile('Boxes', boxes, const Color(0xFF6A1B9A)),
                const SizedBox(width: 6),
                unitTile('Tins', tins, const Color(0xFFE65100)),
              ],
            ),
          ),
        );
      },
    );
  }
}
