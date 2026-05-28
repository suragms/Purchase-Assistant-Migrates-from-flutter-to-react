import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/design_system/hexa_operational_tokens.dart';
import '../../../../core/providers/home_dashboard_provider.dart';
import '../../../../core/providers/home_owner_dashboard_providers.dart';
import '../../../../core/providers/stock_providers.dart';
import '../../../../core/providers/warehouse_alerts_provider.dart';
import '../../../../core/utils/unit_utils.dart';
import 'home_formatters.dart';

/// On-hand warehouse units + operational counts (quantity-first).
class HomeWarehouseSnapshotCard extends ConsumerWidget {
  const HomeWarehouseSnapshotCard({super.key});

  static String _qty(double n) =>
      n.abs() < 0.001 ? '' : formatStockQtyNumber(n);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invAsync = ref.watch(homeInventorySummaryProvider);
    final warehouse = ref.watch(warehouseAlertsProvider);
    final dashState = ref.watch(homeDashboardDataProvider);
    final status = ref.watch(stockStatusCountsProvider);

    return invAsync.when(
      loading: () => const Card(
        child: Padding(
          padding: EdgeInsets.all(HexaOp.cardPadding),
          child: LinearProgressIndicator(minHeight: 2),
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (inv) {
        final wh = warehouse.valueOrNull;
        final statusMap = status.valueOrNull ?? const {};
        final dash = dashState.snapshot.data;

        final units = <String>[];
        if (inv.bags > 0.001) units.add('${_qty(inv.bags)} Bags');
        if (inv.kg > 0.001) units.add('${_qty(inv.kg)} KG');
        if (inv.boxes > 0.001) units.add('${_qty(inv.boxes)} Boxes');
        if (inv.tins > 0.001) units.add('${_qty(inv.tins)} Tins');

        final low = (statusMap['low'] as num?)?.toInt() ?? 0;
        final critical = (statusMap['critical'] as num?)?.toInt() ?? 0;
        final mismatch = wh?.pendingVerifications ?? 0;
        final pendingDel = dash.pendingDeliveryCount;
        final outN = (statusMap['out'] as num?)?.toInt() ?? 0;

        final ops = <String>[
          if (low + critical > 0) 'Low: ${low + critical}',
          if (outN > 0) 'Out: $outN',
          if (mismatch > 0) 'Mismatch: $mismatch',
          if (pendingDel > 0) 'Pending delivery: $pendingDel',
        ];

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
                  Text('Warehouse snapshot', style: HexaOp.cardTitle(context)),
                  const SizedBox(height: 2),
                  Text(
                    'On-hand snapshot · live warehouse totals',
                    style: HexaOp.caption(context),
                  ),
                  const SizedBox(height: 8),
                  if (units.isNotEmpty)
                    Text(
                      units.join(' · '),
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                        height: 1.25,
                      ),
                    )
                  else
                    Text(
                      'No on-hand units recorded',
                      style: HexaOp.caption(context),
                    ),
                  if (ops.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      ops.join(' · '),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                  if (inv.totalValueInr > 0.01) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Stock value ${homeInr(inv.totalValueInr)} · ${inv.itemCount} items',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF94A3B8),
                        fontWeight: FontWeight.w600,
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
