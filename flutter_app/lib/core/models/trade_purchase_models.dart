import 'package:flutter/material.dart';

import '../json_coerce.dart';
import '../strict_decimal.dart';
import '../design_system/hexa_operational_tokens.dart';
import '../theme/hexa_colors.dart';

double _decDouble(Object? value) {
  if (value == null) return 0;
  try {
    return StrictDecimal.fromObject(value).toDouble();
  } on FormatException {
    return 0;
  }
}

double? _decNullableDouble(Object? value) {
  if (value == null) return null;
  try {
    return StrictDecimal.fromObject(value).toDouble();
  } on FormatException {
    return null;
  }
}

Map<String, dynamic>? _mapFromDynamic(Object? value) {
  if (value == null) return null;
  if (value is Map<String, dynamic>) return Map<String, dynamic>.from(value);
  if (value is Map) {
    return value.map((k, v) => MapEntry(k.toString(), v));
  }
  return null;
}

/// Mirrors backend lifecycle + [parsePurchaseStatus].
enum PurchaseStatus {
  draft,
  saved,
  confirmed,
  partiallyPaid,
  paid,
  overdue,
  dueSoon,
  cancelled,
  deleted,
  unknown,
}

extension PurchaseStatusX on PurchaseStatus {
  String get apiValue => switch (this) {
        PurchaseStatus.draft => 'draft',
        PurchaseStatus.saved => 'saved',
        PurchaseStatus.confirmed => 'confirmed',
        PurchaseStatus.partiallyPaid => 'partially_paid',
        PurchaseStatus.paid => 'paid',
        PurchaseStatus.overdue => 'overdue',
        PurchaseStatus.dueSoon => 'due_soon',
        PurchaseStatus.cancelled => 'cancelled',
        PurchaseStatus.deleted => 'deleted',
        PurchaseStatus.unknown => 'unknown',
      };

  String get label => switch (this) {
        PurchaseStatus.draft => 'Draft',
        PurchaseStatus.saved => 'Saved',
        PurchaseStatus.confirmed => 'Pending',
        PurchaseStatus.partiallyPaid => 'Partial',
        PurchaseStatus.paid => 'Paid',
        PurchaseStatus.overdue => 'Overdue',
        PurchaseStatus.dueSoon => 'Due soon',
        PurchaseStatus.cancelled => 'Cancelled',
        PurchaseStatus.deleted => 'Deleted',
        PurchaseStatus.unknown => '—',
      };

  Color get color => switch (this) {
        PurchaseStatus.paid => HexaColors.brandAccent,
        PurchaseStatus.overdue => HexaColors.loss,
        PurchaseStatus.dueSoon => const Color(0xFFF59E0B),
        PurchaseStatus.partiallyPaid => const Color(0xFFF59E0B),
        PurchaseStatus.draft => HexaColors.neutral,
        PurchaseStatus.saved => HexaColors.neutral,
        PurchaseStatus.confirmed => HexaColors.profit,
        PurchaseStatus.cancelled => HexaColors.loss,
        PurchaseStatus.deleted => HexaColors.neutral,
        PurchaseStatus.unknown => HexaColors.neutral,
      };

}

PurchaseStatus parsePurchaseStatus(String? raw) {
  final s = (raw ?? '').toLowerCase().trim();
  return switch (s) {
    'draft' => PurchaseStatus.draft,
    'saved' => PurchaseStatus.saved,
    'confirmed' => PurchaseStatus.confirmed,
    'partially_paid' => PurchaseStatus.partiallyPaid,
    'paid' => PurchaseStatus.paid,
    'overdue' => PurchaseStatus.overdue,
    'due_soon' => PurchaseStatus.dueSoon,
    'cancelled' => PurchaseStatus.cancelled,
    'deleted' => PurchaseStatus.deleted,
    _ => PurchaseStatus.unknown,
  };
}

/// Warehouse delivery track (independent of payment status).
enum DeliveryStatus {
  pending,
  dispatched,
  inTransit,
  arrived,
  staffVerifying,
  staffVerified,
  stockCommitted,
  partial,
  cancelled,
}

