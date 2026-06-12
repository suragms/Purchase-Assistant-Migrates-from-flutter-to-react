import '../../core/json_coerce.dart';

/// Internal metadata on optimistic patches — stripped before list render.
const kStockListPatchAtKey = '_patchedAt';

DateTime? _parsePatchOrRowTimestamp(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  return DateTime.tryParse(raw);
}

/// True when server row timestamps are newer than the optimistic patch.
bool serverRowNewerThanPatch(
  Map<String, dynamic> serverRow,
  Map<String, dynamic> patch,
) {
  final patchedAt = _parsePatchOrRowTimestamp(
    patch[kStockListPatchAtKey]?.toString(),
  );
  if (patchedAt == null) return true;
  final candidates = <String?>[
    serverRow['last_stock_updated_at']?.toString(),
    serverRow['physical_stock_counted_at']?.toString(),
  ];
  for (final raw in candidates) {
    final ts = _parsePatchOrRowTimestamp(raw);
    if (ts != null && ts.isAfter(patchedAt)) return true;
  }
  return false;
}

/// Merges optimistic row fields into a stock list payload (items + total).
Map<String, dynamic> mergeStockListRowMaps(
  Map<String, dynamic> data,
  Map<String, Map<String, dynamic>> patches,
) {
  if (patches.isEmpty) return data;
  final raw = data['items'];
  if (raw is! List) return data;
  final items = <Map<String, dynamic>>[];
  for (final e in raw) {
    if (e is! Map) continue;
    items.add(mergeStockListRowMap(Map<String, dynamic>.from(e), patches));
  }
  return {...data, 'items': items};
}

/// Merges [patches] into a single list row map (by item id).
Map<String, dynamic> mergeStockListRowMap(
  Map<String, dynamic> row,
  Map<String, Map<String, dynamic>> patches,
) {
  final id = row['id']?.toString();
  if (id == null || id.isEmpty) return row;
  final patch = patches[id];
  if (patch == null || patch.isEmpty) return row;
  final hasTimestamp = patch.containsKey(kStockListPatchAtKey);
  if (hasTimestamp && serverRowNewerThanPatch(row, patch)) return row;
  final visible = Map<String, dynamic>.from(patch)
    ..remove(kStockListPatchAtKey);
  if (visible.isEmpty) return row;
  return {...row, ...visible};
}

/// List row fields from POST `/stock/{id}/physical-count` response.
Map<String, dynamic> stockListPatchFromPhysicalCount(
  Map<String, dynamic> out, {
  num? fallbackCountedQty,
  num? fallbackSystemQty,
}) {
  final counted = coerceToDoubleNullable(out['physical_stock_qty']) ??
      coerceToDoubleNullable(out['counted_qty']) ??
      (fallbackCountedQty != null ? fallbackCountedQty.toDouble() : null);
  final system = coerceToDoubleNullable(out['system_qty']) ??
      coerceToDoubleNullable(out['current_stock']) ??
      (fallbackSystemQty != null ? fallbackSystemQty.toDouble() : null);
  if (counted == null) return const {};
  final sys = system ?? 0.0;
  final diff = coerceToDoubleNullable(out['physical_stock_difference_qty']) ??
      coerceToDoubleNullable(out['difference_qty']) ??
      (counted - sys);
  final at = out['physical_stock_counted_at']?.toString() ??
      out['counted_at']?.toString();
  final by = out['physical_stock_counted_by']?.toString() ??
      out['counted_by_name']?.toString();
  final systemAt = out['last_stock_updated_at']?.toString();
  final systemBy = out['last_stock_updated_by']?.toString();
  return {
    'physical_stock_qty': counted,
    'physical_stock_difference_qty': diff,
    if (by != null && by.isNotEmpty) 'physical_stock_counted_by': by,
    if (at != null && at.isNotEmpty) 'physical_stock_counted_at': at,
    if (systemAt != null && systemAt.isNotEmpty) 'last_stock_updated_at': systemAt,
    if (systemBy != null && systemBy.isNotEmpty) 'last_stock_updated_by': systemBy,
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
