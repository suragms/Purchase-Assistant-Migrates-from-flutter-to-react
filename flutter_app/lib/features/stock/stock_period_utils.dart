import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/home_dashboard_provider.dart';
import '../../core/providers/stock_providers.dart';

/// YYYY-MM-DD for stock list period query params (inclusive end date).
String stockApiDate(DateTime d) {
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// Applies [p] to [stockListQueryProvider] with period purchase totals enabled.
void applyStockPagePeriod(WidgetRef ref, HomePeriod p) {
  ref.read(stockPagePeriodProvider.notifier).state = p;
  final range = homePeriodRange(p);
  final endInclusive = range.end.subtract(const Duration(days: 1));
  final q = ref.read(stockListQueryProvider);
  ref.read(stockListQueryProvider.notifier).state = q.copyWith(
    includePeriod: true,
    periodStart: stockApiDate(range.start),
    periodEnd: stockApiDate(endInclusive),
    page: 1,
  );
  ref.read(stockSelectedItemIdProvider.notifier).state = null;
}

/// Client-side filters for operational stock list (unit, missing code, reorder).
List<Map<String, dynamic>> filterStockListClient(
  List<Map<String, dynamic>> items,
  StockOperationalFilters op,
) {
  return items.where((it) {
    if (op.missingBarcodeOnly && it['missing_barcode'] != true) return false;
    if (op.missingItemCodeOnly && it['missing_item_code'] != true) return false;
    if (op.reorderOnly) {
      final ro = _num(it['reorder_level']);
      final cur = _num(it['current_stock']);
      if (ro <= 0 || cur > ro) return false;
    }
    if (op.unit.isNotEmpty) {
      final u = (it['unit']?.toString() ?? '').toLowerCase();
      if (u != op.unit.toLowerCase()) return false;
    }
    return true;
  }).toList();
}

double _num(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse('$v') ?? 0;
}

/// Warehouse priority sort: recently updated → low/out → missing barcode/code → name.
int stockRowSortKey(Map<String, dynamic> item) {
  final updated = item['last_stock_updated_at']?.toString();
  if (updated != null && updated.isNotEmpty) return 0;
  final st = item['stock_status']?.toString() ?? '';
  if (st == 'out') return 1;
  if (st == 'critical') return 2;
  if (st == 'low') return 3;
  if (item['missing_barcode'] == true || item['missing_item_code'] == true) {
    return 4;
  }
  return 5;
}

void sortStockListOperational(List<Map<String, dynamic>> items) {
  items.sort((a, b) {
    final ka = stockRowSortKey(a);
    final kb = stockRowSortKey(b);
    if (ka != kb) return ka.compareTo(kb);
    return (a['name']?.toString() ?? '')
        .toLowerCase()
        .compareTo((b['name']?.toString() ?? '').toLowerCase());
  });
}
