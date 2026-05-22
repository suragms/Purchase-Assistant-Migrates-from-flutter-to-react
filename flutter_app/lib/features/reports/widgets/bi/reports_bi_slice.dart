import 'package:flutter/material.dart';

import '../../../../core/json_coerce.dart';
import '../../../../core/providers/home_dashboard_provider.dart';
import '../../../../core/theme/hexa_colors.dart';
import '../../../home/presentation/widgets/home_formatters.dart';

/// Ring/list slice for Reports BI (aligned with Home analytics slices).
class ReportsBiSlice {
  const ReportsBiSlice({
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.color,
    this.qty = 0,
    this.pct = 0,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final double amount;
  final double qty;
  final double pct;
  final Color color;
  final VoidCallback? onTap;
}

bool _hasActivity({required double amount, required double qty}) =>
    amount > 0 || qty > 0;

String _mapQtyLine(Map<String, dynamic> m) {
  final qty = coerceToDouble(m['total_qty'] ?? m['qty']);
  final unit = m['unit']?.toString() ?? '';
  if (qty > 0 && unit.isNotEmpty) {
    return '${homeFmtQty(qty)} ${unit.toUpperCase()}';
  }
  if (qty > 0) return homeFmtQty(qty);
  return '';
}

List<ReportsBiSlice> slicesFromCategoryMaps(
  List<Map<String, dynamic>> rows, {
  required double totalAmount,
}) {
  final palette = HexaColors.chartPalette;
  final sorted = List<Map<String, dynamic>>.from(rows)
    ..sort(
      (a, b) => coerceToDouble(b['total_purchase'] ?? b['total_amount'])
          .compareTo(coerceToDouble(a['total_purchase'] ?? a['total_amount'])),
    );
  final out = <ReportsBiSlice>[];
  for (var i = 0; i < sorted.length && i < 8; i++) {
    final r = sorted[i];
    final amount = coerceToDouble(r['total_purchase'] ?? r['total_amount']);
    final qty = coerceToDouble(r['total_qty'] ?? r['qty']);
    if (!_hasActivity(amount: amount, qty: qty)) continue;
    final name = r['category_name']?.toString().trim() ??
        r['name']?.toString().trim() ??
        '—';
    final typeCount = r['item_count'] ?? r['line_count'];
    final sub = typeCount != null ? '$typeCount lines' : _mapQtyLine(r);
    out.add(
      ReportsBiSlice(
        title: name,
        subtitle: sub,
        amount: amount,
        qty: qty,
        pct: totalAmount > 0 ? (amount / totalAmount) * 100 : 0,
        color: palette[out.length % palette.length],
      ),
    );
  }
  return out;
}

List<ReportsBiSlice> slicesFromSubcategoryMaps(
  List<Map<String, dynamic>> rows, {
  required double totalAmount,
}) {
  final palette = HexaColors.chartPalette;
  final sorted = List<Map<String, dynamic>>.from(rows)
    ..sort(
      (a, b) => coerceToDouble(b['total_purchase'] ?? b['total_amount'])
          .compareTo(coerceToDouble(a['total_purchase'] ?? a['total_amount'])),
    );
  final out = <ReportsBiSlice>[];
  for (var i = 0; i < sorted.length && i < 8; i++) {
    final r = sorted[i];
    final amount = coerceToDouble(r['total_purchase'] ?? r['total_amount']);
    final qty = coerceToDouble(r['total_qty'] ?? r['qty']);
    if (!_hasActivity(amount: amount, qty: qty)) continue;
    final label = r['type_name']?.toString().trim() ??
        r['subcategory']?.toString().trim() ??
        '—';
    final cat = r['category_name']?.toString().trim();
    final sub = [
      if (cat != null && cat.isNotEmpty) cat,
      _mapQtyLine(r),
    ].where((s) => s.isNotEmpty).join(' · ');
    out.add(
      ReportsBiSlice(
        title: label,
        subtitle: sub,
        amount: amount,
        qty: qty,
        pct: totalAmount > 0 ? (amount / totalAmount) * 100 : 0,
        color: palette[out.length % palette.length],
      ),
    );
  }
  return out;
}

List<ReportsBiSlice> slicesFromDashboardCategories(
  HomeDashboardData dash,
) {
  final total = dash.categories.fold<double>(
    0,
    (s, c) => s + c.totalAmount,
  );
  final palette = HexaColors.chartPalette;
  final rows = List<CategoryStat>.from(dash.categories)
    ..sort((a, b) => b.totalAmount.compareTo(a.totalAmount));
  final out = <ReportsBiSlice>[];
  for (var i = 0; i < rows.length && i < 8; i++) {
    final c = rows[i];
    if (!_hasActivity(amount: c.totalAmount, qty: c.totalQty)) continue;
    out.add(
      ReportsBiSlice(
        title: c.categoryName,
        subtitle: '${c.items.length} items · ${homeFmtQty(c.totalQty)}',
        amount: c.totalAmount,
        qty: c.totalQty,
        pct: total > 0 ? (c.totalAmount / total) * 100 : 0,
        color: palette[out.length % palette.length],
      ),
    );
  }
  return out;
}

List<ReportsBiSlice> slicesFromDashboardSubcategories(HomeDashboardData dash) {
  final total = dash.subcategories.fold<double>(
    0,
    (s, x) => s + x.totalAmount,
  );
  final palette = HexaColors.chartPalette;
  final rows = List<SubcategoryStat>.from(dash.subcategories)
    ..sort((a, b) => b.totalAmount.compareTo(a.totalAmount));
  final out = <ReportsBiSlice>[];
  for (var i = 0; i < rows.length && i < 8; i++) {
    final s = rows[i];
    if (!_hasActivity(amount: s.totalAmount, qty: s.totalQty)) continue;
    out.add(
      ReportsBiSlice(
        title: s.label,
        subtitle: homeFmtQty(s.totalQty),
        amount: s.totalAmount,
        qty: s.totalQty,
        pct: total > 0 ? (s.totalAmount / total) * 100 : 0,
        color: palette[out.length % palette.length],
      ),
    );
  }
  return out;
}
