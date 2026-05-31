import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../../core/strict_decimal.dart';
import '../../../core/utils/unit_utils.dart';

/// How purchase/selling rates are interpreted before GST is applied on the wire.
/// Backend always stores **pre-tax** unit rates; inclusive entry is normalized client-side.
enum RateTaxBasis {
  /// Rate excludes GST; tax is added on top (default, matches backend).
  taxExtra,
  /// Rate includes GST; client strips to pre-tax before save.
  includesTax,
}

double _decimalToDouble(Object? value) {
  if (value == null) return 0;
  try {
    return StrictDecimal.fromObject(value).toDouble();
  } on FormatException {
    return 0;
  }
}

double? _decimalToNullableDouble(Object? value) {
  if (value == null) return null;
  try {
    return StrictDecimal.fromObject(value).toDouble();
  } on FormatException {
    return null;
  }
}

String _fixed(Object value, int scale) =>
    StrictDecimal.fromObject(value).format(scale);

/// API `commission_mode` values (broker header).
const String kPurchaseCommissionModePercent = 'percent';
const String kPurchaseCommissionModeFlatInvoice = 'flat_invoice';
const String kPurchaseCommissionModeFlatKg = 'flat_kg';
const String kPurchaseCommissionModeFlatBag = 'flat_bag';
const String kPurchaseCommissionModeFlatBox = 'flat_box';
const String kPurchaseCommissionModeFlatTin = 'flat_tin';

/// Picks a fixed-rupee commission basis from line units so users switch to
/// **Fixed ₹** with one less manual choice (broker still editable).
String suggestedBrokerFigureModeFromLines(List<PurchaseLineDraft> lines) {
  if (lines.isEmpty) return kPurchaseCommissionModeFlatInvoice;
  var tinQty = 0.0;
  var bagSackQty = 0.0;
  var boxQty = 0.0;
  var hasKgLikeUnit = false;
  for (final l in lines) {
    final u = l.unit.trim().toLowerCase();
    if (u == 'tin') {
      tinQty += l.qty;
    } else if (u == 'bag' || u == 'sack') {
      bagSackQty += l.qty;
    } else if (u == 'box') {
      boxQty += l.qty;
    }
    if (u.contains('kg') ||
        u == 'kgs' ||
        u == 'kilogram' ||
        u == 'g' ||
        u == 'gram' ||
        u == 'quintal' ||
        u == 'qtl') {
      hasKgLikeUnit = true;
    }
  }
  final packQty = bagSackQty + boxQty;
  if (tinQty >= packQty && tinQty > 0) {
    return kPurchaseCommissionModeFlatTin;
  }
  if (boxQty > 0 && bagSackQty <= 0) {
    return kPurchaseCommissionModeFlatBox;
  }
  if (bagSackQty > 0 && boxQty <= 0) {
    return kPurchaseCommissionModeFlatBag;
  }
  if (bagSackQty > 0 && boxQty > 0) {
    return kPurchaseCommissionModeFlatInvoice;
  }
  if (hasKgLikeUnit) return kPurchaseCommissionModeFlatKg;
  return kPurchaseCommissionModeFlatInvoice;
}

/// Hint under figure basis chips (what the bill will multiply by).
String? brokerFigureBasisLineHint(List<PurchaseLineDraft> lines, String mode) {
  final m = PurchaseDraft.normalizeCommissionMode(mode);
  if (m == kPurchaseCommissionModeFlatTin) {
    var t = 0.0;
    for (final l in lines) {
      if (l.unit.trim().toLowerCase() == 'tin') t += l.qty;
    }
    if (t <= 0) {
      return 'No tin lines yet — add “tin” lines or pick another basis.';
    }
    return 'This bill: ${formatStockQtyForUnit('tin', t)} tin qty';
  }
  if (m == kPurchaseCommissionModeFlatBag) {
    var b = 0.0;
    for (final l in lines) {
      final u = l.unit.trim().toLowerCase();
      if (u == 'bag' || u == 'sack') b += l.qty;
    }
    if (b <= 0) {
      return 'No bag lines — add “bag” lines or use per kg / once per bill.';
    }
    return 'This bill: ${formatStockQtyForUnit('bag', b)} bag qty';
  }
  if (m == kPurchaseCommissionModeFlatBox) {
    var bx = 0.0;
    for (final l in lines) {
      final u = l.unit.trim().toLowerCase();
      if (u == 'box') bx += l.qty;
    }
    if (bx <= 0) {
      return 'No box lines — add “box” lines or use per kg / once per bill.';
    }
    return 'This bill: ${formatStockQtyForUnit('box', bx)} box qty';
  }
  if (m == kPurchaseCommissionModeFlatKg) {
    return 'Uses total kg from line weights (items + qty).';
  }
  return null;
}

