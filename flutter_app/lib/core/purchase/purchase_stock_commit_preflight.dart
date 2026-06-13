import '../models/trade_purchase_models.dart';

enum PurchaseStockCommitIssueKind {
  missingCatalogLink,
  needsUnitSetup,
}

class PurchaseStockCommitIssue {
  const PurchaseStockCommitIssue({
    required this.kind,
    required this.lineId,
    required this.itemName,
    this.catalogItemId,
    required this.qty,
    required this.lineUnit,
    this.stockUnit,
  });

  final PurchaseStockCommitIssueKind kind;
  final String lineId;
  final String itemName;
  final String? catalogItemId;
  final double qty;
  final String lineUnit;
  final String? stockUnit;

  String get headline => switch (kind) {
        PurchaseStockCommitIssueKind.missingCatalogLink =>
          'Link to a catalog item',
        PurchaseStockCommitIssueKind.needsUnitSetup =>
          'Set catalog stock unit / weight',
      };

  String get detail {
    final lu = lineUnit.trim().isEmpty ? 'unit' : lineUnit.trim();
    final su = (stockUnit ?? '').trim();
    if (kind == PurchaseStockCommitIssueKind.missingCatalogLink) {
      return '$itemName · ${_fmtQty(qty)} $lu — pick a catalog item on the purchase line.';
    }
    if (su.isEmpty) {
      return '$itemName · ${_fmtQty(qty)} $lu — stock unit is not configured on the catalog item.';
    }
    if (deriveTradeUnitType(lineUnit) == 'box' && stockUnit == 'piece') {
      return '$itemName · ${_fmtQty(qty)} $lu — set catalog stock unit to box for this item.';
    }
    return '$itemName · ${_fmtQty(qty)} $lu — catalog stock is tracked in $su; '
        'add kg-per-bag/box weight or change the line unit to match.';
  }
}

/// Mirrors backend [derive_trade_unit_type] for stock-commit preflight.
String deriveTradeUnitType(String? unit) {
  final u = (unit ?? '').trim().toUpperCase();
  if (u.isEmpty) return 'other';
  if (u == 'BG' || u == 'BGS' || u.contains('SACK') || u.contains('BAG')) {
    return 'bag';
  }
  if (u.contains('BOX')) return 'box';
  if (u.contains('TIN')) return 'tin';
  if (u == 'LTR' ||
      u == 'LITRE' ||
      u == 'LITER' ||
      u == 'LITRES' ||
      u == 'LITERS' ||
      u.contains('LITRE') ||
      u.contains('LITER')) {
    return 'litre';
  }
  if (u == 'PCS' || u == 'PC' || u == 'PIECE' || u == 'PIECES') {
    return 'pcs';
  }
  if (u.contains('KG') || u.contains('KGS') || u.contains('KILO')) {
    return 'kg';
  }
  return 'other';
}

double? parseKgPerBagFromName(String? itemName) {
  if (itemName == null || itemName.trim().isEmpty) return null;
  final m = RegExp(r'(\d+(?:\.\d+)?)\s*KG\b', caseSensitive: false)
      .firstMatch(itemName);
  if (m == null) return null;
  final v = double.tryParse(m.group(1) ?? '');
  if (v == null || v <= 0 || v > 200) return null;
  return v;
}

