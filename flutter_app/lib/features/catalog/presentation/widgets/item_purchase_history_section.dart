import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/catalog/item_trade_history.dart';
import '../../../../core/providers/trade_purchases_provider.dart';
import '../../../../core/router/post_auth_route.dart';
import '../../../../core/auth/session_notifier.dart';
import '../../../../core/widgets/friendly_load_error.dart';
import '../../../../core/design_system/hexa_operational_tokens.dart';
import '../../../../core/utils/unit_utils.dart';

enum ItemPurchaseRange { d7, d30, d90, d365, all }

class ItemPurchaseHistorySection extends ConsumerStatefulWidget {
  const ItemPurchaseHistorySection({
    super.key,
    required this.itemId,
    required this.itemName,
  });

  final String itemId;
  final String itemName;

  @override
  ConsumerState<ItemPurchaseHistorySection> createState() =>
      _ItemPurchaseHistorySectionState();
}

class _ItemPurchaseHistorySectionState
    extends ConsumerState<ItemPurchaseHistorySection> {
  ItemPurchaseRange _range = ItemPurchaseRange.d30;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final isStaff = session != null && sessionIsStaff(session);
    final hideFinancials = session != null && !sessionCanSeeFinancials(session);

    final purchasesAsync = ref.watch(tradePurchasesCatalogIntelParsedProvider);

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(HexaOp.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child:
                      Text('Purchase history', style: HexaOp.cardTitle(context)),
                ),
                TextButton(
                  onPressed: () => context.push(
                    '/catalog/item/${widget.itemId}/purchase-history',
                  ),
                  child: const Text('Open'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _rangeChips(),
            const SizedBox(height: 8),
            purchasesAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, __) => FriendlyLoadError(
                message: 'Could not load purchase history',
                onRetry: () =>
                    ref.invalidate(tradePurchasesCatalogIntelProvider),
              ),
              data: (purchases) {
                final rows = itemTradeHistoryRows(
                  purchases,
                  widget.itemId,
                  catalogItemName: widget.itemName,
                );
                final filtered = _applyRange(rows);
                if (filtered.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.fromLTRB(12, 14, 12, 14),
                    child: Text(
                      'No purchases found in this range.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                  );
                }
                final take = filtered.take(12).toList();
                return Column(
                  children: [
                    for (var i = 0; i < take.length; i++) ...[
                      _PurchaseCard(
                        row: take[i],
                        hideFinancials: hideFinancials || isStaff,
                      ),
                      if (i < take.length - 1)
                        const SizedBox(height: 8),
                    ],
                    if (filtered.length > take.length) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Showing ${take.length} of ${filtered.length}. Use “Open” for the full list.',
                        style: HexaOp.caption(context),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  List<ItemTradeHistoryRow> _applyRange(List<ItemTradeHistoryRow> rows) {
    final now = DateTime.now();
    final since = switch (_range) {
      ItemPurchaseRange.d7 => now.subtract(const Duration(days: 7)),
      ItemPurchaseRange.d30 => now.subtract(const Duration(days: 30)),
      ItemPurchaseRange.d90 => now.subtract(const Duration(days: 90)),
      ItemPurchaseRange.d365 => now.subtract(const Duration(days: 365)),
      ItemPurchaseRange.all => null,
    };
    if (since == null) return rows;
    return rows.where((r) => r.purchaseDate.isAfter(since)).toList();
  }

  Widget _rangeChips() {
    String label(ItemPurchaseRange r) => switch (r) {
          ItemPurchaseRange.d7 => '7d',
          ItemPurchaseRange.d30 => '30d',
          ItemPurchaseRange.d90 => '90d',
          ItemPurchaseRange.d365 => '365d',
          ItemPurchaseRange.all => 'All',
        };
    final opts = ItemPurchaseRange.values;
    return Wrap(
      spacing: 8,
      children: [
        for (final o in opts)
          ChoiceChip(
            label: Text(label(o)),
            selected: _range == o,
            onSelected: (_) => setState(() => _range = o),
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }
}

class _PurchaseCard extends StatelessWidget {
  const _PurchaseCard({required this.row, required this.hideFinancials});

  final ItemTradeHistoryRow row;
  final bool hideFinancials;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    );
    final df = DateFormat('dd MMM yyyy');
    final qty = row.line.qty;
    final unit = row.line.unit.toUpperCase();
    final title = row.supplierName.trim().isNotEmpty ? row.supplierName : 'Supplier';
    final broker = row.brokerName?.trim();

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => context.push('/purchase/detail/${row.purchaseId}'),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                    ),
                  ),
                  Text(
                    df.format(row.purchaseDate),
                    style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                [
                  if (row.humanId.trim().isNotEmpty) row.humanId,
                  if (broker != null && broker.isNotEmpty) broker,
                ].join('  •  '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${formatStockQtyNumber(qty)} $unit',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                    ),
                  ),
                  if (!hideFinancials) ...[
                    Text(
                      row.rateLabel(),
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      money.format(row.lineTotal),
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

