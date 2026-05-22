import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/providers/stock_providers.dart';
import '../../../core/router/post_auth_route.dart';
import '../../../core/utils/unit_utils.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../../../core/widgets/list_skeleton.dart';
import '../../../core/widgets/warehouse_compact_card.dart';

/// Per-item warehouse drill-down: period purchases, variance, recent activity.
class StockItemIntelligencePage extends ConsumerWidget {
  const StockItemIntelligencePage({super.key, required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(stockItemIntelligenceProvider(itemId));
    final session = ref.watch(sessionProvider);
    final hideFinancials = session != null && !sessionCanSeeFinancials(session);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock intelligence'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: async.when(
        loading: () => const ListSkeleton(rowCount: 5, rowHeight: 72),
        error: (_, __) => FriendlyLoadError(
          message: 'Could not load item intelligence',
          onRetry: () => ref.invalidate(stockItemIntelligenceProvider(itemId)),
        ),
        data: (m) {
          final name = m['name']?.toString() ?? 'Item';
          final code = m['item_code']?.toString();
          final cur = double.tryParse(m['current_stock']?.toString() ?? '') ?? 0;
          final purchased =
              double.tryParse(m['period_purchased_qty']?.toString() ?? '') ?? 0;
          final variance =
              double.tryParse(m['period_variance_qty']?.toString() ?? '') ?? 0;
          final unit = m['unit']?.toString() ?? '';
          final verify = m['needs_verification'] == true;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              WarehouseCompactCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: HexaDsType.heading(16),
                    ),
                    if (code != null && code.isNotEmpty)
                      Text('Code $code', style: HexaDsType.body(12)),
                    const SizedBox(height: 8),
                    Text(
                      'On hand: ${stockDisplayPrimary(cur, unit)}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      'Period purchased: ${stockDisplayPrimary(purchased, unit)}',
                      style: HexaDsType.body(13),
                    ),
                    Text(
                      'Variance: ${variance >= 0 ? '+' : ''}${stockDisplayPrimary(variance, unit)}',
                      style: HexaDsType.body(13),
                    ),
                    if (verify)
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text(
                          'Needs verification',
                          style: TextStyle(
                            color: Color(0xFFE65100),
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text('Recent purchases', style: HexaDsType.heading(14)),
              const SizedBox(height: 8),
              ..._purchaseTiles(m['recent_purchases'], hideFinancials),
              const SizedBox(height: 12),
              Text('Recent adjustments', style: HexaDsType.heading(14)),
              const SizedBox(height: 8),
              ..._adjustmentTiles(m['recent_adjustments']),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _purchaseTiles(dynamic raw, bool hideFinancials) {
    if (raw is! List || raw.isEmpty) {
      return [
        const Text('No purchases in this period', style: TextStyle(fontSize: 12)),
      ];
    }
    return [
      for (final e in raw)
        if (e is Map)
          ListTile(
            dense: true,
            title: Text(e['supplier_name']?.toString() ?? 'Supplier'),
            subtitle: Text(
              '${e['qty'] ?? '—'} ${e['unit'] ?? ''}'
              '${hideFinancials ? '' : ' · ${e['rate'] ?? '—'}'}',
            ),
          ),
    ];
  }

  List<Widget> _adjustmentTiles(dynamic raw) {
    if (raw is! List || raw.isEmpty) {
      return [
        const Text('No adjustments', style: TextStyle(fontSize: 12)),
      ];
    }
    final df = DateFormat('MMM d, y');
    return [
      for (final e in raw)
        if (e is Map)
          ListTile(
            dense: true,
            title: Text(
              '${e['old_qty']} → ${e['new_qty']} (${e['adjustment_type']})',
            ),
            subtitle: Text(
              e['updated_at'] != null
                  ? df.format(DateTime.parse(e['updated_at'].toString()).toLocal())
                  : '',
            ),
          ),
    ];
  }
}
