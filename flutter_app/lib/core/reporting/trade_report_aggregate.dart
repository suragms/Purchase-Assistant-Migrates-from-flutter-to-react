import '../models/trade_purchase_models.dart';
import '../utils/trade_purchase_commission.dart';

/// Purchases that contribute to reports / PDF / aggregates (exclude deleted & cancelled).
List<TradePurchase> reportActivePurchases(List<TradePurchase> purchases) {
  return purchases.where((p) {
    final s = p.statusEnum;
    return s != PurchaseStatus.deleted && s != PurchaseStatus.cancelled;
  }).toList();
}

/// Bag / Box / Tin — lines that do not match are excluded from aggregates.
enum ReportPackKind {
  bag,
  box,
  tin,
}

double? _inferPackSizeKgFromItemName(String name) {
  // Heuristic: detect patterns like "SUGAR 50 KG" or "50KG" and treat as a bag-size.
  // We only use this when the stored unit is KG (i.e. legacy entries recorded as weight).
  final s = name.toUpperCase();
  final m = RegExp(r'(\d{1,3}(?:\.\d{1,2})?)\s*KG\b').firstMatch(s);
  if (m == null) return null;
  final raw = m.group(1);
  if (raw == null) return null;
  final v = double.tryParse(raw);
  if (v == null || v <= 0) return null;
  // Guard against nonsense (e.g. "2026 KG" in dates or IDs).
  if (v > 500) return null;
  return v;
}

class ReportEffectiveLinePack {
  const ReportEffectiveLinePack({
    required this.kind,
    required this.packQty,
    required this.kg,
  });

  final ReportPackKind kind;
  final double packQty;
  final double kg;
}

/// Returns the effective pack kind + quantities used by Reports.
///
/// Primary: classify by explicit line unit.
/// Fallback: if unit is KG and item name includes a pack size like "50 KG",
/// treat it as a BAG-family line with `packQty = totalKg / packSizeKg`.
ReportEffectiveLinePack? reportEffectivePack(TradePurchaseLine l) {
  final pk = reportClassifyPackKind(l);
  if (pk != null) {
    return ReportEffectiveLinePack(
      kind: pk,
      packQty: l.qty,
      kg: reportLineKg(l),
    );
  }

  final u = l.unit.trim().toUpperCase();
  final isKg = u == 'KG' || u == 'KGS' || u == 'KILOGRAM' || u == 'KILOGRAMS';
  if (!isKg) return null;

  final packSizeKg = _inferPackSizeKgFromItemName(l.itemName);
  if (packSizeKg == null || packSizeKg <= 1e-9) return null;
  if (l.qty <= 1e-9) return null;

  return ReportEffectiveLinePack(
    kind: ReportPackKind.bag,
    packQty: l.qty / packSizeKg,
    kg: l.qty,
  );
}

/// Single source of truth for Reports: classify only by [TradePurchaseLine.unit].
ReportPackKind? reportClassifyPackKind(TradePurchaseLine l) {
  final u = l.unit.trim().toUpperCase();
  if (u == 'BAG' || u == 'SACK' || u.contains('BAG') || u.contains('SACK')) {
    return ReportPackKind.bag;
  }
  if (u == 'BOX' || u.contains('BOX')) return ReportPackKind.box;
  if (u == 'TIN' || u.contains('TIN')) return ReportPackKind.tin;
  return null;
}

/// Kg from explicit fields; uses persisted [TradePurchaseLine.totalWeight] only when
/// geometry fields cannot yield a positive value (server-computed truth).
double reportLineKg(TradePurchaseLine l) {
  final k = reportClassifyPackKind(l);
  if (k == null) return 0;
  final q = l.qty;
  if (q <= 0) return 0;

  double tw() {
    final t = l.totalWeight;
    if (t != null && t > 0) return t;
    return 0;
  }

  switch (k) {
    case ReportPackKind.bag:
      final kpu = l.kgPerUnit;
      if (kpu != null && kpu > 0) return q * kpu;
      return tw();
    case ReportPackKind.box:
      // Master rebuild default wholesale mode: BOX is count-only (no kg tracking).
      return 0;
    case ReportPackKind.tin:
      // Master rebuild default wholesale mode: TIN is count-only (no kg tracking).
      return 0;
  }
}

