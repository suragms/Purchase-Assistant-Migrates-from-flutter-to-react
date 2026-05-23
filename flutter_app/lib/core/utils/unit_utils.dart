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
  if (u == 'bag' || u == 'sack') {
    if (kgPerBag != null && kgPerBag > 0) {
      return '(${_fmtQty(qty * kgPerBag)} kg)';
    }
  }
  // BOX and TIN never show kg secondary (operational rule).
  return null;
}

String _fmtQty(double n) {
  final rounded = n.roundToDouble();
  if ((n - rounded).abs() < 0.001) {
    return rounded.toInt().toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]},',
        );
  }
  return n.toStringAsFixed(3);
}
