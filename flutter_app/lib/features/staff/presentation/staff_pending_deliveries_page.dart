import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/models/trade_purchase_models.dart';
import '../../../core/providers/staff_home_providers.dart';
import '../../../core/providers/trade_purchases_provider.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/utils/unit_utils.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../../../core/widgets/list_skeleton.dart';

class StaffPendingDeliveriesPage extends ConsumerWidget {
  const StaffPendingDeliveriesPage({super.key});

  static String _bagsQtySummary(TradePurchase p) {
    final byUnit = <String, double>{};
    for (final l in p.lines) {
      final u = l.unit.trim().toUpperCase();
      byUnit[u] = (byUnit[u] ?? 0) + l.qty;
    }
    if (byUnit.isEmpty) return '—';
    return byUnit.entries
        .map((e) => '${formatStockQtyNumber(e.value)} ${e.key}')
        .join(' · ');
  }

  static double _totalLineQty(TradePurchase p) {
    var sum = 0.0;
    for (final l in p.lines) {
      sum += l.qty;
    }
    return sum;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingAsync = ref.watch(staffPendingDeliveriesProvider);
    final total = pendingAsync.valueOrNull?.length ?? 0;

    return Scaffold(
      backgroundColor: HexaColors.brandBackground,
      appBar: AppBar(
        title: Text(
          total > 0 ? 'Pending deliveries ($total)' : 'Pending deliveries',
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: HexaColors.brandPrimary,
      ),
      body: pendingAsync.when(
        loading: () => const ListSkeleton(rowCount: 6),
        error: (_, __) => FriendlyLoadError(
          message: 'Could not load pending deliveries',
          onRetry: () {
            ref.invalidate(staffPendingDeliveriesProvider);
            ref.invalidate(tradePurchasesListProvider);
          },
        ),
        data: (rows) {
          if (rows.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No pending deliveries right now.',
                  textAlign: TextAlign.center,
                  style: HexaDsType.body(15, color: HexaDsColors.textMuted),
                ),
              ),
            );
          }
          final delivered = ref
                  .watch(tradePurchasesParsedProvider)
                  .valueOrNull
                  ?.where((p) => p.isDelivered)
                  .length ??
              0;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$total pending · $delivered delivered',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE65100).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '$total waiting',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 11,
                            color: Color(0xFFE65100),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                _PendingDeliveryTile(
                  index: i + 1,
                  total: rows.length,
                  purchase: rows[i],
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _PendingDeliveryTile extends StatelessWidget {
  const _PendingDeliveryTile({
    required this.index,
    required this.total,
    required this.purchase,
  });

  final int index;
  final int total;
  final TradePurchase purchase;

  @override
  Widget build(BuildContext context) {
    final p = purchase;
    final qty = StaffPendingDeliveriesPage._totalLineQty(p);
    final bagsLine = StaffPendingDeliveriesPage._bagsQtySummary(p);
    final days = DateTime.now().difference(p.purchaseDate).inDays;

    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: HexaColors.brandBorder),
      ),
      child: ListTile(
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: HexaColors.brandPrimary.withValues(alpha: 0.1),
          child: Text(
            '$index',
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 12,
              color: HexaColors.brandPrimary,
            ),
          ),
        ),
        title: Text(
          p.supplierName?.trim().isNotEmpty == true
              ? p.supplierName!
              : 'Supplier',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${p.humanId} · ${DateFormat('d MMM').format(p.purchaseDate)}'
              '${days > 0 ? ' · $days d pending' : ''}',
            ),
            const SizedBox(height: 2),
            Text(
              bagsLine,
              style: HexaDsType.label(11, color: HexaDsColors.textMuted),
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '$index/$total',
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 11,
                color: Color(0xFF64748B),
              ),
            ),
            Text(
              '${qty == qty.roundToDouble() ? qty.round() : qty.toStringAsFixed(1)} qty',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
        onTap: () => context.push('/staff/receive/${p.id}'),
      ),
    );
  }
}
