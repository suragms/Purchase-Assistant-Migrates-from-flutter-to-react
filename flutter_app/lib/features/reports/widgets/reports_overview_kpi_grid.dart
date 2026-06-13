import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/providers/analytics_breakdown_providers.dart';
import '../../../core/providers/operations_providers.dart';
import '../../../core/providers/stock_providers.dart';
import '../../../core/reporting/trade_report_aggregate.dart';
import '../../../core/theme/hexa_colors.dart';
import 'reports_qty_unit_strip.dart';

String _inr(num n) => NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    ).format(n);

/// KPI grid for Reports Overview — hero amount, unit strip, compact secondary cards.
class ReportsOverviewKpiGrid extends ConsumerWidget {
  const ReportsOverviewKpiGrid({
    super.key,
    required this.agg,
    this.onTapStock,
    this.onTapPurchases,
    this.onTapItems,
  });

  final TradeReportAgg agg;
  final VoidCallback? onTapStock;
  final VoidCallback? onTapPurchases;
  final VoidCallback? onTapItems;

  static const _amountColor = Color(0xFF3B6D11);
  static const _countColor = Color(0xFF2563EB);
  static const _warnColor = Color(0xFFDC2626);
  static const _mutedColor = Color(0xFF64748B);
  static const _accentColor = Color(0xFF0D9488);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ops = ref.watch(operationalReportsProvider).valueOrNull;
    final dead = (ops?['dead_stock'] as List?)?.length ?? 0;
    final fast = (ops?['fast_moving'] as List?)?.length ?? 0;
    final lowCount = ref.watch(lowStockByCategoryProvider).maybeWhen(
          data: (m) => m.values.fold<int>(
            0,
            (s, cat) =>
                s +
                cat.values.fold<int>(0, (a, items) => a + items.length),
          ),
          orElse: () => 0,
        );
    final cats = ref.watch(analyticsCategoriesTableProvider).valueOrNull ?? [];
    String topCat = '—';
    if (cats.isNotEmpty) {
      topCat = (cats.first['category_name'] ?? cats.first['category'] ?? '—')
          .toString();
    }
    String topSup = '—';
    if (agg.suppliers.isNotEmpty) {
      topSup = agg.suppliers.first.name;
    }

    final t = agg.totals;
    final secondary = <_KpiCardData>[
      _KpiCardData('Items', '${agg.itemsAll.length}', _countColor, onTap: onTapItems),
      _KpiCardData(
        'Suppliers',
        '${agg.suppliers.length}',
        _accentColor,
        onTap: onTapPurchases,
      ),
      _KpiCardData('Low stock', '$lowCount', _warnColor, onTap: onTapStock),
      _KpiCardData('Dead stock', '$dead', _warnColor, onTap: onTapStock),
      _KpiCardData('Fast moving', '$fast', _mutedColor, onTap: onTapStock),
      _KpiCardData('Top supplier', topSup, _accentColor, onTap: onTapPurchases),
      _KpiCardData('Top category', topCat, _mutedColor, onTap: onTapItems),
    ];

    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 720 ? 4 : 2;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: HexaColors.brandCard,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Total spend',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              _inr(t.inr),
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: _amountColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 36,
                      color: HexaColors.brandBorder,
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: InkWell(
                        onTap: onTapPurchases,
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Bills',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              Text(
                                '${t.deals}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: _countColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            ReportsQtyUnitStrip(
              bags: t.bags,
              boxes: t.boxes,
              tins: t.tins,
              kg: t.kg,
            ),
            const SizedBox(height: 6),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                mainAxisExtent: 56,
                crossAxisSpacing: 6,
                mainAxisSpacing: 6,
              ),
              itemCount: secondary.length,
              itemBuilder: (_, i) => _KpiTile(data: secondary[i]),
            ),
          ],
        );
      },
    );
  }
}

class _KpiCardData {
  const _KpiCardData(this.label, this.value, this.valueColor, {this.onTap});
  final String label;
  final String value;
  final Color valueColor;
  final VoidCallback? onTap;
}

class _KpiTile extends StatelessWidget {
  const _KpiTile({required this.data});
  final _KpiCardData data;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: HexaColors.brandCard,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: data.onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                data.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                data.value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: data.valueColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