String catalogStockUnit(
  Map<String, dynamic>? catalogRow,
  TradePurchaseLine line,
) {
  if (catalogRow == null) return '';
  // Mirror backend profile_from_catalog_item().primary_unit (commit-stock SSOT).
  final du = (catalogRow['default_unit']?.toString() ?? 'piece')
      .trim()
      .toLowerCase();
  final unitRes = catalogRow['unit_resolution'];
  final ur = unitRes is Map
      ? Map<String, dynamic>.from(unitRes)
      : const <String, dynamic>{};
  final pt = (ur['package_type'] ?? catalogRow['package_type'])
      ?.toString()
      .trim()
      .toUpperCase();

  // Owner-set default_unit is SSOT (overrides RETAIL_PACKET smart rows e.g. 400GM BOX).
  if (du == 'box') return 'box';
  if (du == 'tin') return 'tin';
  if (du == 'bag') return 'bag';
  if (du == 'kg') return 'kg';

  if (pt == 'LOOSE' || pt == 'LOOSE_KG' || du == 'kg') return 'kg';

  // Retail "* BOX" rows still tracked as piece in DB — commit as box when name says so.
  final name =
      (catalogRow['name']?.toString() ?? line.itemName).trim().toUpperCase();
  if (du != 'bag' && du != 'kg' && du != 'tin') {
    if (name.contains(' BOX') ||
        name.endsWith(' BOX') ||
        RegExp(r'\bBOX\b').hasMatch(name) ||
        pt == 'BOX') {
      return 'box';
    }
  }

  if (pt == 'RETAIL_PACKET' ||
      pt == 'PACKET' ||
      pt == 'PKT' ||
      (du == 'piece' &&
          (_toDouble(catalogRow['default_kg_per_bag']) != null ||
              _toDouble(ur['kg_per_bag']) != null ||
              _toDouble(ur['package_size']) != null &&
                  (ur['package_measurement']?.toString().toUpperCase() ==
                      'KG')))) {
    return 'piece';
  }

  if (du == 'bag' || pt == 'SACK' || pt == 'WHOLESALE_BAG' || pt == 'BAG') {
    return 'bag';
  }
  if (du == 'box' || pt == 'BOX') return 'box';
  if (du == 'tin' || pt == 'TIN') return 'tin';

  // Persisted smart-unit stock label when profile mode is ambiguous.
  for (final key in ['stock_unit']) {
    final fromUr = ur[key]?.toString().trim();
    if (fromUr != null && fromUr.isNotEmpty) {
      return fromUr.toLowerCase();
    }
    final top = catalogRow[key]?.toString().trim();
    if (top != null && top.isNotEmpty) return top.toLowerCase();
  }

  return du.isEmpty ? 'piece' : du;
}

double? catalogKgPerBag(
  Map<String, dynamic>? catalogRow,
  TradePurchaseLine line, {
  required String stockUnit,
}) {
  final unitRes = catalogRow?['unit_resolution'];
  final ur = unitRes is Map
      ? Map<String, dynamic>.from(unitRes)
      : const <String, dynamic>{};
  for (final v in [
    line.kgPerUnit,
    ur['kg_per_bag'],
    ur['conversion_factor'],
    catalogRow?['default_kg_per_bag'],
    catalogRow?['conversion_factor'],
    if ((ur['package_measurement']?.toString().toUpperCase() ?? '') == 'KG')
      ur['package_size'],
    line.defaultKgPerBag,
  ]) {
    final n = _toDouble(v);
    if (n != null && n > 0) return n;
  }
  if (deriveTradeUnitType(stockUnit) == 'bag') {
    return parseKgPerBagFromName(line.itemName);
  }
  return null;
}

double lineKgQty(
  TradePurchaseLine line,
  Map<String, dynamic>? catalogRow,
  String stockUnit,
) {
  final tw = line.totalWeight;
  if (tw != null && tw > 0) return tw;
  final qty = line.receivedQty ?? line.qty;
  if (qty <= 0) return 0;
  final lineType = deriveTradeUnitType(line.unit);
  if (lineType == 'kg') return qty;
  if (lineType == 'bag') {
    final kpb = catalogKgPerBag(catalogRow, line, stockUnit: stockUnit);
    if (kpb != null && kpb > 0) return qty * kpb;
  }
  return 0;
}

