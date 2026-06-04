import '../../core/json_coerce.dart';

/// Merges optimistic row fields into a stock list payload (items + total).
Map<String, dynamic> applyStockListRowPatches(
  Map<String, dynamic> data,
  Map<String, Map<String, dynamic>> patches,
) {
  if (patches.isEmpty) return data;
  final raw = data['items'];
  if (raw is! List) return data;
  final items = <Map<String, dynamic>>[];
  for (final e in raw) {
    if (e is! Map) continue;
    items.add(applyStockListRowPatch(Map<String, dynamic>.from(e), patches));
  }
  return {...data, 'items': items};
}

Map<String, dynamic> applyStockListRowPatch(
  Map<String, dynamic> row,
  Map<String, Map<String, dynamic>> patches,
) {
  final id = row['id']?.toString();
  if (id == null || id.isEmpty) return row;
  final patch = patches[id];
  if (patch == null || patch.isEmpty) return row;
  return {...row, ...patch};
}

/// List row fields from POST `/stock/{id}/physical-count` response.
Map<String, dynamic> stockListPatchFromPhysicalCount(
  Map<String, dynamic> out,
) {
  final counted = coerceToDouble(out['counted_qty']);
  final system = coerceToDouble(out['system_qty']);
  final diff = coerceToDoubleNullable(out['difference_qty']) ?? (counted - system);
  final at = out['counted_at']?.toString();
  final by = out['counted_by_name']?.toString();
  return {
    'physical_stock_qty': counted,
    'physical_stock_difference_qty': diff,
    if (by != null && by.isNotEmpty) 'physical_stock_counted_by': by,
    if (at != null && at.isNotEmpty) 'physical_stock_counted_at': at,
  };
}

/// List row fields from PATCH `/stock/{id}` (detail) response.
Map<String, dynamic> stockListPatchFromStockDetail(
  Map<String, dynamic> detail, {
  num? fallbackQty,
}) {
  final patch = <String, dynamic>{};
  final qty = coerceToDoubleNullable(detail['current_stock']) ?? fallbackQty;
  if (qty != null && qty.isFinite) {
    patch['current_stock'] = qty;
    final phys = coerceToDoubleNullable(detail['physical_stock_qty']);
    if (phys != null && phys.isFinite) {
      patch['physical_stock_difference_qty'] = phys - qty;
    }
  }
  final version = detail['stock_version'];
  if (version != null) patch['stock_version'] = version;
  final at = detail['last_stock_updated_at']?.toString();
  final by = detail['last_stock_updated_by']?.toString();
  if (at != null && at.isNotEmpty) patch['last_stock_updated_at'] = at;
  if (by != null && by.isNotEmpty) patch['last_stock_updated_by'] = by;
  final physAt = detail['physical_stock_counted_at']?.toString();
  final physBy = detail['physical_stock_counted_by']?.toString();
  if (physAt != null && physAt.isNotEmpty) {
    patch['physical_stock_counted_at'] = physAt;
  }
  if (physBy != null && physBy.isNotEmpty) {
    patch['physical_stock_counted_by'] = physBy;
  }
  final physQty = coerceToDoubleNullable(detail['physical_stock_qty']);
  if (physQty != null && physQty.isFinite) {
    patch['physical_stock_qty'] = physQty;
    final sys = qty ?? coerceToDouble(detail['current_stock']);
    if (sys.isFinite) {
      patch['physical_stock_difference_qty'] = physQty - sys;
    }
  }
  return patch;
}
