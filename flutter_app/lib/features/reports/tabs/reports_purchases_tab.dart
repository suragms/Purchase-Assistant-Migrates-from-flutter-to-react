import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/models/trade_purchase_models.dart';
import '../shell/reports_layout.dart';
import '../widgets/reports_purchase_row_card.dart';

/// Virtualized purchase cards list.
class ReportsPurchasesTab extends StatelessWidget {
  const ReportsPurchasesTab({
    super.key,
    required this.purchases,
    required this.onLoadMore,
    required this.hasMore,
    this.isLoading = false,
  });

  final List<TradePurchase> purchases;
  final VoidCallback? onLoadMore;
  final bool hasMore;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    if (isLoading && purchases.isEmpty) {
      return ListView.builder(
        itemCount: 6,
        itemExtent: kReportsRowExtent,
        itemBuilder: (_, __) => const ReportsPurchaseRowCardSkeleton(),
      );
    }
    if (purchases.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: Text('No purchases in this period.')),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: purchases.length + (hasMore ? 1 : 0),
      itemBuilder: (context, i) {
        if (hasMore && i == purchases.length) {
          return TextButton(
            onPressed: onLoadMore,
            child: const Text('Load more'),
          );
        }
        final p = purchases[i];
        return ReportsPurchaseRowCard(
          purchase: p,
          onTap: () => context.push('/reports/purchase/${p.id}', extra: p),
        );
      },
    );
  }
}