/// Client mirror of backend [line_qty_in_stock_unit] (preflight only).
double estimateLineQtyInStockUnit(
  TradePurchaseLine line,
  Map<String, dynamic>? catalogRow,
) {
  final snap = line.qtyInStockUnit;
  if (snap != null && snap > 0) {
    return snap;
  }

  final rawQty = line.receivedQty ?? line.qty;
  if (rawQty <= 0) return 0;

  final stockUnit = catalogStockUnit(catalogRow, line);
  final stockType = deriveTradeUnitType(stockUnit);
  final lineType = deriveTradeUnitType(line.unit);

  if (lineType == stockType) return rawQty;

  if (stockType == 'bag') {
    if (lineType == 'bag') return rawQty;
    if (lineType == 'kg') {
      final kg = lineKgQty(line, catalogRow, stockUnit);
      final kpb = catalogKgPerBag(catalogRow, line, stockUnit: stockUnit);
      if (kpb != null && kpb > 0 && kg > 0) return kg / kpb;
      return 0;
    }
  }

  if (stockType == 'pcs' || stockType == 'other') {
    final lu = line.unit.trim().toLowerCase();
    if (lineType == 'pcs' || lineType == 'other') {
      if (lu.isEmpty ||
          lu == 'piece' ||
          lu == 'pieces' ||
          lu == 'pcs' ||
          lu == 'pkt' ||
          lu == 'packet') {
        return rawQty;
      }
    }
    if (lineType == 'kg') {
      final kg = lineKgQty(line, catalogRow, stockUnit);
      final wpp = catalogKgPerBag(catalogRow, line, stockUnit: stockUnit);
      if (wpp != null && wpp > 0 && kg > 0) return kg / wpp;
      return 0;
    }
    if (lineType == 'bag') return 0;
  }

  if (stockType == 'kg') {
    if (lineType == 'kg') return rawQty;
    if (lineType == 'bag') {
      final kpb = catalogKgPerBag(catalogRow, line, stockUnit: stockUnit);
      if (kpb != null && kpb > 0) return rawQty * kpb;
      return 0;
    }
  }

  if (stockType == 'pcs' || stockType == 'other') {
    if (lineType == 'pcs' || lineType == 'other') return rawQty;
  }

  if (stockType == 'box' && lineType == 'box') return rawQty;
  if (stockType == 'tin' && lineType == 'tin') return rawQty;

  // Retail rows named "* BOX" purchased in boxes — 1:1 until catalog default_unit is box.
  if (lineType == 'box' &&
      (stockType == 'pcs' || stockType == 'other')) {
    final name = line.itemName.toUpperCase();
    final pt =
        (catalogRow?['package_type']?.toString() ?? '').trim().toUpperCase();
    if (name.contains(' BOX') || name.endsWith(' BOX') || pt == 'BOX') {
      return rawQty;
    }
  }

  final lu = line.unit.trim().toLowerCase();
  if (stockUnit.isNotEmpty && lu.isNotEmpty && stockUnit == lu) return rawQty;

  return 0;
}

/// Client mirror of backend [line_qty_for_stock_commit] (commit preflight SSOT).
double estimateLineQtyForStockCommit(
  TradePurchaseLine line,
  Map<String, dynamic>? catalogRow,
) {
  final recv = line.receivedQty;
  if (recv != null) {
    if (recv <= 0) return 0;
    final ordered = line.qty;
    final snap = line.qtyInStockUnit;
    if (snap != null && ordered > 0 && snap > 0) {
      return snap * recv / ordered;
    }
    final proxy = TradePurchaseLine(
      id: line.id,
      itemName: line.itemName,
      qty: recv,
      unit: line.unit,
      landingCost: line.landingCost,
      catalogItemId: line.catalogItemId,
      kgPerUnit: line.kgPerUnit,
      totalWeight: line.totalWeight,
      defaultKgPerBag: line.defaultKgPerBag,
    );
    return estimateLineQtyInStockUnit(proxy, catalogRow);
  }
  return estimateLineQtyInStockUnit(line, catalogRow);
}

String suggestCatalogUnitForStockCommitIssue(
  PurchaseStockCommitIssue issue,
  Map<String, dynamic>? catalogRow,
) {
  final lineType = deriveTradeUnitType(issue.lineUnit);
  if (lineType == 'box') return 'box';
  if (lineType == 'bag') return 'bag';
  if (lineType == 'tin') return 'tin';
  if (lineType == 'kg') return 'kg';

  final du = (catalogRow?['default_unit']?.toString() ?? '').trim().toLowerCase();
  if (du == 'box' || du == 'bag' || du == 'tin' || du == 'kg') return du;

  final name =
      (catalogRow?['name']?.toString() ?? issue.itemName).trim().toUpperCase();
  if (name.contains(' BOX') ||
      name.endsWith(' BOX') ||
      RegExp(r'\bBOX\b').hasMatch(name)) {
    return 'box';
  }
  if (parseKgPerBagFromName(issue.itemName) != null) return 'bag';

  final su = (issue.stockUnit ?? '').trim().toLowerCase();
  if (su == 'box' || su == 'bag' || su == 'tin' || su == 'kg') return su;
  if (lineType == 'pcs') return 'piece';
  return 'piece';
}