/// Amount for report INR totals: [TradePurchaseLine.lineTotal] when set (canonical
/// tax/discount-inclusive line purchase), else [TradePurchaseLine.landingGross]
/// (computed pre-tax gross; mirrors SQL `coalesce(line_total, computed_gross)`).
double reportLineAmountInr(TradePurchaseLine l) {
  if (l.lineTotal != null) return l.lineTotal!;
  return l.landingGross;
}

class TradeReportItemRow {
  TradeReportItemRow({
    required this.key,
    required this.name,
  });

  final String key;
  final String name;
  double bags = 0;
  double boxes = 0;
  double tins = 0;
  double kg = 0;
  double amountInr = 0;
  final Set<String> dealIds = {};
  /// Latest [TradePurchase.purchaseDate] among lines contributing to this row.
  DateTime? lastPurchaseDate;
}

class TradeReportSupplierRow {
  TradeReportSupplierRow({required this.key, required this.name});

  final String key;
  final String name;
  final Set<String> dealIds = {};
  double bagQty = 0;
  double bagKg = 0;
  double amountInr = 0;
  DateTime? lastPurchaseDate;
}

class TradeReportBrokerRow {
  TradeReportBrokerRow({required this.key, required this.name});

  final String key;
  final String name;
  double commission = 0;
  final Set<String> purchaseIds = {};
}

class TradeReportTotals {
  const TradeReportTotals({
    required this.inr,
    required this.bags,
    required this.boxes,
    required this.tins,
    required this.kg,
    required this.deals,
  });

  final double inr;
  final double bags;
  final double boxes;
  final double tins;
  final double kg;
  final int deals;

  static const zero = TradeReportTotals(
    inr: 0,
    bags: 0,
    boxes: 0,
    tins: 0,
    kg: 0,
    deals: 0,
  );
}

class TradeReportAgg {
  TradeReportAgg({
    required this.totals,
    required this.itemsBag,
    required this.itemsBox,
    required this.itemsTin,
    required this.itemsAll,
    required this.suppliers,
    required this.brokers,
    required this.purchasesIncluded,
  });

  final TradeReportTotals totals;

  /// Item rows when unit filter is Bag (columns: Bags, Kg, Amount).
  final List<TradeReportItemRow> itemsBag;

  /// Item rows for Box filter.
  final List<TradeReportItemRow> itemsBox;

  /// Item rows for Tin filter.
  final List<TradeReportItemRow> itemsTin;

  /// All pack kinds merged per item key (only populated when [buildTradeReportAgg] uses `onlyKind: null`).
  final List<TradeReportItemRow> itemsAll;

  final List<TradeReportSupplierRow> suppliers;
  final List<TradeReportBrokerRow> brokers;

  /// Purchases that contributed at least one classified line (for PDF / detail).
  final List<TradePurchase> purchasesIncluded;
}

/// Sorting for merged item lists (Items tab — All pack kinds).
enum TradeReportItemSort {
  highQty,
  latest,
}

List<TradeReportItemRow> sortTradeReportItemsAll(
  List<TradeReportItemRow> raw,
  TradeReportItemSort sort,
) {
  final list = [...raw];
  if (sort == TradeReportItemSort.latest) {
    list.sort((a, b) {
      final ad = a.lastPurchaseDate;
      final bd = b.lastPurchaseDate;
      if (ad == null && bd == null) return a.name.compareTo(b.name);
      if (ad == null) return 1;
      if (bd == null) return -1;
      final c = bd.compareTo(ad);
      if (c != 0) return c;
      return a.name.compareTo(b.name);
    });
  } else {
    list.sort((a, b) {
      final qa = a.bags + a.boxes + a.tins;
      final qb = b.bags + b.boxes + b.tins;
      if ((qa - qb).abs() > 1e-6) return qb.compareTo(qa);
      if ((a.kg - b.kg).abs() > 1e-9) return b.kg.compareTo(a.kg);
      return a.name.compareTo(b.name);
    });
  }
  return list;
}