/// Fixed-₹ commission basis — always show all choices so Terms works before Items.
/// [lines] is kept for call-site stability; hints use it to explain qty available.
List<(String mode, String label)> brokerFigureUiOptions(
    List<PurchaseLineDraft> _) {
  return const [
    (kPurchaseCommissionModeFlatInvoice, 'Once / bill'),
    (kPurchaseCommissionModeFlatKg, 'Per kg (total kg)'),
    (kPurchaseCommissionModeFlatBag, 'Per bag'),
    (kPurchaseCommissionModeFlatBox, 'Per box'),
    (kPurchaseCommissionModeFlatTin, 'Per tin'),
  ];
}

/// If [current] fixed mode is not allowed for [lines], pick a sensible default.
String clampFigureModeToUiOptions(String current, List<PurchaseLineDraft> lines) {
  final opts = brokerFigureUiOptions(lines);
  final allowed = {for (final o in opts) o.$1};
  final c = PurchaseDraft.normalizeCommissionMode(current);
  if (allowed.contains(c)) return c;
  final s = suggestedBrokerFigureModeFromLines(lines);
  if (allowed.contains(s)) return s;
  return opts.first.$1;
}

/// API-aligned: `included` or `separate`.
@immutable
class PurchaseDraft {
  const PurchaseDraft({
    this.supplierId,
    this.supplierName,
    this.brokerId,
    this.brokerName,
    this.brokerIdFromSupplier,
    this.purchaseDate,
    this.invoiceNumber,
    this.paymentDays,
    this.headerDiscountPercent,
    this.commissionMode = kPurchaseCommissionModePercent,
    this.commissionPercent,
    this.commissionMoney,
    this.deliveredRate,
    this.billtyRate,
    this.freightAmount,
    this.freightType = 'separate',
    this.lines = const <PurchaseLineDraft>[],
  });

  final String? supplierId;
  final String? supplierName;
  final String? brokerId;
  final String? brokerName;
  /// Set when default came from selected supplier; used for broker label only.
  final String? brokerIdFromSupplier;
  final DateTime? purchaseDate;
  final String? invoiceNumber;
  final int? paymentDays;
  final double? headerDiscountPercent;
  final String commissionMode;
  final double? commissionPercent;
  final double? commissionMoney;
  final double? deliveredRate;
  final double? billtyRate;
  final double? freightAmount;
  final String freightType;
  final List<PurchaseLineDraft> lines;

  static String normalizeCommissionMode(String? raw) {
    final m = (raw ?? kPurchaseCommissionModePercent).trim().toLowerCase();
    switch (m) {
      case kPurchaseCommissionModeFlatInvoice:
      case kPurchaseCommissionModeFlatKg:
      case kPurchaseCommissionModeFlatBag:
      case kPurchaseCommissionModeFlatBox:
      case kPurchaseCommissionModeFlatTin:
        return m;
      default:
        return kPurchaseCommissionModePercent;
    }
  }

