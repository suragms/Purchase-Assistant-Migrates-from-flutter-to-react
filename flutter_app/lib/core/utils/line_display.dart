import 'package:intl/intl.dart';

import '../calc_engine.dart';
import '../json_coerce.dart';
import '../models/trade_purchase_models.dart';
import '../reporting/trade_report_aggregate.dart'
    show ReportPackKind, reportEffectivePack, reportLineKg;

String _qtyStr(double qty) {
  if (qty == qty.roundToDouble()) return qty.round().toString();
  return qty.toStringAsFixed(qty >= 100 ? 0 : 2);
}

String _kgStr(double kg) {
  if (kg <= 0) return '';
  final rounded = kg == kg.roundToDouble();
  return rounded
      ? '${NumberFormat('#,##,##0', 'en_IN').format(kg.round())} kg'
      : '${NumberFormat('#,##,##0.##', 'en_IN').format(kg)} kg';
}

/// Human-readable qty + weight for purchase lines: **bags/box/tin count first**, then total kg.
/// Use everywhere list/detail/history shows a line to avoid "5000 kg • 250000 kg" confusion.
String formatLineQtyWeight({
  required double qty,
  required String unit,
  double? kgPerUnit,
  double? totalWeightKg,
}) {
  final u = unit.trim().toLowerCase();
  final uDisp = unit.trim().isEmpty ? 'unit' : unit.trim();
  final isBag = u == 'bag' || u == 'sack';
  final isBox = u == 'box';
  final isTin = u == 'tin';

  double? totalKg;
  if (totalWeightKg != null && totalWeightKg > 1e-9) {
    totalKg = totalWeightKg;
  } else if ((isBag || isBox || isTin) &&
      kgPerUnit != null &&
      kgPerUnit > 1e-9) {
    totalKg = qty * kgPerUnit;
  } else if (u == 'kg' ||
      u == 'kgs' ||
      u == 'kilogram' ||
      u == 'kilograms' ||
      u == 'quintal' ||
      u == 'qtl') {
    totalKg = qty;
  }

  if (isBag && totalKg != null && totalKg > 1e-9) {
    return '${_qtyStr(qty)} ${_qtyStr(qty) == '1' ? 'bag' : 'bags'} • ${_kgStr(totalKg)}';
  }
  if (isBag) {
    return '${_qtyStr(qty)} ${_qtyStr(qty) == '1' ? 'bag' : 'bags'}';
  }
  if (u == 'sack' && totalKg != null && totalKg > 1e-9) {
    return '${_qtyStr(qty)} ${_qtyStr(qty) == '1' ? 'sack' : 'sacks'} • ${_kgStr(totalKg)}';
  }
  if (u == 'sack') {
    return '${_qtyStr(qty)} ${_qtyStr(qty) == '1' ? 'sack' : 'sacks'}';
  }
  if (isBox && totalKg != null && totalKg > 1e-9) {
    return '${_qtyStr(qty)} ${_qtyStr(qty) == '1' ? 'box' : 'boxes'} • ${_kgStr(totalKg)}';
  }
  if (isBox) {
    return '${_qtyStr(qty)} ${_qtyStr(qty) == '1' ? 'box' : 'boxes'}';
  }
  if (isTin && totalKg != null && totalKg > 1e-9) {
    return '${_qtyStr(qty)} ${_qtyStr(qty) == '1' ? 'tin' : 'tins'} • ${_kgStr(totalKg)}';
  }
  if (isTin) {
    return '${_qtyStr(qty)} ${_qtyStr(qty) == '1' ? 'tin' : 'tins'}';
  }
  if (totalKg != null && totalKg > 1e-9) {
    return _kgStr(totalKg);
  }
  return '${_qtyStr(qty)} $uDisp';
}

/// Spec row text for a persisted [TradePurchaseLine] (same rules as Reports).
String formatLineQtyWeightFromTradeLine(TradePurchaseLine l) {
  final raw = l.unit.trim().toLowerCase();
  final u = raw == 'sack' ? 'bag' : raw;
  if (u == 'bag') {
    final kg = reportLineKg(l);
    return formatPackagedQty(unit: 'bag', pieces: l.qty, kg: kg);
  }
  if (u == 'box') {
    return formatPackagedQty(unit: 'box', pieces: l.qty);
  }
  if (u == 'tin') {
    return formatPackagedQty(unit: 'tin', pieces: l.qty);
  }
  if (u == 'kg' ||
      u == 'kgs' ||
      u == 'kilogram' ||
      u == 'kilograms' ||
      u == 'quintal' ||
      u == 'qtl') {
    return formatPackagedQty(unit: 'kg', pieces: l.qty);
  }
  final w = ledgerTradeLineWeightKg(
    itemName: l.itemName,
    unit: l.unit,
    qty: l.qty,
    catalogDefaultUnit: l.defaultPurchaseUnit ?? l.defaultUnit,
    catalogDefaultKgPerBag: l.defaultKgPerBag,
    kgPerUnit: l.kgPerUnit,
    boxMode: l.boxMode,
    itemsPerBox: l.itemsPerBox,
    weightPerItem: l.weightPerItem,
    kgPerBox: l.kgPerBox,
    weightPerTin: l.weightPerTin,
  );
  return formatLineQtyWeight(
    qty: l.qty,
    unit: l.unit,
    kgPerUnit: l.kgPerUnit,
    totalWeightKg: (l.totalWeight != null && l.totalWeight! > 1e-9)
        ? l.totalWeight
        : (w > 1e-9 ? w : null),
  );
}