extension DeliveryStatusX on DeliveryStatus {
  String get wireValue => switch (this) {
        DeliveryStatus.pending => 'pending',
        DeliveryStatus.dispatched => 'dispatched',
        DeliveryStatus.inTransit => 'in_transit',
        DeliveryStatus.arrived => 'arrived',
        DeliveryStatus.staffVerifying => 'staff_verifying',
        DeliveryStatus.staffVerified => 'staff_verified',
        DeliveryStatus.stockCommitted => 'stock_committed',
        DeliveryStatus.partial => 'partial',
        DeliveryStatus.cancelled => 'cancelled',
      };

  String get label => switch (this) {
        DeliveryStatus.pending => 'Pending delivery',
        DeliveryStatus.dispatched => 'Dispatched',
        DeliveryStatus.inTransit => 'In transit',
        DeliveryStatus.arrived => 'Arrived — verify',
        DeliveryStatus.staffVerifying => 'Being verified',
        DeliveryStatus.staffVerified => 'Verified — commit',
        DeliveryStatus.stockCommitted => 'Stock added',
        DeliveryStatus.partial => 'Partial delivery',
        DeliveryStatus.cancelled => 'Cancelled',
      };

  Color get color => switch (this) {
        DeliveryStatus.pending => HexaOp.statusPending,
        DeliveryStatus.dispatched => HexaOp.statusDispatched,
        DeliveryStatus.inTransit => HexaOp.statusDispatched,
        DeliveryStatus.arrived => HexaOp.statusArrived,
        DeliveryStatus.staffVerifying => HexaOp.statusArrived,
        DeliveryStatus.staffVerified => HexaOp.statusVerified,
        DeliveryStatus.stockCommitted => HexaOp.statusCommitted,
        DeliveryStatus.partial => HexaOp.statusPartial,
        DeliveryStatus.cancelled => HexaColors.loss,
      };

  bool get needsStaffAction =>
      this == DeliveryStatus.arrived || this == DeliveryStatus.staffVerifying;

  bool get readyForOwnerCommit =>
      this == DeliveryStatus.staffVerified || this == DeliveryStatus.partial;

  IconData get icon => switch (this) {
        DeliveryStatus.pending => Icons.schedule_rounded,
        DeliveryStatus.dispatched => Icons.local_shipping_outlined,
        DeliveryStatus.inTransit => Icons.pin_drop_outlined,
        DeliveryStatus.arrived => Icons.inventory_2_outlined,
        DeliveryStatus.staffVerifying => Icons.fact_check_outlined,
        DeliveryStatus.staffVerified => Icons.verified_outlined,
        DeliveryStatus.stockCommitted => Icons.check_circle_outline_rounded,
        DeliveryStatus.partial => Icons.call_split_rounded,
        DeliveryStatus.cancelled => Icons.cancel_outlined,
      };
}

DeliveryStatus parseDeliveryStatus(String? raw) {
  final s = (raw ?? '').toLowerCase().trim();
  return switch (s) {
    'pending' => DeliveryStatus.pending,
    'dispatched' => DeliveryStatus.dispatched,
    'in_transit' => DeliveryStatus.inTransit,
    'arrived' => DeliveryStatus.arrived,
    'staff_verifying' => DeliveryStatus.staffVerifying,
    'staff_verified' => DeliveryStatus.staffVerified,
    'stock_committed' => DeliveryStatus.stockCommitted,
    'partial' => DeliveryStatus.partial,
    'cancelled' => DeliveryStatus.cancelled,
    _ => DeliveryStatus.pending,
  };
}

class TradePurchaseLine {
  const TradePurchaseLine({
    required this.id,
    required this.itemName,
    required this.qty,
    required this.unit,
    required this.landingCost,
    this.purchaseRate,
    this.sellingRate,
    this.freightType,
    this.freightValue,
    this.deliveredRate,
    this.billtyRate,
    this.totalWeight,
    this.lineTotal,
    this.lineLandingGross,
    this.profit,
    this.sellingCost,
    this.discount,
    this.taxPercent,
    this.catalogItemId,
    this.receivedQty,
    this.qtyInStockUnit,
    this.hsnCode,
    this.itemCode,
    this.paymentDays,
    this.description,
    this.defaultUnit,
    this.defaultKgPerBag,
    this.defaultPurchaseUnit,
    this.kgPerUnit,
    this.landingCostPerKg,
    this.boxMode,
    this.itemsPerBox,
    this.weightPerItem,
    this.kgPerBox,
    this.weightPerTin,
    this.rateContext,
  });