  /// Same wire shape as [PurchaseDraftNotifier.buildTradePurchaseBody] — used
  /// from scan review and other call sites without mutating provider state.
  Map<String, dynamic> toTradePurchaseCreateBody({bool forceDuplicate = false}) {
    final lines = <Map<String, dynamic>>[
      for (final l in this.lines) l.toLineMap(),
    ];
    final body = <String, dynamic>{
      'purchase_date': DateFormat('yyyy-MM-dd').format(purchaseDate ?? DateTime.now()),
      'status': 'confirmed',
      'lines': lines,
      'freight_type': freightType,
      if (forceDuplicate) 'force_duplicate': true,
    };
    if (supplierId != null && supplierId!.isNotEmpty) {
      body['supplier_id'] = supplierId;
    }
    if (brokerId != null && brokerId!.isNotEmpty) {
      body['broker_id'] = brokerId;
    }
    final pd = paymentDays;
    if (pd != null && pd >= 0) body['payment_days'] = pd;
    final hd = headerDiscountPercent;
    if (hd != null && hd > 0) body['discount'] = _fixed(hd, 2);
    body['commission_mode'] = commissionMode;
    if (commissionMode == kPurchaseCommissionModePercent) {
      final comm = commissionPercent;
      if (comm != null && comm > 0) {
        body['commission_percent'] = _fixed(comm, 2);
      }
    } else {
      final cm = commissionMoney;
      if (cm != null && cm > 0) {
        body['commission_money'] = _fixed(cm, 4);
      }
    }
    final dlr = deliveredRate;
    if (dlr != null && dlr >= 0) body['delivered_rate'] = _fixed(dlr, 2);
    final brt = billtyRate;
    if (brt != null && brt >= 0) body['billty_rate'] = _fixed(brt, 2);
    final fa = freightAmount;
    if (fa != null && fa > 0) body['freight_amount'] = _fixed(fa, 2);
    return body;
  }

  /// Replaces broker commission header fields (null-safe for API modes).
  PurchaseDraft withCommissionHeader({
    required String mode,
    double? percent,
    double? money,
  }) {
    final m = normalizeCommissionMode(mode);
    return PurchaseDraft(
      supplierId: supplierId,
      supplierName: supplierName,
      brokerId: brokerId,
      brokerName: brokerName,
      brokerIdFromSupplier: brokerIdFromSupplier,
      purchaseDate: purchaseDate,
      invoiceNumber: invoiceNumber,
      paymentDays: paymentDays,
      headerDiscountPercent: headerDiscountPercent,
      commissionMode: m,
      commissionPercent: m == kPurchaseCommissionModePercent ? percent : null,
      commissionMoney: m == kPurchaseCommissionModePercent ? null : money,
      deliveredRate: deliveredRate,
      billtyRate: billtyRate,
      freightAmount: freightAmount,
      freightType: freightType,
      lines: lines,
    );
  }

  static PurchaseDraft initial() => PurchaseDraft(
        purchaseDate: DateTime.now(),
        supplierId: null,
        supplierName: null,
        brokerId: null,
        brokerName: null,
        brokerIdFromSupplier: null,
        invoiceNumber: null,
        paymentDays: null,
        headerDiscountPercent: null,
        commissionMode: kPurchaseCommissionModePercent,
        commissionPercent: null,
        commissionMoney: null,
        deliveredRate: null,
        billtyRate: null,
        freightAmount: null,
        freightType: 'separate',
        lines: const [],
      );

  PurchaseDraft copyWith({
    String? supplierId,
    String? supplierName,
    bool clearSupplier = false,
    String? brokerId,
    String? brokerName,
    bool clearBroker = false,
    String? brokerIdFromSupplier,
    bool clearBrokerFromSupplier = false,
    DateTime? purchaseDate,
    String? invoiceNumber,
    bool clearInvoice = false,
    int? paymentDays,
    bool clearPaymentDays = false,
    double? headerDiscountPercent,
    bool clearHeaderDiscount = false,
    String? commissionMode,
    double? commissionPercent,
    bool clearCommission = false,
    double? commissionMoney,
    bool clearCommissionMoney = false,
    double? deliveredRate,
    bool clearDelivered = false,
    double? billtyRate,
    bool clearBillty = false,
    double? freightAmount,
    bool clearFreight = false,
    String? freightType,
    List<PurchaseLineDraft>? lines,
  }) {
    return PurchaseDraft(
      supplierId: clearSupplier ? null : (supplierId ?? this.supplierId),
      supplierName: clearSupplier ? null : (supplierName ?? this.supplierName),
      brokerId: clearBroker ? null : (brokerId ?? this.brokerId),
      brokerName: clearBroker ? null : (brokerName ?? this.brokerName),
      brokerIdFromSupplier: clearBrokerFromSupplier
          ? null
          : (brokerIdFromSupplier ?? this.brokerIdFromSupplier),
      purchaseDate: purchaseDate ?? this.purchaseDate,
      invoiceNumber: clearInvoice ? null : (invoiceNumber ?? this.invoiceNumber),
      paymentDays: clearPaymentDays ? null : (paymentDays ?? this.paymentDays),
      headerDiscountPercent: clearHeaderDiscount
          ? null
          : (headerDiscountPercent ?? this.headerDiscountPercent),
      commissionMode: clearCommission
          ? kPurchaseCommissionModePercent
          : (commissionMode ?? this.commissionMode),
      commissionPercent:
          clearCommission ? null : (commissionPercent ?? this.commissionPercent),
      commissionMoney: clearCommission || clearCommissionMoney
          ? null
          : (commissionMoney ?? this.commissionMoney),
      deliveredRate: clearDelivered ? null : (deliveredRate ?? this.deliveredRate),
      billtyRate: clearBillty ? null : (billtyRate ?? this.billtyRate),
      freightAmount: clearFreight ? null : (freightAmount ?? this.freightAmount),
      freightType: freightType ?? this.freightType,
      lines: lines ?? this.lines,
    );
  }
}