/// Bag/sack lines for KPI and history **bag** counts (sugar often uses `sack` without "bag" in the string).
bool unitCountsAsBagFamily(String? unit) {
  final u = (unit ?? '').trim().toLowerCase();
  return u.contains('bag') || u.contains('sack');
}

/// [Bug 7/8 fix] Spec-mandated row format for view-more / reports rows:
///   - BAG  → `5000 KG • 100 BAGS`
///   - BOX  → `100 BOXES`        (no kg)
///   - TIN  → `50 TINS`          (no kg)
///   - KG   → `5000 KG`
/// `bagsOrBoxesOrTins` is the count for the chosen pack family. `kg` is the
/// total weight (only used for bag/kg). Returns `'-'` when both are zero.
String formatPackagedQty({
  required String unit,
  required double pieces,
  double kg = 0,
}) {
  final u = unit.trim().toLowerCase();
  String intLike(double v) {
    if (v < 1e-9) return '0';
    if ((v - v.roundToDouble()).abs() < 1e-6) {
      return NumberFormat('#,##,##0', 'en_IN').format(v.round());
    }
    return NumberFormat('#,##,##0.##', 'en_IN').format(v);
  }

  String kgFmt(double k) {
    if ((k - k.roundToDouble()).abs() < 1e-6) {
      return '${NumberFormat('#,##,##0', 'en_IN').format(k.round())} KG';
    }
    return '${NumberFormat('#,##,##0.##', 'en_IN').format(k)} KG';
  }

  if (u == 'bag' || u == 'sack') {
    final bags = intLike(pieces);
    if (kg > 1e-9) return '${kgFmt(kg)} • $bags ${pieces == 1 ? 'BAG' : 'BAGS'}';
    return '$bags ${pieces == 1 ? 'BAG' : 'BAGS'}';
  }
  if (u == 'box') {
    final n = intLike(pieces);
    return '$n ${pieces == 1 ? 'BOX' : 'BOXES'}';
  }
  if (u == 'tin') {
    final n = intLike(pieces);
    return '$n ${pieces == 1 ? 'TIN' : 'TINS'}';
  }
  if (u == 'kg' || u == 'kgs' || u == 'kilogram' || u == 'kilograms') {
    return kgFmt(pieces);
  }
  if (pieces > 1e-9) return intLike(pieces);
  return '-';
}

/// Parses a nominal kg-per-bag hint from names like `SUGAR 50 KG` or `RICE 26KG`.
final RegExp kgPerBagHintFromItemNameRe =
    RegExp(r'(\d+(?:\.\d+)?)\s*KG\b', caseSensitive: false);

double? parseKgPerBagHintFromItemName(String itemName) {
  final m = kgPerBagHintFromItemNameRe.firstMatch(itemName.trim());
  if (m == null) return null;
  return double.tryParse(m.group(1)!);
}

/// When [totalBags] is zero but [totalKg] is positive (kg-only persisted lines),
/// infer a bag count from the item name's `NN KG` hint — **display only**.
///
/// Returns null when inference would be misleading (no hint, bad divisor, or
/// implied total weight diverges too far from [totalKg]).
int? inferBagCountForKgOnlyDisplay({
  required String itemName,
  required double totalKg,
  required double totalBags,
}) {
  if (totalBags > 1e-9) return null;
  if (totalKg <= 1e-9) return null;
  final kgPerBag = parseKgPerBagHintFromItemName(itemName);
  if (kgPerBag == null || kgPerBag <= 1e-9) return null;
  final bags = (totalKg / kgPerBag).round();
  if (bags < 1 || bags > 1000000) return null;
  final impliedKg = bags * kgPerBag;
  if ((totalKg - impliedKg).abs() > totalKg * 0.15 + 1.0) return null;
  return bags;
}