  final String id;
  final String itemName;
  final double qty;
  final String unit;
  final double landingCost;
  final double? purchaseRate;
  final double? sellingRate;
  final String? freightType;
  final double? freightValue;
  final double? deliveredRate;
  final double? billtyRate;
  final double? totalWeight;
  /// Tax/discount-inclusive line purchase (API `line_total`); not pre-tax gross.
  final double? lineTotal;
  /// Pre-discount / pre-tax landing gross (API `line_landing_gross`).
  final double? lineLandingGross;
  final double? profit;
  /// When set, line was priced as qty × kg_per_unit × landing_cost_per_kg.
  final double? kgPerUnit;
  final double? landingCostPerKg;
  final double? sellingCost;
  final double? discount;
  final double? taxPercent;
  final String? catalogItemId;
  final double? receivedQty;
  /// Persisted stock-unit qty snapshot (backend commit-stock SSOT when set).
  final double? qtyInStockUnit;
  final String? hsnCode;
  final String? itemCode;
  final int? paymentDays;
  final String? description;
  /// From catalog when line is linked; used for BAG/kg display and edit wizard.
  final String? defaultUnit;
  final double? defaultKgPerBag;
  final String? defaultPurchaseUnit;
  final String? boxMode;
  final double? itemsPerBox;
  final double? weightPerItem;
  final double? kgPerBox;
  final double? weightPerTin;
  /// Server `rate_context` for labels (₹/bag vs ₹/kg); optional on older payloads.
  final Map<String, dynamic>? rateContext;

  factory TradePurchaseLine.fromJson(Map<String, dynamic> j) {
    return TradePurchaseLine(
      id: j['id']?.toString() ?? '',
      itemName: j['item_name']?.toString() ?? '',
      qty: _decDouble(j['qty']),
      unit: j['unit']?.toString() ?? '',
      landingCost: _decDouble(j['landing_cost'] ?? j['purchase_rate']),
      purchaseRate: _decNullableDouble(j['purchase_rate'] ?? j['landing_cost']),
      sellingRate: _decNullableDouble(j['selling_rate'] ?? j['selling_cost']),
      freightType: j['freight_type']?.toString(),
      freightValue: _decNullableDouble(j['freight_value'] ?? j['freight_amount']),
      deliveredRate: _decNullableDouble(j['delivered_rate']),
      billtyRate: _decNullableDouble(j['billty_rate']),
      totalWeight: _decNullableDouble(j['total_weight']),
      lineTotal: _decNullableDouble(j['line_total']),
      lineLandingGross: _decNullableDouble(j['line_landing_gross']),
      profit: _decNullableDouble(j['profit']),
      sellingCost: _decNullableDouble(j['selling_cost'] ?? j['selling_rate']),
      discount: _decNullableDouble(j['discount']),
      taxPercent: _decNullableDouble(j['tax_percent']),
      catalogItemId: j['catalog_item_id']?.toString(),
      receivedQty: _decNullableDouble(j['received_qty']),
      qtyInStockUnit: _decNullableDouble(j['qty_in_stock_unit']),
      hsnCode: j['hsn_code']?.toString(),
      itemCode: j['item_code']?.toString(),
      paymentDays: coerceToIntNullable(j['payment_days']),
      description: j['description']?.toString(),
      defaultUnit: j['default_unit']?.toString(),
      defaultKgPerBag: _decNullableDouble(j['default_kg_per_bag']),
      defaultPurchaseUnit: j['default_purchase_unit']?.toString(),
      kgPerUnit: _decNullableDouble(j['kg_per_unit'] ?? j['weight_per_unit']),
      landingCostPerKg: _decNullableDouble(j['landing_cost_per_kg']),
      boxMode: j['box_mode']?.toString(),
      itemsPerBox: _decNullableDouble(j['items_per_box']),
      weightPerItem: _decNullableDouble(j['weight_per_item']),
      kgPerBox: _decNullableDouble(j['kg_per_box']),
      weightPerTin: _decNullableDouble(j['weight_per_tin']),
      rateContext: _mapFromDynamic(j['rate_context']),
    );
  }

