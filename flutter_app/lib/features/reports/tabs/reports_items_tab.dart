import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/navigation/resolve_catalog_item_id.dart';
import '../../../core/models/trade_purchase_models.dart';
import '../../../core/reporting/trade_report_aggregate.dart';
import '../reporting/reports_item_metrics.dart';
import '../shell/reports_layout.dart';
import '../widgets/reports_item_row_card.dart';

/// Virtualized items list with 72–80px row cards.
class ReportsItemsTab extends ConsumerWidget {
  const ReportsItemsTab({
    super.key,
    required this.rows,
    required this.merged,
    required this.onLoadMore,
    required this.hasMore,
    this.isLoading = false,
  });

  final List<TradeReportItemRow> rows;
  final List<TradePurchase> merged;
  final VoidCallback? onLoadMore;
  final bool hasMore;
  final bool isLoading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (isLoading && rows.isEmpty) {
      return ListView.builder(
        itemCount: 8,
        itemExtent: kReportsRowExtent,
        itemBuilder: (_, __) => const _SkeletonRow(),
      );
    }
    if (rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: Text('No items in this period.')),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: rows.length + (hasMore ? 1 : 0),
      itemExtent: hasMore ? null : kReportsRowExtent,
      itemBuilder: (context, i) {
        if (hasMore && i == rows.length) {
          return TextButton(
            onPressed: onLoadMore,
            child: const Text('Load more'),
          );
        }
        final r = rows[i];
        final rateLine = reportItemRateArrowLine(merged, r.key);
        return ReportsItemRowCard(
          row: r,
          rateLine: rateLine,
          purchaseCount: r.dealIds.length,
          onTap: () => _openItemReport(context, ref, r),
        );
      },
    );
  }

  Future<void> _openItemReport(
    BuildContext context,
    WidgetRef ref,
    TradeReportItemRow r,
  ) async {
    final cid = await resolveCatalogItemId(ref, itemName: r.name);
    if (!context.mounted) return;
    if (cid != null && cid.isNotEmpty) {
      context.push(
        '/reports/item/$cid?name=${Uri.encodeComponent(r.name)}',
      );
    } else {
      context.push(
        '/reports/item-detail?k=${Uri.encodeComponent(r.key)}&n=${Uri.encodeComponent(r.name)}',
      );
    }
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  height: 12,
                  width: double.infinity,
                  color: Colors.grey.shade200,
                ),
                const SizedBox(height: 6),
                Container(
                  height: 10,
                  width: 120,
                  color: Colors.grey.shade100,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
