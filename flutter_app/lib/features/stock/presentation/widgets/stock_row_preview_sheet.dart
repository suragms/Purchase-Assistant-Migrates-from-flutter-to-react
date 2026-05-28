import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/json_coerce.dart';
import '../../../../core/providers/stock_providers.dart';
import '../../../../core/utils/unit_utils.dart';

/// Quick row drill-down: stock totals + recent bills before full navigation.
Future<void> showStockRowPreviewSheet({
  required BuildContext context,
  required WidgetRef ref,
  required Map<String, dynamic> item,
  required bool isStaffMode,
}) async {
  final id = item['id']?.toString() ?? '';
  if (id.isEmpty) return;

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      return _StockRowPreviewBody(
        itemId: id,
        item: item,
        isStaffMode: isStaffMode,
      );
    },
  );
}

class _StockRowPreviewBody extends ConsumerWidget {
  const _StockRowPreviewBody({
    required this.itemId,
    required this.item,
    required this.isStaffMode,
  });

  final String itemId;
  final Map<String, dynamic> item;
  final bool isStaffMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final intel = ref.watch(stockItemIntelligenceProvider(itemId));
    final name = item['name']?.toString() ?? 'Item';
    final purchased = coerceToDouble(item['period_purchased_qty']);
    final current = coerceToDouble(item['current_stock']);
    final stockUnit =
        item['stock_unit']?.toString() ?? item['unit']?.toString() ?? 'piece';
    final kgPerBag = coerceToDouble(item['default_kg_per_bag']);
    final stockKg = coerceToDouble(item['current_stock_kg']);
    final nowDual = dualStockDisplay(
      qty: current,
      unit: stockUnit,
      kgPerBag: kgPerBag > 0 ? kgPerBag : null,
      currentStockKg: stockKg > 0 ? stockKg : null,
    );
    final moved = coerceToDouble(
      item['ledger_variance_qty'] ?? item['period_variance_qty'],
    );
    final hid = item['last_purchase_human_id']?.toString() ?? '';
    final delivered = item['last_purchase_delivered'];
    final pending = delivered == false && hid.isNotEmpty;

    return SafeArea(
      top: false,
      child: Padding(
        padding:
            EdgeInsets.fromLTRB(16, 8, 16, 16 + MediaQuery.paddingOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          Text(
            name,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
          ),
          if (pending) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Pending delivery · $hid',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFE65100),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              _metric(
                'Buy',
                stockDisplayPrimary(purchased, stockUnit),
              ),
              _metric('Now', nowDual.primary, subtitle: nowDual.secondary),
              _metric(
                'Var',
                moved.abs() > 0.0001 ? formatStockQtyNumber(moved) : '—',
              ),
            ],
          ),
          const SizedBox(height: 12),
          intel.when(
            loading: () => const LinearProgressIndicator(minHeight: 2),
            error: (_, __) => const Text(
              'Could not load recent bills',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            data: (data) {
              final raw = data['recent_purchases'];
              if (raw is! List || raw.isEmpty) {
                return const Text(
                  'No purchases in this period',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                );
              }
              final df = DateFormat('d MMM yyyy');
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Recent bills',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  for (final e in raw.take(3))
                    if (e is Map) ...[
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(
                          e['human_id']?.toString() ??
                              e['purchase_human_id']?.toString() ??
                              'Bill',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          [
                            if (e['purchase_date'] != null)
                              df.format(
                                DateTime.parse(
                                  e['purchase_date'].toString(),
                                ).toLocal(),
                              ),
                            e['supplier_name']?.toString() ?? '',
                          ].where((s) => s.isNotEmpty).join(' · '),
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: e['is_delivered'] == true
                            ? null
                            : const Text(
                                'Pending',
                                style: TextStyle(
                                  color: Color(0xFFE65100),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11,
                                ),
                              ),
                        onTap: () {
                          final pid = e['id']?.toString() ??
                              e['purchase_id']?.toString();
                          if (pid == null || pid.isEmpty) return;
                          Navigator.pop(context);
                          if (isStaffMode) {
                            context.push('/staff/purchase-history/$pid');
                          } else {
                            context.push('/purchase/detail/$pid');
                          }
                        },
                      ),
                    ],
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              context.push('/catalog/item/$itemId');
            },
            child: const Text('Open item & ledger'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () {
              Navigator.pop(context);
              context.push('/stock/intelligence/$itemId');
            },
            child: const Text('Full stock view'),
          ),
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, String value, {String? subtitle}) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
          Text(
            value,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
          ),
          if (subtitle != null && subtitle.isNotEmpty)
            Text(
              subtitle,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Colors.black45),
            ),
        ],
      ),
    );
  }
}