String reportItemKey(TradePurchaseLine l) {
  final cid = (l.catalogItemId ?? '').trim();
  if (cid.isNotEmpty) return 'cid:$cid';
  return 'n:${l.itemName.trim().toLowerCase()}';
}

String reportSupplierKey(TradePurchase p) {
  final sid = (p.supplierId ?? '').trim();
  final nm = (p.supplierName ?? '').trim().isEmpty ? '-' : p.supplierName!.trim();
  return sid.isNotEmpty ? 'sid:$sid' : 'sn:${nm.toLowerCase()}';
}

String reportSupplierTitle(TradePurchase p) =>
    (p.supplierName ?? '').trim().isEmpty ? '-' : p.supplierName!.trim();

/// When [onlyKind] is set, totals and per-kind item maps only include lines of that kind.
/// When [onlyKind] is null, totals cover all classified lines and [itemsAll] merges bag/box/tin per item.
/// Suppliers: **deals** = any classified line; **bagQty/bagKg** only from BAG lines.
/// Brokers: commission from full purchase when it has classified lines and a broker.
TradeReportAgg buildTradeReportAgg(
  List<TradePurchase> purchases, {
  ReportPackKind? onlyKind,
}) {
  final active = reportActivePurchases(purchases);
  final bagMap = <String, TradeReportItemRow>{};
  final boxMap = <String, TradeReportItemRow>{};
  final tinMap = <String, TradeReportItemRow>{};
  final allMap = <String, TradeReportItemRow>{};
  final supMap = <String, TradeReportSupplierRow>{};
  final broMap = <String, TradeReportBrokerRow>{};

  var sumInr = 0.0;
  var sumBags = 0.0;
  var sumBoxes = 0.0;
  var sumTins = 0.0;
  var sumKg = 0.0;
  final dealIds = <String>{};
  final includedPurchases = <TradePurchase>[];

  void bumpItemRow(
    TradeReportItemRow row,
    TradePurchaseLine l,
    ReportPackKind pk,
    double packQty,
    double kg,
    double amt,
    TradePurchase p,
  ) {
    row.dealIds.add(p.id);
    row.kg += kg;
    row.amountInr += amt;
    final d = p.purchaseDate;
    if (row.lastPurchaseDate == null || d.isAfter(row.lastPurchaseDate!)) {
      row.lastPurchaseDate = d;
    }
    switch (pk) {
      case ReportPackKind.bag:
        row.bags += packQty;
      case ReportPackKind.box:
        row.boxes += packQty;
      case ReportPackKind.tin:
        row.tins += packQty;
    }
  }

  for (final p in active) {
    var purchaseTouchesClassified = false;
    var purchaseClassifiedInr = 0.0;

    final bid = (p.brokerId ?? '').trim();
    final bnm = (p.brokerName ?? '').trim();
    TradeReportBrokerRow? broRow;
    if (bid.isNotEmpty || bnm.isNotEmpty) {
      final bk = bid.isNotEmpty ? 'bid:$bid' : 'bn:${bnm.toLowerCase()}';
      broRow = broMap.putIfAbsent(
        bk,
        () => TradeReportBrokerRow(
          key: bk,
          name: bnm.isEmpty ? 'Broker' : bnm,
        ),
      );
    }

    final sk = reportSupplierKey(p);
    final sup = supMap.putIfAbsent(
      sk,
      () => TradeReportSupplierRow(key: sk, name: reportSupplierTitle(p)),
    );

    for (final l in p.lines) {
      final eff = reportEffectivePack(l);
      if (eff == null) continue;
      final pk = eff.kind;
      if (onlyKind != null && pk != onlyKind) continue;
      final kg = eff.kg;
      final packQty = eff.packQty;

      purchaseTouchesClassified = true;
      dealIds.add(p.id);
      sup.dealIds.add(p.id);

      final amt = reportLineAmountInr(l);
      purchaseClassifiedInr += amt;
      sumInr += amt;
      sumKg += kg;

      final ik = reportItemKey(l);
      final title = l.itemName.trim().isEmpty ? '—' : l.itemName.trim();

      if (onlyKind == null) {
        final merged = allMap.putIfAbsent(
          ik,
          () => TradeReportItemRow(key: ik, name: title),
        );
        bumpItemRow(merged, l, pk, packQty, kg, amt, p);
      }

      Map<String, TradeReportItemRow> targetMap;
      switch (pk) {
        case ReportPackKind.bag:
          targetMap = bagMap;
          sumBags += packQty;
          sup.bagQty += packQty;
          sup.bagKg += kg;
        case ReportPackKind.box:
          targetMap = boxMap;
          sumBoxes += l.qty;
        case ReportPackKind.tin:
          targetMap = tinMap;
          sumTins += l.qty;
      }

      final row = targetMap.putIfAbsent(
        ik,
        () => TradeReportItemRow(key: ik, name: title),
      );
      bumpItemRow(row, l, pk, packQty, kg, amt, p);

      if (broRow != null && broRow.purchaseIds.add(p.id)) {
        broRow.commission += tradePurchaseCommissionInr(p);
      }
    }

    if (purchaseTouchesClassified) {
      includedPurchases.add(p);
      sup.amountInr += purchaseClassifiedInr;
      if (sup.lastPurchaseDate == null ||
          p.purchaseDate.isAfter(sup.lastPurchaseDate!)) {
        sup.lastPurchaseDate = p.purchaseDate;
      }
    }
  }

  List<TradeReportItemRow> sortItems(Map<String, TradeReportItemRow> m, ReportPackKind k) {
    final list = m.values.toList();
    list.sort((a, b) {
      if (k == ReportPackKind.bag && (a.kg - b.kg).abs() > 1e-9) {
        return b.kg.compareTo(a.kg);
      }
      final qa = switch (k) {
        ReportPackKind.bag => a.bags,
        ReportPackKind.box => a.boxes,
        ReportPackKind.tin => a.tins,
      };
      final qb = switch (k) {
        ReportPackKind.bag => b.bags,
        ReportPackKind.box => b.boxes,
        ReportPackKind.tin => b.tins,
      };
      if ((qa - qb).abs() > 1e-9) return qb.compareTo(qa);
      return a.name.compareTo(b.name);
    });
    return list;
  }

  final suppliers = supMap.values.where((s) => s.dealIds.isNotEmpty).toList()
    ..sort((a, b) {
      final c = b.amountInr.compareTo(a.amountInr);
      if (c != 0) return c;
      final d = b.dealIds.length.compareTo(a.dealIds.length);
      if (d != 0) return d;
      return a.name.compareTo(b.name);
    });

  final brokers = broMap.values.toList()
    ..sort((a, b) {
      final c = b.commission.compareTo(a.commission);
      if (c != 0) return c;
      final d = b.purchaseIds.length.compareTo(a.purchaseIds.length);
      if (d != 0) return d;
      return a.name.compareTo(b.name);
    });

  final itemsAll = onlyKind == null
      ? sortTradeReportItemsAll(
          allMap.values.toList(),
          TradeReportItemSort.highQty,
        )
      : const <TradeReportItemRow>[];

  return TradeReportAgg(
    totals: TradeReportTotals(
      inr: sumInr,
      bags: sumBags,
      boxes: sumBoxes,
      tins: sumTins,
      kg: sumKg,
      deals: dealIds.length,
    ),
    itemsBag: sortItems(bagMap, ReportPackKind.bag),
    itemsBox: sortItems(boxMap, ReportPackKind.box),
    itemsTin: sortItems(tinMap, ReportPackKind.tin),
    itemsAll: itemsAll,
    suppliers: suppliers,
    brokers: brokers,
    purchasesIncluded: includedPurchases,
  );
}