@immutable
class PurchaseLineDraft {
  const PurchaseLineDraft({
    this.catalogItemId,
    required this.itemName,
    required this.qty,
    required this.unit,
    required this.landingCost,
    this.kgPerUnit,
    this.landingCostPerKg,
    this.sellingPrice,
    this.taxPercent,
    this.lineDiscountPercent,
    this.freightType,
    this.freightValue,
    this.deliveredRate,
    this.billtyRate,
    this.boxMode,
    this.itemsPerBox,
    this.weightPerItem,
    this.kgPerBox,
    this.weightPerTin,
    this.hsnCode,
    this.itemCode,
    this.description,
  });

  final String? catalogItemId;
  final String itemName;
  final double qty;
  final String unit;
  /// Per *line* unit when not using explicit kg fields, or derived `kg_per_unit * landing_cost_per_kg` for weight lines.
  final double landingCost;
  /// Snapshot: kg per bag when [unit] is bag (legacy: `sack` is normalized to `bag`).
  final double? kgPerUnit;
  /// Rupees per kg when [kgPerUnit] is set.
  final double? landingCostPerKg;
  final double? sellingPrice;
  final double? taxPercent;
  final double? lineDiscountPercent;
  final String? freightType;
  final double? freightValue;
  final double? deliveredRate;
  final double? billtyRate;
  final String? boxMode;
  final double? itemsPerBox;
  final double? weightPerItem;
  final double? kgPerBox;
  final double? weightPerTin;
  /// Carried for GST lines; from catalog or edited purchase line.
  final String? hsnCode;
  final String? itemCode;
  final String? description;

  Map<String, dynamic> toLineMap() {
    final m = <String, dynamic>{
      'item_name': itemName,
      'qty': _fixed(qty, 3),
      'unit': unit,
      'purchase_rate': _fixed(landingCost, 2),
      'landing_cost': _fixed(landingCost, 2),
    };
    if (catalogItemId != null && catalogItemId!.isNotEmpty) {
      m['catalog_item_id'] = catalogItemId;
    }
    if (kgPerUnit != null) {
      m['weight_per_unit'] = _fixed(kgPerUnit!, 3);
      m['kg_per_unit'] = _fixed(kgPerUnit!, 3);
    }
    if (landingCostPerKg != null) {
      m['landing_cost_per_kg'] = _fixed(landingCostPerKg!, 2);
    }
    if (sellingPrice != null) {
      m['selling_rate'] = _fixed(sellingPrice!, 2);
      m['selling_cost'] = _fixed(sellingPrice!, 2);
    }
    if (freightType == 'included' || freightType == 'separate') {
      m['freight_type'] = freightType;
    }
    if (freightValue != null) m['freight_value'] = _fixed(freightValue!, 2);
    if (deliveredRate != null) m['delivered_rate'] = _fixed(deliveredRate!, 2);
    if (billtyRate != null) m['billty_rate'] = _fixed(billtyRate!, 2);
    if (boxMode != null && boxMode!.trim().isNotEmpty) m['box_mode'] = boxMode;
    if (itemsPerBox != null) m['items_per_box'] = _fixed(itemsPerBox!, 3);
    if (weightPerItem != null) m['weight_per_item'] = _fixed(weightPerItem!, 3);
    if (kgPerBox != null) m['kg_per_box'] = _fixed(kgPerBox!, 3);
    if (weightPerTin != null) m['weight_per_tin'] = _fixed(weightPerTin!, 3);
    if (taxPercent != null) m['tax_percent'] = _fixed(taxPercent!, 2);
    if (lineDiscountPercent != null) {
      m['discount'] = _fixed(lineDiscountPercent!, 2);
    }
    if (hsnCode != null && hsnCode!.trim().isNotEmpty) {
      m['hsn_code'] = hsnCode!.trim();
    }
    if (itemCode != null && itemCode!.trim().isNotEmpty) {
      m['item_code'] = itemCode!.trim();
    }
    final descOut = description?.trim() ?? '';
    if (descOut.isNotEmpty) m['description'] = descOut;
    return m;
  }