/// Trade shell item row ([`/trade-report-items`-style map][home breakdown]): quantity subtitle.
String tradeShellItemQtySummaryLine(Map<String, dynamic> m) {
  final itemTitle = m['item_name']?.toString() ?? '';
  final tb = coerceToDouble(m['total_bags']);
  final txb = coerceToDouble(m['total_boxes']);
  final ttn = coerceToDouble(m['total_tins']);
  final tkg = coerceToDouble(m['total_kg']);
  String fmtQty(double q) =>
      q == q.roundToDouble() ? q.round().toString() : q.toStringAsFixed(1);
  final parts = <String>[];
  if (tb > 0) {
    parts.add('${fmtQty(tb)} ${tb == 1 ? 'BAG' : 'BAGS'}');
  } else if (itemTitle.trim().isNotEmpty) {
    final inferred = inferBagCountForKgOnlyDisplay(
      itemName: itemTitle,
      totalKg: tkg,
      totalBags: tb,
    );
    if (inferred != null) {
      final ib = inferred.toDouble();
      parts.add('${fmtQty(ib)} ${ib == 1 ? 'BAG' : 'BAGS'}');
    }
  }
  if (txb > 0) {
    parts.add('${fmtQty(txb)} ${txb == 1 ? 'BOX' : 'BOXES'}');
  }
  if (ttn > 0) {
    parts.add('${fmtQty(ttn)} ${ttn == 1 ? 'TIN' : 'TINS'}');
  }
  if (tkg > 0) parts.add('${fmtQty(tkg)} KG');
  if (parts.isNotEmpty) return parts.join(' • ');
  final q = coerceToDouble(m['total_qty']);
  final u = m['unit']?.toString().trim();
  if (q > 0 && u != null && u.isNotEmpty && u != '—') {
    return '${fmtQty(q)} $u';
  }
  return '—';
}

class PurchaseHistoryMonthStats {
  const PurchaseHistoryMonthStats({
    required this.purchaseCount,
    required this.totalInr,
    required this.bags,
    required this.boxes,
    required this.tins,
    required this.kg,
  });

  static const empty = PurchaseHistoryMonthStats(
    purchaseCount: 0,
    totalInr: 0,
    bags: 0,
    boxes: 0,
    tins: 0,
    kg: 0,
  );

  final int purchaseCount;
  final double totalInr;
  final double bags;
  final double boxes;
  final double tins;
  /// Bag-derived kg + loose kg lines (never box/tin geometry).
  final double kg;
}

class _HistoryPackAccumulator {
  double bags = 0;
  double boxes = 0;
  double tins = 0;
  double looseKg = 0;
  double bagKg = 0;
}

void _accumulateHistoryLine(TradePurchaseLine ln, _HistoryPackAccumulator t) {
  final eff = reportEffectivePack(ln);
  if (eff != null) {
    switch (eff.kind) {
      case ReportPackKind.bag:
        t.bags += eff.packQty;
        t.bagKg += eff.kg;
        break;
      case ReportPackKind.box:
        t.boxes += eff.packQty;
        break;
      case ReportPackKind.tin:
        t.tins += eff.packQty;
        break;
    }
    return;
  }
  final u = ln.unit.trim().toLowerCase();
  if (u == 'kg' ||
      u == 'kgs' ||
      u == 'kilogram' ||
      u == 'kilograms' ||
      u == 'quintal' ||
      u == 'qtl') {
    t.looseKg += ln.qty;
  }
}

/// Distinct wholesale pack families on a purchase (`bag` / `box` / `tin`), from line units + report rules.
Set<String> purchaseHistoryPackKinds(TradePurchase p) {
  final s = <String>{};
  for (final ln in p.lines) {
    final eff = reportEffectivePack(ln);
    if (eff != null) {
      s.add(switch (eff.kind) {
        ReportPackKind.bag => 'bag',
        ReportPackKind.box => 'box',
        ReportPackKind.tin => 'tin',
      });
    }
  }
  return s;
}

/// [filterKey]: `bag` | `box` | `tin` | `mixed` — count-only semantics match history cards.
bool purchaseHistoryMatchesPackKindFilter(TradePurchase p, String filterKey) {
  final kinds = purchaseHistoryPackKinds(p);
  switch (filterKey) {
    case 'bag':
      return kinds.length == 1 && kinds.contains('bag');
    case 'box':
      return kinds.length == 1 && kinds.contains('box');
    case 'tin':
      return kinds.length == 1 && kinds.contains('tin');
    case 'mixed':
      return kinds.length > 1;
    default:
      return true;
  }
}

