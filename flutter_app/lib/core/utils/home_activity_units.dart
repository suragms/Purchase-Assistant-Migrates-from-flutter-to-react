import '../json_coerce.dart';
import 'purchase_units_subtitle.dart';
import '../../features/home/presentation/widgets/home_formatters.dart';

/// Bags · boxes · tins · kg (or per-line units) for a trade purchase map.
String? purchaseActivityUnitsLine(Map<String, dynamic> p) {
  final linesRaw = p['lines'];
  if (linesRaw is List && linesRaw.isNotEmpty) {
    final line = purchaseUnitsSubtitleFromLines(linesRaw);
    if (line.isNotEmpty) return line;
  }
  final fromMap = purchaseUnitsSubtitleFromMap(p);
  return fromMap.isNotEmpty ? fromMap : null;
}

/// Stock audit row: signed delta with catalog unit (never a bare number).
String? stockAuditActivityUnitsLine(Map<String, dynamic> a) {
  final oldQ = coerceToDouble(a['old_qty']);
  final newQ = coerceToDouble(a['new_qty']);
  final rawDelta = a['delta_qty'] ?? a['qty_change'] ?? a['change'];
  var delta = coerceToDoubleNullable(rawDelta);
  delta ??= newQ - oldQ;
  if (delta.abs() < 0.001) return null;

  final unitRaw = (a['unit'] ?? a['stock_unit'] ?? '').toString().trim();
  final sign = delta >= 0 ? '+' : '-';
  final qty = homeFmtQty(delta.abs());
  if (unitRaw.isNotEmpty) {
    final u = unitRaw.toUpperCase();
    return '$sign$qty $u';
  }
  final item = a['item_name']?.toString().trim();
  if (item != null && item.isNotEmpty) {
    return '$sign$qty · $item';
  }
  return '$sign$qty';
}

/// Center-column label for delivery-style activity rows.
String warehouseActivityDeliveryUnitsLabel({
  String? unitsLine,
  String? qtyChange,
}) {
  final line = unitsLine?.trim();
  if (line != null && line.isNotEmpty) return line;
  final qc = qtyChange?.trim();
  if (qc == null || qc.isEmpty) return '—';
  if (RegExp(r'^PUR-', caseSensitive: false).hasMatch(qc)) return '—';
  return qc;
}

int warehouseActivityRowScore({
  String? unitsLine,
  String? verifiedBy,
  double? amountInr,
  String? supplierName,
}) {
  var score = 0;
  if (unitsLine != null && unitsLine.trim().isNotEmpty) score += 4;
  if (verifiedBy != null && verifiedBy.trim().isNotEmpty) score += 2;
  if (amountInr != null && amountInr > 0) score += 2;
  if (supplierName != null && supplierName.trim().isNotEmpty) score += 1;
  return score;
}
