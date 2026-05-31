import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/navigation/resolve_catalog_item_id.dart';
import '../../../core/providers/reports_provider.dart';
import '../../../core/reporting/trade_report_aggregate.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../presentation/reports_item_detail_page.dart';
import '../reporting/reports_item_metrics.dart';
import '../widgets/reports_kpi_row.dart';
import 'reports_breadcrumb_bar.dart';

String _inr0(num n) =>
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
        .format(n);

/// Dedicated in-flow item report (not catalog redirect).
class ReportsItemReportPage extends ConsumerStatefulWidget {
  const ReportsItemReportPage({
    super.key,
    required this.catalogItemId,
    this.itemName,
  });

  final String catalogItemId;
  final String? itemName;

  @override
  ConsumerState<ReportsItemReportPage> createState() =>
      _ReportsItemReportPageState();
}

class _ReportsItemReportPageState extends ConsumerState<ReportsItemReportPage> {
  String? _resolvedName;
  String? _itemKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolve());
  }

  Future<void> _resolve() async {
    final name = widget.itemName?.trim();
    if (name != null && name.isNotEmpty) {
      setState(() {
        _resolvedName = name;
        _itemKey = normCatalogItemName(name);
      });
      return;
    }
    final id = await resolveCatalogItemId(ref, itemId: widget.catalogItemId);
    if (!mounted) return;
    setState(() {
      _resolvedName = widget.itemName ?? widget.catalogItemId;
      _itemKey = id ?? widget.catalogItemId;
    });
  }

  @override
  Widget build(BuildContext context) {
    final merged = ref.watch(reportsPurchasesMergedProvider);
    final key = _itemKey ?? widget.catalogItemId;
    final displayName = _resolvedName ?? widget.itemName ?? 'Item';

    TradeReportItemRow? sumRow;
    final agg = buildTradeReportAgg(merged);
    for (final r in agg.itemsAll) {
      if (r.key == key || normCatalogItemName(r.name) == normCatalogItemName(displayName)) {
        sumRow = r;
        break;
      }
    }

    if (sumRow == null && merged.isNotEmpty) {
      for (final p in merged) {
        for (final line in p.lines) {
          if (line.catalogItemId == widget.catalogItemId) {
            _resolvedName ??= line.itemName;
            break;
          }
        }
      }
    }

    final qtyLine = sumRow == null ? '' : reportQtySummaryBoldLine(sumRow);
    final txns = reportItemTransactions(merged, key);

    return Scaffold(
      backgroundColor: HexaColors.brandBackground,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/reports?tab=items');
            }
          },
        ),
        title: Text(displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
        backgroundColor: HexaColors.brandBackground,
        foregroundColor: HexaColors.brandPrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          ReportsBreadcrumbBar(
            segments: [
              ('Reports', '/reports?tab=items'),
              (displayName, null),
            ],
          ),
          if (sumRow != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ReportsKpiRow(
                totals: TradeReportTotals(
                  inr: sumRow.amountInr,
                  bags: sumRow.bags,
                  boxes: sumRow.boxes,
                  tins: sumRow.tins,
                  kg: sumRow.kg,
                  deals: sumRow.dealIds.length,
                ),
                itemCount: 1,
                supplierCount: 0,
              ),
            ),
          if (qtyLine.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                qtyLine,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text(
              _inr0((sumRow?.amountInr ?? 0).round()),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ),
          if (txns.isEmpty && sumRow == null)
            FriendlyLoadError(
              message: 'No purchase history for this item in the selected period.',
              onRetry: () {},
            )
          else
            ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(
                  'Purchase history',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                ),
              ),
              for (final t in txns)
                ListTile(
                  dense: true,
                  title: Text(t.supplierName),
                  subtitle: Text(DateFormat('d MMM yyyy').format(t.date)),
                  trailing: Text(reportKgWeightedRateLabel(t.buyRate)),
                ),
            ],
          TextButton(
            onPressed: () => context.push('/catalog/item/${widget.catalogItemId}?tab=purchases'),
            child: const Text('Open in catalog'),
          ),
        ],
      ),
    );
  }
}

/// Fallback when catalog id unknown — delegates to legacy detail page.
class ReportsItemReportFallbackPage extends ConsumerWidget {
  const ReportsItemReportFallbackPage({
    super.key,
    required this.itemKey,
    required this.itemName,
  });

  final String itemKey;
  final String itemName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ReportsItemDetailPage(itemKey: itemKey, itemName: itemName);
  }
}