  /// Gross landing value for the line (pre-discount / pre-tax; matches backend `line_landing_gross`).
  double get landingGross {
    if (lineLandingGross != null) return lineLandingGross!;
    final landing = purchaseRate ?? landingCost;
    if (kgPerUnit != null &&
        landingCostPerKg != null &&
        kgPerUnit! > 0 &&
        landingCostPerKg! > 0) {
      final derived = kgPerUnit! * landingCostPerKg!;
      if ((derived - landing).abs() <= 0.05 + 1e-9) {
        return qty * kgPerUnit! * landingCostPerKg!;
      }
    }
    return qty * landing;
  }

  /// Gross selling value for the line.
  /// Uses direct per-unit multiplication when selling rate is per-bag/box/unit.
  /// Only multiplies by [kgPerUnit] when the rate is clearly per-kg scale
  /// (similar magnitude to [landingCostPerKg], not per-bag scale).
  double get sellingGross {
    final rate = sellingRate ?? sellingCost;
    if (rate == null) return 0;
    if (kgPerUnit != null &&
        kgPerUnit! > 0 &&
        landingCostPerKg != null &&
        landingCostPerKg! > 0) {
      final directRatio = rate / landingCostPerKg!;
      if (directRatio >= 0.5 && directRatio <= 2.0) {
        return qty * kgPerUnit! * rate;
      }
    }
    return qty * rate;
  }

  /// Profit for this line when selling is recorded.
  double? get lineProfit {
    if (profit != null) return profit;
    if ((sellingRate ?? sellingCost) == null) return null;
    return sellingGross - landingGross;
  }
}

String _normTradePurchaseCommissionMode(String? raw) {
  final m = (raw ?? 'percent').trim().toLowerCase();
  switch (m) {
    case 'flat_invoice':
    case 'flat_kg':
    case 'flat_bag':
    case 'flat_box':
    case 'flat_tin':
      return m;
    default:
      return 'percent';
  }
}

class TradePurchase {
  TradePurchase({
    required this.id,
    required this.humanId,
    this.invoiceNumber,
    required this.purchaseDate,
    this.supplierId,
    this.brokerId,
    this.paymentDays,
    this.dueDate,
    required this.paidAmount,
    this.paidAt,
    required this.totalAmount,
    required this.storedStatus,
    required this.derivedStatus,
    required this.remaining,
    this.itemsCount = 0,
    this.supplierName,
    this.brokerName,
    this.supplierGst,
    this.supplierAddress,
    this.supplierPhone,
    this.supplierWhatsapp,
    this.brokerPhone,
    this.brokerLocation,
    this.brokerImageUrl,
    this.discount,
    this.commissionMode = 'percent',
    this.commissionPercent,
    this.commissionMoney,
    this.deliveredRate,
    this.billtyRate,
    this.freightAmount,
    this.freightType,
    this.lines = const [],
    this.createdAt,
    this.updatedAt,
    this.totalLandingSubtotal,
    this.totalSellingSubtotal,
    this.totalLineProfit,
    this.hasMissingDetails = false,
    this.isDelivered = false,
    this.deliveryStatus,
    this.deliveredAt,
    this.deliveryNotes,
    this.dispatchedAt,
    this.arrivedAt,
    this.staffVerifiedAt,
    this.staffVerifiedByName,
    this.stockCommittedAt,
    this.staffVerifiedQty,
    this.deliveredQtyCommitted,
    this.dispatchNote,
    this.truckNumber,
    this.driverContact,
    this.stockUpdatesCount = 0,
  });

  final String id;
  final String humanId;
  final String? invoiceNumber;
  final DateTime purchaseDate;
  final String? supplierId;
  final String? brokerId;
  final int? paymentDays;
  final DateTime? dueDate;
  final double paidAmount;
  final DateTime? paidAt;
  final double totalAmount;
  final String storedStatus;
  final String derivedStatus;
  final double remaining;
  final int itemsCount;
  final String? supplierName;
  final String? brokerName;
  final String? supplierGst;
  final String? supplierAddress;
  final String? supplierPhone;
  final String? supplierWhatsapp;
  final String? brokerPhone;
  final String? brokerLocation;
  final String? brokerImageUrl;
  final double? discount;
  final String commissionMode;
  final double? commissionPercent;
  final double? commissionMoney;
  final double? deliveredRate;
  final double? billtyRate;
  final double? freightAmount;
  final String? freightType;
  final List<TradePurchaseLine> lines;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final double? totalLandingSubtotal;
  final double? totalSellingSubtotal;
  final double? totalLineProfit;
  final bool hasMissingDetails;
  final bool isDelivered;
  /// Wire: `delivery_status` (pending, dispatched, stock_committed, …).
  final String? deliveryStatus;
  final DateTime? deliveredAt;
  final String? deliveryNotes;
  final DateTime? dispatchedAt;
  final DateTime? arrivedAt;
  final DateTime? staffVerifiedAt;
  final String? staffVerifiedByName;
  final DateTime? stockCommittedAt;
  final double? staffVerifiedQty;
  final double? deliveredQtyCommitted;
  final String? dispatchNote;
  final String? truckNumber;
  final String? driverContact;
  final int stockUpdatesCount;