List<PurchaseStockCommitIssue> issuesFromUnitSetupItemNames(
  TradePurchase purchase,
  List<dynamic> itemNames,
  List<Map<String, dynamic>> catalogRows,
) {
  final byId = <String, Map<String, dynamic>>{
    for (final row in catalogRows)
      if ((row['id']?.toString() ?? '').isNotEmpty) row['id'].toString(): row,
  };
  final wanted = itemNames
      .map((x) => x.toString().trim().toUpperCase())
      .where((s) => s.isNotEmpty)
      .toSet();
  if (wanted.isEmpty) return const [];

  final out = <PurchaseStockCommitIssue>[];
  for (final line in purchase.lines) {
    final rawQty = line.receivedQty ?? line.qty;
    if (rawQty <= 0) continue;
    if (!wanted.contains(line.itemName.trim().toUpperCase())) continue;
    final cid = line.catalogItemId?.trim();
    if (cid == null || cid.isEmpty) {
      out.add(
        PurchaseStockCommitIssue(
          kind: PurchaseStockCommitIssueKind.missingCatalogLink,
          lineId: line.id,
          itemName: line.itemName,
          qty: rawQty,
          lineUnit: line.unit,
        ),
      );
      continue;
    }
    final row = byId[cid];
    out.add(
      PurchaseStockCommitIssue(
        kind: PurchaseStockCommitIssueKind.needsUnitSetup,
        lineId: line.id,
        itemName: line.itemName,
        catalogItemId: cid,
        qty: rawQty,
        lineUnit: line.unit,
        stockUnit: row == null ? null : catalogStockUnit(row, line),
      ),
    );
  }
  return out;
}

List<PurchaseStockCommitIssue> findPurchaseStockCommitIssues(
  TradePurchase purchase,
  List<Map<String, dynamic>> catalogRows,
) {
  final byId = <String, Map<String, dynamic>>{
    for (final row in catalogRows)
      if ((row['id']?.toString() ?? '').isNotEmpty) row['id'].toString(): row,
  };
  final out = <PurchaseStockCommitIssue>[];
  for (final line in purchase.lines) {
    final rawQty = line.receivedQty ?? line.qty;
    if (rawQty <= 0) continue;
    final cid = line.catalogItemId?.trim();
    if (cid == null || cid.isEmpty) {
      out.add(
        PurchaseStockCommitIssue(
          kind: PurchaseStockCommitIssueKind.missingCatalogLink,
          lineId: line.id,
          itemName: line.itemName,
          qty: rawQty,
          lineUnit: line.unit,
        ),
      );
      continue;
    }
    final row = byId[cid];
    if (row == null) {
      out.add(
        PurchaseStockCommitIssue(
          kind: PurchaseStockCommitIssueKind.needsUnitSetup,
          lineId: line.id,
          itemName: line.itemName,
          catalogItemId: cid,
          qty: rawQty,
          lineUnit: line.unit,
          stockUnit: null,
        ),
      );
      continue;
    }
    final stockUnit = catalogStockUnit(row, line);
    final stockQty = estimateLineQtyForStockCommit(line, row);
    if (stockQty <= 0) {
      out.add(
        PurchaseStockCommitIssue(
          kind: PurchaseStockCommitIssueKind.needsUnitSetup,
          lineId: line.id,
          itemName: line.itemName,
          catalogItemId: cid,
          qty: rawQty,
          lineUnit: line.unit,
          stockUnit: stockUnit,
        ),
      );
    }
  }
  return out;
}
double? _toDouble(Object? raw) {
  if (raw == null) return null;
  if (raw is num) return raw.toDouble();
  return double.tryParse(raw.toString());
}

String _fmtQty(double n) {
  if ((n - n.roundToDouble()).abs() < 1e-6) return n.round().toString();
  return n.toStringAsFixed(3).replaceAll(RegExp(r'\.?0+$'), '');
}
