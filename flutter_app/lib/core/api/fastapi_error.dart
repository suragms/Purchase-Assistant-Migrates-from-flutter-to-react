// Parsing FastAPI / Starlette error bodies: { "detail": "..." } or
// { "detail": [ { "loc": [...], "msg": "..." }, ... ] }.

/// Human-readable purchase-save copy for a 422 `detail` list.
///
/// Maps the Phase 6 backend contract (required `catalog_item_id`, `qty > 0`,
/// `landing_cost > 0`, paired `kg_per_unit`/`landing_cost_per_kg`) to strings
/// a shop owner can act on, prefixed with the 1-based line number when the
/// error is on a line. Returns null when the payload doesn't look like a
/// Pydantic validation list.
String? fastApiPurchaseFriendlyError(Object? data) {
  if (data is! Map) return null;
  final detail = data['detail'];
  if (detail is! List) return null;
  final msgs = <String>[];
  for (final e in detail) {
    if (e is! Map) continue;
    final rawMsg = e['msg']?.toString() ?? '';
    final loc = e['loc'];
    final segs = <String>[];
    if (loc is List) {
      for (final x in loc) {
        if (x == 'body') continue;
        segs.add(x.toString());
      }
    }
    String? linePrefix;
    String? field;
    final li = segs.indexOf('lines');
    if (li >= 0 && li + 1 < segs.length) {
      final n = int.tryParse(segs[li + 1]);
      if (n != null) linePrefix = 'Line ${n + 1}';
      if (li + 2 < segs.length) field = segs[li + 2];
    } else if (segs.isNotEmpty) {
      field = segs.last;
    }
    final friendly = _friendlyFieldMessage(field, rawMsg);
    if (friendly == null) continue;
    msgs.add(linePrefix == null ? friendly : '$linePrefix: $friendly');
  }
  if (msgs.isEmpty) return null;
  const maxLines = 6;
  if (msgs.length <= maxLines) return msgs.join('\n');
  return '${msgs.take(maxLines).join('\n')}\n…';
}

String? _friendlyFieldMessage(String? field, String rawMsg) {
  final m = rawMsg.toLowerCase();
  switch (field) {
    case 'catalog_item_id':
      return 'pick the item from the list (free-typed items cannot be saved)';
    case 'qty':
      return 'quantity must be greater than 0';
    case 'landing_cost':
      return 'landing cost must be greater than 0';
    case 'selling_cost':
      return 'selling price cannot be negative';
    case 'discount':
      return 'discount cannot be negative';
    case 'tax_percent':
      return 'tax % cannot be negative';
    case 'kg_per_unit':
      return 'kg per unit must be greater than 0';
    case 'landing_cost_per_kg':
      return 'price per kg must be greater than 0';
    case 'unit':
      return 'unit is required';
    case 'item_name':
      return 'item name is required';
    case 'supplier_id':
      return 'please select a supplier';
    case 'purchase_date':
      return 'please set a valid purchase date';
    case 'payment_days':
      return 'payment days must be between 0 and 3650';
    case 'default_items_per_box':
      return 'Enter how many items fit in one box.';
    case 'default_weight_per_tin':
      return 'Enter weight or size per tin.';
    case 'default_kg_per_bag':
      return 'Enter weight per bag in kg (for example 50).';
    case 'name':
      return 'item name is required';
    case 'hsn_code':
      return 'enter a valid HSN code';
    case 'default_unit':
      return 'Select a unit (bag, kg, box, etc.).';
    case 'type_id':
      return 'Select a subcategory (type).';
    case 'category_id':
      return 'Select a category.';
    case 'default_supplier_ids':
      return 'Select at least one default supplier (add suppliers in Contacts if needed).';
  }
  // Fallback for the paired kg_per_unit / landing_cost_per_kg root validator.
  if (m.contains('kg_per_unit') && m.contains('landing_cost_per_kg')) {
    return 'fill both kg per unit and price per kg, or leave both blank';
  }
  final trimmed = rawMsg.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// Human-readable text from a JSON error body, or null if none.
String? fastApiDetailString(Object? data) {
  if (data is! Map) return null;
  final detail = data['detail'];
  if (detail is String) {
    final t = detail.trim();
    return t.isEmpty ? null : t;
  }
  if (detail is Map) {
    final msg = detail['message']?.toString().trim();
    if (msg != null && msg.isNotEmpty) return msg;
    final code = detail['code']?.toString();
    if (code == 'UNIT_SETUP_REQUIRED') {
      final items = detail['items_needing_setup'];
      if (items is List && items.isNotEmpty) {
        return 'Set up units for: ${items.join(', ')}.';
      }
    }
  }
  if (detail is List) {
    final parts = <String>[];
    for (final e in detail) {
      if (e is! Map) continue;
      final msg = e['msg']?.toString();
      if (msg == null) continue;
      final loc = e['loc'];
      if (loc is List) {
        final segs = <String>[];
        for (final x in loc) {
          if (x == 'body') continue;
          segs.add(x.toString());
        }
        if (segs.isNotEmpty) {
          parts.add('${segs.join('.')}: $msg');
        } else {
          parts.add(msg);
        }
      } else {
        parts.add(msg);
      }
    }
    if (parts.isEmpty) return null;
    const maxLines = 6;
    if (parts.length <= maxLines) return parts.join('\n');
    return '${parts.take(maxLines).join('\n')}\n…';
  }
  return null;
}

/// Hints for scrolling the purchase wizard to the relevant field on validation errors.
class FastApiPurchaseScrollHint {
  const FastApiPurchaseScrollHint._({
    this.supplierField = false,
    this.brokerField = false,
    this.lineIndex,
  });

  const FastApiPurchaseScrollHint.supplier() : this._(supplierField: true);

  const FastApiPurchaseScrollHint.broker() : this._(brokerField: true);

  /// 0-based line index from e.g. `["body", "lines", 2, "qty"]`.
  const FastApiPurchaseScrollHint.line(int index)
      : this._(supplierField: false, lineIndex: index);

  final bool supplierField;
  final bool brokerField;
  final int? lineIndex;
}

/// Best-effort parse of `lines[i]` / `supplier_id` from a 422 [detail] list.
FastApiPurchaseScrollHint? fastApiPurchaseScrollHint(Object? data) {
  if (data is! Map) return null;
  final detail = data['detail'];
  if (detail is! List) return null;
  for (final e in detail) {
    if (e is! Map) continue;
    final loc = e['loc'];
    if (loc is! List) continue;
    final segs = <String>[];
    for (final x in loc) {
      if (x == 'body') continue;
      segs.add(x.toString());
    }
    if (segs.isNotEmpty && segs.last == 'supplier_id') {
      return const FastApiPurchaseScrollHint.supplier();
    }
    if (segs.isNotEmpty && segs.last == 'broker_id') {
      return const FastApiPurchaseScrollHint.broker();
    }
    final li = segs.indexOf('lines');
    if (li >= 0 && li + 1 < segs.length) {
      final n = int.tryParse(segs[li + 1]);
      if (n != null) return FastApiPurchaseScrollHint.line(n);
    }
  }
  return null;
}
