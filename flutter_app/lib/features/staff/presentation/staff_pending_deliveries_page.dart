import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/models/trade_purchase_models.dart';
import '../../../core/providers/staff_home_providers.dart';
import '../../../core/providers/trade_purchases_provider.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../../../core/widgets/list_skeleton.dart';

class StaffPendingDeliveriesPage extends ConsumerWidget {
  const StaffPendingDeliveriesPage({super.key});

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

    return Scaffold(
      backgroundColor: HexaColors.brandBackground,
      appBar: AppBar(
        title: const Text('Pending deliveries'),
        backgroundColor: Colors.transparent,
        foregroundColor: HexaColors.brandPrimary,
      ),
      body: pendingAsync.when(
        loading: () => const ListSkeleton(rowCount: 6),
        error: (_, __) => FriendlyLoadError(
          message: 'Could not load pending deliveries',
          onRetry: () => ref.invalidate(tradePurchasesListProvider),
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
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final p = rows[i];
              final qty = _totalLineQty(p);
              final days = DateTime.now().difference(p.purchaseDate).inDays;
              return Material(
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: HexaColors.brandBorder),
                ),
                child: ListTile(
                  leading: const Icon(
                    Icons.local_shipping_rounded,
                    color: HexaColors.brandPrimary,
                  ),
                  title: Text(
                    p.supplierName?.trim().isNotEmpty == true
                        ? p.supplierName!
                        : 'Supplier',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    '${p.humanId} · ${DateFormat('d MMM').format(p.purchaseDate)}'
                    '${days > 0 ? ' · $days d pending' : ''}',
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${qty == qty.roundToDouble() ? qty.round() : qty.toStringAsFixed(1)} qty',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        '${p.lines.length} line${p.lines.length == 1 ? '' : 's'}',
                        style: HexaDsType.label(10, color: HexaDsColors.textMuted),
                      ),
                    ],
                  ),
                  onTap: () => context.push('/staff/receive/${p.id}'),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
