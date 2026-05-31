// Stock quantity display helpers (primary unit + derived KG for bags/tins).

String stockDisplayPrimary(double qty, String unit, [String? packType]) {
  final u = unit.trim().toLowerCase();
  final p = packType?.trim().toLowerCase() ?? '';
  final label = (p == 'bag' || u == 'sack') ? 'bag' : (u.isEmpty ? '' : u);
  final q = _fmtQty(qty);
  if (label.isEmpty) return q;
  final plural = switch (label) {
    'bag' => qty == 1 ? 'bag' : 'bags',
    'box' => qty == 1 ? 'box' : 'boxes',
    'tin' => qty == 1 ? 'tin' : 'tins',
    _ => label,
  };
  return '$q $plural';
}

String? stockDisplaySecondary(
  double qty,
  String unit,
  double? kgPerBag,
  double? kgPerTin,
) {
  final u = unit.trim().toLowerCase();
  if (u == 'bag' || u == 'sack' || u == 'piece') {
    if (kgPerBag != null && kgPerBag > 0) {
      return '(${_fmtQty(qty * kgPerBag)} kg)';
    }
  }
  // BOX and TIN never show kg secondary (operational rule).
  return null;
}

bool isKgStockUnit(String? unit) {
  final u = (unit ?? '').trim().toLowerCase();
  return u == 'kg' || u == 'kilogram' || u == 'kilograms';
}

/// Warehouse list qty: integers for bag/box/tin/piece; up to 2 decimals for kg only.
String formatStockQtyForUnit(String? unit, double n) {
  if (!n.isFinite) return '—';
  if (isKgStockUnit(unit)) {
    return formatStockQtyNumber(n);
  }
  return formatStockQtyNumber(n);
}

/// Warehouse qty with unit suffix for KG only (bag/box/tin show number alone).
String formatStockQtyDisplay(String? unit, double n) {
  final q = formatStockQtyForUnit(unit, n);
  if (isKgStockUnit(unit) && (unit ?? '').trim().isNotEmpty) {
    return '$q ${unit!.trim().toUpperCase()}';
  }
  return q;
}

/// Warehouse list qty: no trailing `.000`, comma thousands for ints.
String formatStockQtyNumber(double n) {
  final rounded = n.roundToDouble();
  if ((n - rounded).abs() < 0.001) {
    return rounded.toInt().toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]},',
        );
  }
  final s = n.toStringAsFixed(2);
  return s.endsWith('0') ? s.substring(0, s.length - 1) : s;
}

String _fmtQty(double n) => formatStockQtyNumber(n);

/// All warehouse qty labels (no `.000` on whole numbers).
String formatQtyForDisplay(num? value) {
  if (value == null) return '—';
  return formatStockQtyNumber(value.toDouble());
}

/// Primary stock label + optional kg subtitle from API fields.
class DualStockDisplay {
  const DualStockDisplay({required this.primary, this.secondary});

  final String primary;
  final String? secondary;
}

DualStockDisplay dualStockDisplay({
  required double qty,
  String? unit,
  double? kgPerBag,
  double? currentStockKg,
}) {
  final u = (unit ?? '').trim().toLowerCase();
  final primary = stockDisplayPrimary(qty, u.isEmpty ? 'piece' : u);
  String? secondary = stockDisplaySecondary(qty, u, kgPerBag, null);
  if (secondary == null && currentStockKg != null && currentStockKg > 0) {
    secondary = '(${_fmtQty(currentStockKg)} kg)';
  }
  return DualStockDisplay(primary: primary, secondary: secondary);
}

/// Purchase row: entered unit + normalized stock-unit qty from API.
DualStockDisplay dualPurchaseQtyDisplay({
  required double enteredQty,
  String? enteredUnit,
  double? qtyInStockUnit,
  String? stockUnit,
  double? kgPerBag,
}) {
  final eu = (enteredUnit ?? '').trim().toLowerCase();
  final entered = stockDisplayPrimary(enteredQty, eu.isEmpty ? 'piece' : eu);
  if (qtyInStockUnit == null || stockUnit == null) {
    return DualStockDisplay(primary: entered);
  }
  final su = stockUnit.trim().toLowerCase();
  final normalized = stockDisplayPrimary(qtyInStockUnit, su);
  if (entered == normalized) {
    final sec = stockDisplaySecondary(qtyInStockUnit, su, kgPerBag, null);
    return DualStockDisplay(primary: entered, secondary: sec);
  }
  final sec = stockDisplaySecondary(enteredQty, eu, kgPerBag, null) ??
      '($normalized)';
  return DualStockDisplay(primary: entered, secondary: sec);
}
