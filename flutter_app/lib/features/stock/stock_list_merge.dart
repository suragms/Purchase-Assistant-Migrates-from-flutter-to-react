/// Merges paged `/stock/list` responses by catalog item id.
Map<String, dynamic> mergeStockListPage({
  required Map<String, dynamic>? previous,
  required Map<String, dynamic> incoming,
  required int page,
}) {
  final total = _int(incoming['total']);
  final raw = incoming['items'];
  final batch = <Map<String, dynamic>>[];
  if (raw is List) {
    for (final e in raw) {
      if (e is Map) batch.add(Map<String, dynamic>.from(e));
    }
  }
  if (page <= 1 || previous == null) {
    return {'items': batch, 'total': total, 'page': page};
  }
  final prevItems = previous['items'];
  final merged = <Map<String, dynamic>>[];
  final seen = <String>{};
  if (prevItems is List) {
    for (final e in prevItems) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      final id = m['id']?.toString();
      if (id != null && id.isNotEmpty) {
        if (seen.add(id)) merged.add(m);
      } else {
        merged.add(m);
      }
    }
  }
  for (final m in batch) {
    final id = m['id']?.toString();
    if (id != null && id.isNotEmpty) {
      if (seen.contains(id)) continue;
      seen.add(id);
    }
    merged.add(m);
  }
  return {'items': merged, 'total': total, 'page': page};
}

int stockListMaxPage(int total, int perPage) {
  if (perPage <= 0) return 1;
  final pages = (total / perPage).ceil();
  return pages < 1 ? 1 : pages;
}

int _int(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('$v') ?? 0;
}