/// Classified-line spend grouped by catalog category (for Reports → Categories).
class TradeReportCategoryRow {
  TradeReportCategoryRow({
    required this.categoryKey,
    required this.name,
  });

  final String categoryKey;
  final String name;
  double amountInr = 0;
  double kg = 0;
  double bagQty = 0;
  final Set<String> dealIds = {};
}

/// Maps each catalog item id to its category id, and category id → display name.
List<TradeReportCategoryRow> buildTradeReportCategoryRows(
  List<TradePurchase> purchases, {
  required Map<String, String> catalogItemIdToCategoryId,
  required Map<String, String> categoryIdToName,
}) {
  const unc = '_uncategorized';
  final m = <String, TradeReportCategoryRow>{};

  for (final p in purchases) {
    for (final l in p.lines) {
      final pk = reportClassifyPackKind(l);
      if (pk == null) continue;
      final cid = (l.catalogItemId ?? '').trim();
      final catId =
          cid.isEmpty ? unc : (catalogItemIdToCategoryId[cid] ?? unc);
      final nm = catId == unc
          ? 'Uncategorized'
          : (categoryIdToName[catId] ?? 'Category');
      final row = m.putIfAbsent(
        catId,
        () => TradeReportCategoryRow(categoryKey: catId, name: nm),
      );
      row.dealIds.add(p.id);
      row.amountInr += reportLineAmountInr(l);
      row.kg += reportLineKg(l);
      if (pk == ReportPackKind.bag) {
        row.bagQty += l.qty;
      }
    }
  }

  final list = m.values.toList()
    ..sort((a, b) {
      final c = b.amountInr.compareTo(a.amountInr);
      if (c != 0) return c;
      return a.name.compareTo(b.name);
    });
  return list;
}