/// One-line pack summary for history cards (mixed invoices join with ` • `).
///
/// Bag lines and **loose kg** lines are rolled into **one total kg** next to the
/// bag count (e.g. `80 bags • 4,095 kg`), so mixed invoices do not show a second
/// stray `95 KG` segment after the bag subtotal.
String purchaseHistoryPackSummary(TradePurchase p) {
  final t = _HistoryPackAccumulator();
  for (final ln in p.lines) {
    _accumulateHistoryLine(ln, t);
  }
  final parts = <String>[];
  final bagPlusLooseKg = t.bagKg + t.looseKg;
  if (t.bags > 1e-6) {
    if (bagPlusLooseKg > 1e-6) {
      parts.add(
        formatLineQtyWeight(
          qty: t.bags,
          unit: 'bag',
          totalWeightKg: bagPlusLooseKg,
        ),
      );
    } else {
      parts.add(formatPackagedQty(unit: 'bag', pieces: t.bags));
    }
  } else if (t.looseKg > 1e-6) {
    parts.add(formatPackagedQty(unit: 'kg', pieces: t.looseKg));
  }
  if (t.boxes > 1e-6) {
    parts.add(formatPackagedQty(unit: 'box', pieces: t.boxes));
  }
  if (t.tins > 1e-6) {
    parts.add(formatPackagedQty(unit: 'tin', pieces: t.tins));
  }
  if (parts.isEmpty) return '';
  return parts.join(' • ');
}

String purchaseHistoryItemHeadline(TradePurchase p) {
  if (p.lines.isNotEmpty) {
    if (p.lines.length == 1) return p.lines.first.itemName;
    return '${p.lines.length} items';
  }
  if (p.itemsCount > 0) {
    return p.itemsCount == 1 ? '1 item' : '${p.itemsCount} items';
  }
  return '';
}

/// Calendar-month aggregates for the history header strip (kg = bags + loose kg only).
PurchaseHistoryMonthStats computePurchaseHistoryMonthStats(
  List<TradePurchase> list,
  DateTime monthAnchor,
) {
  final start = DateTime(monthAnchor.year, monthAnchor.month, 1);
  final end = DateTime(monthAnchor.year, monthAnchor.month + 1, 1);
  var count = 0;
  var totalInr = 0.0;
  final t = _HistoryPackAccumulator();
  for (final p in list) {
    final d = p.purchaseDate;
    if (d.isBefore(start)) continue;
    if (!d.isBefore(end)) continue;
    count++;
    totalInr += p.totalAmount;
    for (final ln in p.lines) {
      _accumulateHistoryLine(ln, t);
    }
  }
  final kg = t.bagKg + t.looseKg;
  return PurchaseHistoryMonthStats(
    purchaseCount: count,
    totalInr: totalInr,
    bags: t.bags,
    boxes: t.boxes,
    tins: t.tins,
    kg: kg,
  );
}

/// Date-range aggregates for the history header strip (kg = bags + loose kg only).
/// [from] and [to] are inclusive calendar days.
PurchaseHistoryMonthStats computePurchaseHistoryRangeStats(
  List<TradePurchase> list, {
  required DateTime from,
  required DateTime to,
}) {
  final start = DateTime(from.year, from.month, from.day);
  final end = DateTime(to.year, to.month, to.day);
  var count = 0;
  var totalInr = 0.0;
  final t = _HistoryPackAccumulator();
  for (final p in list) {
    final d0 = p.purchaseDate;
    final d = DateTime(d0.year, d0.month, d0.day);
    if (d.isBefore(start)) continue;
    if (d.isAfter(end)) continue;
    count++;
    totalInr += p.totalAmount;
    for (final ln in p.lines) {
      _accumulateHistoryLine(ln, t);
    }
  }
  final kg = t.bagKg + t.looseKg;
  return PurchaseHistoryMonthStats(
    purchaseCount: count,
    totalInr: totalInr,
    bags: t.bags,
    boxes: t.boxes,
    tins: t.tins,
    kg: kg,
  );
}

String formatPurchaseHistoryMonthPackLine(PurchaseHistoryMonthStats s) {
  final parts = <String>[];
  if (s.bags > 1e-6) {
    parts.add(
      '${NumberFormat('#,##,##0', 'en_IN').format(s.bags.round())} bags',
    );
  }
  if (s.boxes > 1e-6) {
    parts.add(
      '${NumberFormat('#,##,##0', 'en_IN').format(s.boxes.round())} boxes',
    );
  }
  if (s.tins > 1e-6) {
    parts.add(
      '${NumberFormat('#,##,##0', 'en_IN').format(s.tins.round())} tins',
    );
  }
  if (s.kg > 1e-6) {
    final k = s.kg;
    final kgStr = (k - k.roundToDouble()).abs() < 1e-6
        ? NumberFormat('#,##,##0', 'en_IN').format(k.round())
        : NumberFormat('#,##,##0.##', 'en_IN').format(k);
    parts.add('${kgStr}kg');
  }
  if (parts.isEmpty) return '—';
  return parts.join(' • ');
}
