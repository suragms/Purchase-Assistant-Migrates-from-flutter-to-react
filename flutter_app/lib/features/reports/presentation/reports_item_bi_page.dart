import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../stock/presentation/stock_item_intelligence_page.dart';

/// Canonical item BI route: stock intelligence + purchase context.
class ReportsItemBiPage extends ConsumerWidget {
  const ReportsItemBiPage({
    super.key,
    required this.catalogItemId,
    this.itemName,
  });

  final String catalogItemId;
  final String? itemName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          itemName?.trim().isNotEmpty == true ? itemName!.trim() : 'Item analytics',
          style: const TextStyle(fontSize: 18),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            tooltip: 'Purchase history',
            icon: const Icon(Icons.receipt_long_outlined),
            onPressed: () {
              if (itemName != null && itemName!.trim().isNotEmpty) {
                final encK = Uri.encodeComponent(catalogItemId);
                final encN = Uri.encodeComponent(itemName!.trim());
                context.push('/reports/item-detail?k=$encK&n=$encN');
              }
            },
          ),
        ],
      ),
      body: StockItemIntelligencePage(
        itemId: catalogItemId,
        embedded: true,
        hideOwnerAnalytics: false,
      ),
    );
  }
}
