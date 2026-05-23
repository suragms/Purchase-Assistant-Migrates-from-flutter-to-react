import '../models/trade_purchase_models.dart';
import '../units/dynamic_unit_label_engine.dart' as unit_lbl;

/// Document title string for purchase PDFs (single source for tests + layout).
const String kPurchaseOrderPdfTitle = 'New Harisree Agency Purchase Order';

/// Weight-priced line: qty × kg_per_unit × landing_cost_per_kg.
bool tradePurchaseLineIsWeightPriced(TradePurchaseLine l) {
  final a = l.kgPerUnit;
  final b = l.landingCostPerKg;
  return a != null && b != null && a > 0 && b > 0;
}

/// Effective per-unit purchase rate when [landingCost] is missing but line total exists.
double? tradePurchaseLineFallbackUnitRate(TradePurchaseLine l) {
  if (l.landingCost > 0) return null;
  final total = l.lineTotal;
  if (total == null || total <= 0 || l.qty <= 0) return null;
  return total / l.qty;
}

/// Purchase rate for display: uses [rate_context] when present (₹/bag vs ₹/kg).
double tradePurchaseLineDisplayPurchaseRate(TradePurchaseLine l) {
  final dim = unit_lbl.purchaseRateSuffix(l);
  if (dim == 'kg' && tradePurchaseLineIsWeightPriced(l)) {
    if (l.landingCostPerKg! > 0) return l.landingCostPerKg!;
    final fb = tradePurchaseLineFallbackUnitRate(l);
    if (fb != null && l.kgPerUnit != null && l.kgPerUnit! > 0) {
      return fb / l.kgPerUnit!;
    }
    return l.landingCostPerKg!;
  }
  if (l.landingCost > 0) return l.landingCost;
  return tradePurchaseLineFallbackUnitRate(l) ?? 0;
}

/// Selling rate for display; respects [rate_context] selling_rate_dim.
double? tradePurchaseLineDisplaySellingRate(TradePurchaseLine l) {
  final sp = l.sellingRate ?? l.sellingCost;
  if (sp == null || sp <= 0) return null;
  final dim = unit_lbl.sellingRateSuffix(l);
  if (dim == 'kg' && tradePurchaseLineIsWeightPriced(l)) {
    return sp / l.kgPerUnit!;
  }
  final u = l.unit.trim().toLowerCase();
  if (dim == 'kg' && (u == 'kg' || u == 'kgs')) return sp;
  if (dim == 'kg' &&
      (u == 'bag' || u == 'sack' || u == 'box' || u == 'tin') &&
      l.kgPerUnit != null &&
      l.kgPerUnit! > 0) {
    return sp / l.kgPerUnit!;
  }
  return sp;
}

/// True when UI should show selling as per-kg (legacy + [rate_context]).
bool tradePurchaseLineDisplaySellingRateIsPerKg(TradePurchaseLine l) {
  return unit_lbl.sellingRateSuffix(l) == 'kg';
}

/// UI qualifier for ledger / intel lines (e.g. `/kg`, `/bag`).
String ledgerPurchaseRateDisplayDim(TradePurchaseLine l) =>
    unit_lbl.purchaseRateSuffix(l);

String ledgerSellingRateDisplayDim(TradePurchaseLine l) =>
    unit_lbl.sellingRateSuffix(l);
