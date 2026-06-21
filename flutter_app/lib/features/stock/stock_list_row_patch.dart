import '../../core/json_coerce.dart';

/// Internal metadata on optimistic patches — stripped before list render.
const kStockListPatchAtKey = '_patchedAt';

/// Keep optimistic qty overlay briefly when list timestamps race ahead of qty.
const Duration kStockPatchStaleQtyGrace = Duration(seconds: 45);

DateTime? _parsePatchOrRowTimestamp(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  return DateTime.tryParse(raw);
}

/// Derive list-row status when the API omits [stock_status] on a partial payload.
String? stockStatusForPatchRow(Map<String, dynamic> detail) {
  final st = detail['stock_status']?.toString().trim();
  if (st != null && st.isNotEmpty) return st;
  final qty = coerceToDoubleNullable(detail['current_stock']) ??
      coerceToDoubleNullable(detail['system_qty']);
  if (qty == null || !qty.isFinite) return null;
  if (qty <= 0) return 'out';
  final reorder = coerceToDoubleNullable(detail['reorder_level']);
  if (reorder != null && reorder > 0 && qty <= reorder) return 'low';
  return 'healthy';
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

bool _patchStockQtyDiffersFromServer(
  Map<String, dynamic> serverRow,
  Map<String, dynamic> patch,
) {
  final pQty = coerceToDoubleNullable(patch['current_stock']);
  final sQty = coerceToDoubleNullable(serverRow['current_stock']);
  if (pQty != null &&
      sQty != null &&
      (pQty - sQty).abs() > 1e-6) {
    return true;
  }
  final pPhys = coerceToDoubleNullable(patch['physical_stock_qty']);
  final sPhys = coerceToDoubleNullable(serverRow['physical_stock_qty']);
  if (pPhys != null &&
      sPhys != null &&
      (pPhys - sPhys).abs() > 1e-6) {
    return true;
  }
  return false;
}

bool shouldKeepStockPatchDespiteServerTimestamp(
  Map<String, dynamic> serverRow,
  Map<String, dynamic> patch,
) {
  if (!_patchStockQtyDiffersFromServer(serverRow, patch)) return false;
  final patchedAt = _parsePatchOrRowTimestamp(
    patch[kStockListPatchAtKey]?.toString(),
  );
  if (patchedAt == null) return false;
  return DateTime.now().toUtc().difference(patchedAt) < kStockPatchStaleQtyGrace;
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
  if (hasTimestamp &&
      serverRowNewerThanPatch(row, patch) &&
      !shouldKeepStockPatchDespiteServerTimestamp(row, patch)) {
    return row;
  }
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
      fallbackCountedQty?.toDouble();
  final system = coerceToDoubleNullable(out['system_qty']) ??
      coerceToDoubleNullable(out['current_stock']) ??
      fallbackSystemQty?.toDouble();
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
  final status = stockStatusForPatchRow(out);
  return {
    'physical_stock_qty': counted,
    'physical_stock_difference_qty': diff,
    if (system != null && system.isFinite) 'current_stock': system,
    if (status != null) 'stock_status': status,
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
  final status = stockStatusForPatchRow(detail);
  if (status != null) patch['stock_status'] = status;
  return patch;
}