  static PurchaseLineDraft fromLineMap(Map<String, dynamic> e) {
    final rawHsn = e['hsn_code']?.toString().trim() ?? '';
    final rawIc = e['item_code']?.toString().trim() ?? '';
    final rawDesc = e['description']?.toString().trim() ?? '';
    return PurchaseLineDraft(
      catalogItemId: e['catalog_item_id']?.toString(),
      itemName: e['item_name']?.toString() ?? '',
      qty: _decimalToDouble(e['qty']),
      unit: e['unit']?.toString() ?? 'kg',
      landingCost: _decimalToDouble(e['purchase_rate'] ?? e['landing_cost']),
      kgPerUnit: _decimalToNullableDouble(e['weight_per_unit'] ?? e['kg_per_unit']),
      landingCostPerKg: _decimalToNullableDouble(e['landing_cost_per_kg']),
      sellingPrice: _decimalToNullableDouble(e['selling_rate'] ?? e['selling_cost']),
      taxPercent: _decimalToNullableDouble(e['tax_percent']),
      lineDiscountPercent: _decimalToNullableDouble(e['discount']),
      freightType: e['freight_type']?.toString(),
      freightValue: _decimalToNullableDouble(e['freight_value'] ?? e['freight_amount']),
      deliveredRate: _decimalToNullableDouble(e['delivered_rate']),
      billtyRate: _decimalToNullableDouble(e['billty_rate']),
      boxMode: e['box_mode']?.toString(),
      itemsPerBox: _decimalToNullableDouble(e['items_per_box']),
      weightPerItem: _decimalToNullableDouble(e['weight_per_item']),
      kgPerBox: _decimalToNullableDouble(e['kg_per_box']),
      weightPerTin: _decimalToNullableDouble(e['weight_per_tin']),
      hsnCode: rawHsn.isEmpty ? null : rawHsn,
      itemCode: rawIc.isEmpty ? null : rawIc,
      description: rawDesc.isEmpty ? null : rawDesc,
    );
  }
}

bool _isBagUnit(String unit) {
  final x = unit.trim().toLowerCase();
  // Back-compat: treat legacy `sack` as canonical `bag`.
  return x == 'bag' || x == 'sack';
}

bool _isBoxUnit(String unit) => unit.trim().toLowerCase() == 'box';
bool _isTinUnit(String unit) => unit.trim().toLowerCase() == 'tin';

bool _isPieceUnit(String unit) {
  final x = unit.trim().toLowerCase();
  return x == 'piece' || x == 'pcs' || x == 'pieces';
}

