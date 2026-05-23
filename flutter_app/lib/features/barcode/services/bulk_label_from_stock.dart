import '../../../core/json_coerce.dart';
import 'barcode_pdf_service.dart';

String normalizeItemId(String id) => id.trim().toLowerCase();

/// Build printable label data from a stock list row (offline / API fallback).
BarcodeLabelData? labelDataFromStockRow(Map<String, dynamic>? row) {
  if (row == null) return null;
  final ic = row['item_code']?.toString().trim() ?? '';
  final bc = row['barcode']?.toString().trim() ?? '';
  if (ic.isEmpty && bc.isEmpty) return null;

  DateTime? lpDate;
  final lpRaw = row['last_purchase_date'] ?? row['last_purchase_at'];
  if (lpRaw is String && lpRaw.isNotEmpty) {
    lpDate = DateTime.tryParse(lpRaw);
  } else if (lpRaw is DateTime) {
    lpDate = lpRaw;
  }

  final unit = row['unit']?.toString().trim() ??
      row['stock_unit']?.toString().trim() ??
      row['default_unit']?.toString().trim();

  return BarcodeLabelData(
    barcode: bc.isEmpty ? null : bc,
    itemCode: ic.isEmpty ? bc : ic,
    itemName: row['name']?.toString().trim().isNotEmpty == true
        ? row['name'].toString().trim()
        : (ic.isNotEmpty ? ic : bc),
    unit: unit?.isEmpty == true ? null : unit,
    currentStock: coerceToDoubleNullable(row['current_stock']),
    lastPurchaseDate: lpDate,
    lastPurchaseQty: coerceToDoubleNullable(
      row['last_purchase_qty'] ?? row['period_purchased_qty'],
    ),
    lastPurchaseUnit: row['last_purchase_unit']?.toString() ?? unit,
    lastPurchaseRate: coerceToDoubleNullable(row['last_purchase_rate']),
    supplierName: row['supplier_name']?.toString().trim(),
  );
}

Map<String, Map<String, dynamic>> stockRowsByIdFromList(
  Iterable<Map<String, dynamic>> rows,
) {
  final out = <String, Map<String, dynamic>>{};
  for (final row in rows) {
    final id = row['id']?.toString();
    if (id == null || id.isEmpty) continue;
    out[normalizeItemId(id)] = row;
  }
  return out;
}