  PurchaseStatus get statusEnum => parsePurchaseStatus(derivedStatus);

  DeliveryStatus get deliveryStatusEnum =>
      parseDeliveryStatus(deliveryStatus);

  bool get isDeliveryCommitted =>
      deliveryStatusEnum == DeliveryStatus.stockCommitted;

  String get itemsSummary {
    if (lines.isEmpty) return '';
    final names = lines.take(3).map((e) => e.itemName).join(', ');
    return lines.length > 3 ? '$names…' : names;
  }

  factory TradePurchase.fromJson(Map<String, dynamic> j) {
    DateTime? parseD(String? k) {
      final v = j[k]?.toString();
      if (v == null || v.isEmpty) return null;
      return DateTime.tryParse(v);
    }

    final linesRaw = j['lines'];
    final lines = <TradePurchaseLine>[];
    if (linesRaw is List) {
      for (final e in linesRaw) {
        if (e is Map) {
          lines.add(TradePurchaseLine.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }

    final pd = parseD('purchase_date') ??
        parseD('purchaseDate') ??
        DateTime.now();
    final cm = _normTradePurchaseCommissionMode(j['commission_mode']?.toString());
    final cPct = _decNullableDouble(j['commission_percent']);
    final cMoney = _decNullableDouble(j['commission_money']);

    return TradePurchase(
      id: j['id']?.toString() ?? '',
      humanId: j['human_id']?.toString() ?? j['humanId']?.toString() ?? '',
      invoiceNumber: j['invoice_number']?.toString(),
      purchaseDate: pd,
      supplierId: j['supplier_id']?.toString(),
      brokerId: j['broker_id']?.toString(),
      paymentDays: coerceToIntNullable(j['payment_days']),
      dueDate: parseD('due_date'),
      paidAmount: _decDouble(j['paid_amount']),
      paidAt: parseD('paid_at'),
      totalAmount: _decDouble(j['total_amount']),
      totalLandingSubtotal: _decNullableDouble(j['total_landing_subtotal']),
      totalSellingSubtotal: _decNullableDouble(j['total_selling_subtotal']),
      totalLineProfit: _decNullableDouble(j['total_line_profit']),
      storedStatus: j['status']?.toString() ?? 'confirmed',
      derivedStatus:
          j['derived_status']?.toString() ?? j['status']?.toString() ?? 'confirmed',
      remaining: _decNullableDouble(j['remaining']) ??
          _decDouble(j['total_amount']) - _decDouble(j['paid_amount']),
      itemsCount: coerceToInt(j['items_count'], fallback: lines.length),
      supplierName: j['supplier_name']?.toString() ?? j['supplierName']?.toString(),
      brokerName: j['broker_name']?.toString() ?? j['brokerName']?.toString(),
      supplierGst: j['supplier_gst']?.toString(),
      supplierAddress: j['supplier_address']?.toString(),
      supplierPhone: j['supplier_phone']?.toString(),
      supplierWhatsapp: j['supplier_whatsapp']?.toString(),
      brokerPhone: j['broker_phone']?.toString(),
      brokerLocation: j['broker_location']?.toString(),
      brokerImageUrl: j['broker_image_url']?.toString(),
      discount: _decNullableDouble(j['discount']),
      commissionMode: cm,
      commissionPercent: cm == 'percent' ? cPct : null,
      commissionMoney: cm != 'percent' ? cMoney : null,
      deliveredRate: _decNullableDouble(j['delivered_rate']),
      billtyRate: _decNullableDouble(j['billty_rate']),
      freightAmount: _decNullableDouble(j['freight_amount'] ?? j['freight_value']),
      freightType: j['freight_type']?.toString(),
      lines: lines,
      createdAt: parseD('created_at'),
      updatedAt: parseD('updated_at'),
      hasMissingDetails: j['has_missing_details'] == true ||
          j['has_missing_details']?.toString().toLowerCase() == 'true',
      isDelivered: (j['is_delivered'] as bool?) ?? false,
      deliveryStatus: j['delivery_status']?.toString() ??
          ((j['is_delivered'] as bool?) == true ? 'arrived' : 'pending'),
      deliveredAt: j['delivered_at'] != null
          ? DateTime.tryParse(j['delivered_at'].toString())
          : null,
      deliveryNotes: j['delivery_notes']?.toString(),
      dispatchedAt: parseD('dispatched_at'),
      arrivedAt: parseD('arrived_at'),
      staffVerifiedAt: parseD('staff_verified_at'),
      staffVerifiedByName: j['staff_verified_by_name']?.toString(),
      stockCommittedAt: parseD('stock_committed_at'),
      staffVerifiedQty: _decNullableDouble(j['staff_verified_qty']),
      deliveredQtyCommitted: _decNullableDouble(j['delivered_qty_committed']),
      dispatchNote: j['dispatch_note']?.toString(),
      truckNumber: j['truck_number']?.toString(),
      driverContact: j['driver_contact']?.toString(),
      stockUpdatesCount:
          j['stock_updates'] is List ? (j['stock_updates'] as List).length : 0,
    );
  }

  TradePurchase copyWith({
    String? id,
    String? humanId,
    String? invoiceNumber,
    DateTime? purchaseDate,
    String? supplierId,
    String? brokerId,
    int? paymentDays,
    DateTime? dueDate,
    double? paidAmount,
    DateTime? paidAt,
    double? totalAmount,
    String? storedStatus,
    String? derivedStatus,
    double? remaining,
    int? itemsCount,
    String? supplierName,
    String? brokerName,
    String? supplierGst,
    String? supplierAddress,
    String? supplierPhone,
    String? supplierWhatsapp,
    String? brokerPhone,
    String? brokerLocation,
    String? brokerImageUrl,
    double? discount,
    String? commissionMode,
    double? commissionPercent,
    double? commissionMoney,
    double? deliveredRate,
    double? billtyRate,
    double? freightAmount,
    String? freightType,
    List<TradePurchaseLine>? lines,
    DateTime? createdAt,
    DateTime? updatedAt,
    double? totalLandingSubtotal,
    double? totalSellingSubtotal,
    double? totalLineProfit,
    bool? hasMissingDetails,
    bool? isDelivered,
    String? deliveryStatus,
    DateTime? deliveredAt,
    String? deliveryNotes,
    DateTime? dispatchedAt,
    DateTime? arrivedAt,
    DateTime? staffVerifiedAt,
    String? staffVerifiedByName,
    DateTime? stockCommittedAt,
    double? staffVerifiedQty,
    double? deliveredQtyCommitted,
    String? dispatchNote,
    String? truckNumber,
    String? driverContact,
    int? stockUpdatesCount,
    bool clearDeliveredAt = false,
    bool clearDispatchedAt = false,
    bool clearArrivedAt = false,
    bool clearStaffVerifiedAt = false,
    bool clearStockCommittedAt = false,
  }) {
    return TradePurchase(
      id: id ?? this.id,
      humanId: humanId ?? this.humanId,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      purchaseDate: purchaseDate ?? this.purchaseDate,
      supplierId: supplierId ?? this.supplierId,
      brokerId: brokerId ?? this.brokerId,
      paymentDays: paymentDays ?? this.paymentDays,
      dueDate: dueDate ?? this.dueDate,
      paidAmount: paidAmount ?? this.paidAmount,
      paidAt: paidAt ?? this.paidAt,
      totalAmount: totalAmount ?? this.totalAmount,
      storedStatus: storedStatus ?? this.storedStatus,
      derivedStatus: derivedStatus ?? this.derivedStatus,
      remaining: remaining ?? this.remaining,
      itemsCount: itemsCount ?? this.itemsCount,
      supplierName: supplierName ?? this.supplierName,
      brokerName: brokerName ?? this.brokerName,
      supplierGst: supplierGst ?? this.supplierGst,
      supplierAddress: supplierAddress ?? this.supplierAddress,
      supplierPhone: supplierPhone ?? this.supplierPhone,
      supplierWhatsapp: supplierWhatsapp ?? this.supplierWhatsapp,
      brokerPhone: brokerPhone ?? this.brokerPhone,
      brokerLocation: brokerLocation ?? this.brokerLocation,
      brokerImageUrl: brokerImageUrl ?? this.brokerImageUrl,
      discount: discount ?? this.discount,
      commissionMode: commissionMode ?? this.commissionMode,
      commissionPercent: commissionPercent ?? this.commissionPercent,
      commissionMoney: commissionMoney ?? this.commissionMoney,
      deliveredRate: deliveredRate ?? this.deliveredRate,
      billtyRate: billtyRate ?? this.billtyRate,
      freightAmount: freightAmount ?? this.freightAmount,
      freightType: freightType ?? this.freightType,
      lines: lines ?? this.lines,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      totalLandingSubtotal: totalLandingSubtotal ?? this.totalLandingSubtotal,
      totalSellingSubtotal: totalSellingSubtotal ?? this.totalSellingSubtotal,
      totalLineProfit: totalLineProfit ?? this.totalLineProfit,
      hasMissingDetails: hasMissingDetails ?? this.hasMissingDetails,
      isDelivered: isDelivered ?? this.isDelivered,
      deliveryStatus: deliveryStatus ?? this.deliveryStatus,
      deliveredAt: clearDeliveredAt ? null : (deliveredAt ?? this.deliveredAt),
      deliveryNotes: deliveryNotes ?? this.deliveryNotes,
      dispatchedAt:
          clearDispatchedAt ? null : (dispatchedAt ?? this.dispatchedAt),
      arrivedAt: clearArrivedAt ? null : (arrivedAt ?? this.arrivedAt),
      staffVerifiedAt: clearStaffVerifiedAt
          ? null
          : (staffVerifiedAt ?? this.staffVerifiedAt),
      staffVerifiedByName: staffVerifiedByName ?? this.staffVerifiedByName,
      stockCommittedAt: clearStockCommittedAt
          ? null
          : (stockCommittedAt ?? this.stockCommittedAt),
      staffVerifiedQty: staffVerifiedQty ?? this.staffVerifiedQty,
      deliveredQtyCommitted:
          deliveredQtyCommitted ?? this.deliveredQtyCommitted,
      dispatchNote: dispatchNote ?? this.dispatchNote,
      truckNumber: truckNumber ?? this.truckNumber,
      driverContact: driverContact ?? this.driverContact,
      stockUpdatesCount: stockUpdatesCount ?? this.stockUpdatesCount,
    );
  }
}

extension TradePurchaseOptimisticPatch on TradePurchase {
  /// Instant UI while delivery commit round-trips.
  TradePurchase withOptimisticMarkedDelivered() {
    final now = DateTime.now();
    return copyWith(
      isDelivered: true,
      deliveryStatus: DeliveryStatus.stockCommitted.wireValue,
      deliveredAt: deliveredAt ?? now,
      stockCommittedAt: stockCommittedAt ?? now,
    );
  }

  /// Optimistic delivery toggle (detail screen) before GET refresh.
  TradePurchase withDelivered(bool delivered) {
    if (!delivered) {
      return copyWith(
        isDelivered: false,
        deliveryStatus: DeliveryStatus.pending.wireValue,
        clearDeliveredAt: true,
        clearDispatchedAt: true,
        clearArrivedAt: true,
        clearStaffVerifiedAt: true,
        clearStockCommittedAt: true,
      );
    }
    final now = DateTime.now();
    return copyWith(
      isDelivered: true,
      deliveryStatus: DeliveryStatus.stockCommitted.wireValue,
      deliveredAt: deliveredAt ?? now,
      stockCommittedAt: stockCommittedAt ?? now,
    );
  }

  /// Instant UI while [markPurchasePaid] round-trips.
  TradePurchase withOptimisticMarkedPaid() {
    return copyWith(
      paidAmount: totalAmount,
      paidAt: paidAt ?? DateTime.now(),
      derivedStatus: 'paid',
      remaining: 0,
    );
  }

  /// Instant UI while [cancelPurchase] round-trips (detail/history actions).
  TradePurchase withOptimisticCancelled() {
    return copyWith(
      storedStatus: 'cancelled',
      derivedStatus: 'cancelled',
    );
  }
}
