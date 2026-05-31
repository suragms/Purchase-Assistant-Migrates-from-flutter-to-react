import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/models/trade_purchase_models.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/utils/unit_utils.dart';
import 'reports_breadcrumb_bar.dart';

String _inr0(num n) =>
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
        .format(n);

/// Purchase-centric report view inside Reports flow.
class ReportsPurchaseReportPage extends ConsumerWidget {
  const ReportsPurchaseReportPage({
    super.key,
    required this.purchaseId,
    this.initialPurchase,
  });

  final String purchaseId;
  final TradePurchase? initialPurchase;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = initialPurchase;
    if (p == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Purchase report')),
        body: const Center(child: Text('Purchase not found')),
      );
    }

    final df = DateFormat('d MMM yyyy');
    final supplier = p.supplierName ?? 'Supplier';

    return Scaffold(
      backgroundColor: HexaColors.brandBackground,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/reports?tab=purchase');
            }
          },
        ),
        title: Text(p.humanId),
        backgroundColor: HexaColors.brandBackground,
        foregroundColor: HexaColors.brandPrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          ReportsBreadcrumbBar(
            segments: [
              ('Reports', '/reports?tab=purchase'),
              (supplier, null),
              (p.humanId, null),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  supplier,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${df.format(p.purchaseDate)} · ${p.lines.length} lines',
                  style: const TextStyle(color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 8),
                Text(
                  _inr0(p.totalAmount.round()),
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                    color: HexaColors.brandPrimary,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          for (final line in p.lines)
            ListTile(
              title: Text(line.itemName),
              subtitle: Text(
                '${formatStockQtyForUnit(line.unit, line.qty)} ${line.unit.toUpperCase()}',
              ),
              trailing: Text(_inr0((line.lineTotal ?? line.landingGross).round())),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              onPressed: () => context.push('/purchase/detail/${p.id}', extra: p),
              child: const Text('Open purchase detail'),
            ),
          ),
        ],
      ),
    );
  }
}