/// Human-readable pack count for statement tables (bag / box / tin from unit).
String reportStatementPackLabel(TradePurchaseLine l) {
  final pk = reportClassifyPackKind(l);
  if (pk == null) return '—';
  final q = l.qty;
  final qs =
      q == q.roundToDouble() ? '${q.round()}' : q.toStringAsFixed(1);
  return switch (pk) {
    ReportPackKind.bag => '$qs bag',
    ReportPackKind.box => '$qs box',
    ReportPackKind.tin => '$qs tin',
  };
}

/// Bags column for statement PDF/table (effective bag count only).
String reportStatementBagsCell(TradePurchaseLine l) {
  final eff = reportEffectivePack(l);
  if (eff == null || eff.kind != ReportPackKind.bag) return '—';
  final q = eff.packQty;
  return q == q.roundToDouble() ? '${q.round()}' : q.toStringAsFixed(1);
}

/// Statement row for PDF/export (every classified line).
class TradeReportStatementLine {
  TradeReportStatementLine({
    required this.date,
    required this.supplierName,
    required this.itemName,
    required this.packLabel,
    required this.bagsCell,
    required this.qty,
    required this.unit,
    required this.kg,
    required this.rate,
    required this.amountInr,
  });

  final DateTime date;
  final String supplierName;
  final String itemName;
  /// Same pack semantics as report aggregates (from line unit).
  final String packLabel;
  /// Numeric bags for PDF column; '—' when line is not bag-classified.
  final String bagsCell;
  final double qty;
  final String unit;
  final double kg;
  final double rate;
  final double amountInr;
}

List<TradeReportStatementLine> buildTradeStatementLines(
    List<TradePurchase> purchases) {
  final out = <TradeReportStatementLine>[];
  for (final p in reportActivePurchases(purchases)) {
    final sup = reportSupplierTitle(p);
    for (final l in p.lines) {
      if (reportClassifyPackKind(l) == null) continue;
      final kg = reportLineKg(l);
      final amt = reportLineAmountInr(l);
      final rate = l.qty > 0 ? amt / l.qty : 0.0;
      out.add(
        TradeReportStatementLine(
          date: p.purchaseDate,
          supplierName: sup,
          itemName: l.itemName.trim().isEmpty ? '—' : l.itemName.trim(),
          packLabel: reportStatementPackLabel(l),
          bagsCell: reportStatementBagsCell(l),
          qty: l.qty,
          unit: l.unit.trim().toUpperCase(),
          kg: kg,
          rate: rate,
          amountInr: amt,
        ),
      );
    }
  }
  out.sort((a, b) {
    final c = a.date.compareTo(b.date);
    if (c != 0) return c;
    return a.itemName.compareTo(b.itemName);
  });
  return out;
}
