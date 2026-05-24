import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/design_system/hexa_ds_tokens.dart';
import '../../../../core/design_system/hexa_operational_tokens.dart';
import '../../../../core/json_coerce.dart';
import '../../../../core/providers/home_breakdown_tab_providers.dart';
import '../../../../core/providers/home_owner_dashboard_providers.dart';
import '../../../../core/providers/stock_providers.dart';
import '../../../../core/theme/hexa_colors.dart';
import '../../../../core/widgets/friendly_load_error.dart';
import '../../../home/presentation/widgets/home_analytics_helpers.dart';
import '../../../home/presentation/widgets/home_formatters.dart';

/// Staff home: on-hand warehouse totals (bags / kg / boxes / tins).
class StaffWarehouseTotalsCard extends ConsumerWidget {
  const StaffWarehouseTotalsCard({super.key});

  static String _fmtNum(double n) {
    final rounded = n.roundToDouble();
    if ((n - rounded).abs() < 0.001) return rounded.round().toString();
    return n.toStringAsFixed(1);
  }

  void _openSubcategorySheet(BuildContext context, WidgetRef ref) {
    final dash = ref.read(homeOwnerPeriodDashboardProvider);
    final slices = homeAnalyticsSlicesForTab(
      tab: HomeBreakdownTab.subcategory,
      dash: dash,
      shell: null,
    );
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Subcategories', style: HexaDsType.heading(18)),
              const SizedBox(height: 8),
              if (slices.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    homeAnalyticsEmptyHint(HomeBreakdownTab.subcategory, dash),
                    textAlign: TextAlign.center,
                    style: HexaDsType.body(13, color: HexaDsColors.textMuted),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: slices.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final s = slices[i];
                      return ListTile(
                        title: Text(
                          s.title,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(s.subtitle),
                        trailing: Text(
                          homeInr(s.amount),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          ref.read(stockListQueryProvider.notifier).state =
                              ref.read(stockListQueryProvider).copyWith(
                                    subcategory: s.title,
                                    page: 1,
                                  );
                          context.push('/staff/stock');
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
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
                onTap: () => _openSubcategorySheet(context, ref),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Warehouse stock',
                  style: HexaDsType.heading(15),
                ),
                const SizedBox(height: 2),
                Text(
                  'On hand · tap for subcategories',
                  style: HexaDsType.body(11, color: HexaDsColors.textMuted),
                ),
                const SizedBox(height: 8),
                Row(
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
              ],
            ),
          ),
        );
      },
    );
  }
}