/// First validation failure for [l] that would also fail API line rules, or null
/// when the line is save-ready (aligned with [TradePurchase] create/update).
///
/// Master rebuild rules:
/// - kg / bag / box / tin only (legacy `sack` accepted as `bag` for read).
/// - BAG must have `kg_per_unit` (+ rate). The entry sheet auto-detects from name
///   (e.g. "SUGAR 50 KG" → 50). [Bug 2 fix]
/// - BOX / TIN are count-only — no kg fields required, no items-per-box, no
///   weight-per-item, no kg-per-box, no weight-per-tin. [Bug 1 fix]
String? purchaseLineSaveBlockReason(PurchaseLineDraft l) {
  if ((l.catalogItemId ?? '').trim().isEmpty) {
    return 'Pick the item from the list (free-typed items cannot be saved).';
  }
  if (l.itemName.trim().isEmpty) {
    return 'Item name is required.';
  }
  if (l.unit.trim().isEmpty) {
    return 'Unit is required.';
  }
  if (l.qty <= 0) {
    return 'Quantity must be greater than 0.';
  }
  final kpu = l.kgPerUnit;
  final pk = l.landingCostPerKg;
  final weightLine = kpu != null || pk != null;
  final unitIsBag = _isBagUnit(l.unit);
  final unitIsBox = _isBoxUnit(l.unit);
  final unitIsTin = _isTinUnit(l.unit);
  final unitIsPiece = _isPieceUnit(l.unit);
  if (unitIsBag || unitIsBox || unitIsTin || unitIsPiece) {
    if ((l.qty - l.qty.roundToDouble()).abs() > 1e-6) {
      return 'Use a whole number quantity for ${l.unit.trim()} lines (no decimals).';
    }
  }
  // BOX & TIN are count-only in master rebuild default wholesale mode.
  // Only require qty > 0 + a positive landing cost.
  if (unitIsBox || unitIsTin) {
    if (l.landingCost <= 0) {
      return 'Purchase rate must be greater than 0.';
    }
    return null;
  }
  if (unitIsPiece) {
    if (l.landingCost <= 0) {
      return 'Purchase rate must be greater than 0.';
    }
    return null;
  }
  if (weightLine || unitIsBag) {
    if (kpu == null || kpu <= 0) {
      return unitIsBag
          ? 'Kg per bag is required for this unit.'
          : 'Kg per unit must be greater than 0.';
    }
    if (pk == null || pk <= 0) {
      return 'Per-kg cost must be greater than 0.';
    }
  } else if (l.landingCost <= 0) {
    return 'Landing cost must be greater than 0.';
  }
  final tax = l.taxPercent ?? 0;
  if (tax > 0) {
    if ((l.hsnCode ?? '').trim().isEmpty) {
      return 'HSN code is required for taxed items (tax% > 0).';
    }
  }
  return null;
}

/// True when qty, name, unit, and money inputs match API rules for saved lines.
bool purchaseLineIsValidForSave(PurchaseLineDraft l) =>
    purchaseLineSaveBlockReason(l) == null;

/// Seeds the wizard from AI assistant `entry_draft` / chat preview JSON.
PurchaseDraft purchaseDraftFromAssistantEntryMap(Map<String, dynamic> d) {
  final linesRaw = d['lines'];
  final lines = <PurchaseLineDraft>[];
  if (linesRaw is List) {
    for (final e in linesRaw) {
      if (e is Map) {
        lines.add(PurchaseLineDraft.fromLineMap(Map<String, dynamic>.from(e)));
      }
    }
  }
  DateTime? pd;
  final pds = d['purchase_date']?.toString();
  if (pds != null && pds.isNotEmpty) {
    pd = DateTime.tryParse(pds);
  }
  return PurchaseDraft(
    supplierId: d['supplier_id']?.toString(),
    supplierName: d['supplier_name']?.toString(),
    brokerId: d['broker_id']?.toString(),
    brokerName: d['broker_name']?.toString(),
    purchaseDate: pd,
    invoiceNumber: d['invoice_number']?.toString(),
    paymentDays: int.tryParse(d['payment_days']?.toString() ?? ''),
    lines: lines,
  );
}

/// Strict footer / invoice-style row breakdown (mirrors prior wizard `\_strictFooterBreakdown`).
@immutable
class PurchaseStrictBreakdown {
  const PurchaseStrictBreakdown({
    required this.subtotalGross,
    required this.taxTotal,
    required this.discountTotal,
    required this.freight,
    required this.commission,
    required this.grand,
  });
  final double subtotalGross;
  final double taxTotal;
  final double discountTotal;
  final double freight;
  final double commission;
  final double grand;
}
