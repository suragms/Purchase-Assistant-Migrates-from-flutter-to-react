// Lightweight fuzzy matching for catalog search (typo-tolerant, case-insensitive).

/// Max autocomplete / picker rows (Sprint 12 duplicate-search cap).
const int kCatalogFuzzySearchMax = 8;

String normalizeCatalogSearch(String s) {
  return s.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
}

int _levenshtein(String a, String b) {
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  final m = a.length;
  final n = b.length;
  var prev = List<int>.generate(n + 1, (j) => j);
  for (var i = 1; i <= m; i++) {
    final cur = List<int>.filled(n + 1, 0);
    cur[0] = i;
    for (var j = 1; j <= n; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      final ins = cur[j - 1] + 1;
      final del = prev[j] + 1;
      final sub = prev[j - 1] + cost;
      cur[j] = ins < del ? (ins < sub ? ins : sub) : (del < sub ? del : sub);
    }
    prev = cur;
  }
  return prev[n];
}

/// Higher is better. Empty [query] matches everything at score 100.
double catalogFuzzyScore(String query, String candidate) {
  final q = normalizeCatalogSearch(query);
  final c = normalizeCatalogSearch(candidate);
  if (q.isEmpty) return 100;
  if (c.isEmpty) return 0;
  if (c.contains(q)) return 100;

  final qWords = q.split(' ').where((e) => e.isNotEmpty).toList();
  final cWords = c.split(' ').where((e) => e.isNotEmpty).toList();
  if (qWords.isNotEmpty && cWords.isNotEmpty) {
    var prefixHits = 0;
    for (final qw in qWords) {
      for (final cw in cWords) {
        if (cw.startsWith(qw) || qw.startsWith(cw)) {
          prefixHits++;
          break;
        }
      }
    }
    if (prefixHits == qWords.length) return 82;
  }

  final maxLen = q.length > c.length ? q.length : c.length;
  if (maxLen > 48) return 0;
  final d = _levenshtein(q, c);
  final sim = 70 - d * 4;
  return sim < 0 ? 0 : sim.toDouble();
}

/// Rank [items] by [labelOf]; keep best [limit] with score ≥ [minScore].
List<T> catalogFuzzyRank<T>(
  String query,
  List<T> items,
  String Function(T) labelOf, {
  double minScore = 42,
  int limit = kCatalogFuzzySearchMax,
}) {
  final q = normalizeCatalogSearch(query);
  if (q.isEmpty) return List<T>.from(items);
  final scored = <({T item, double score})>[];
  for (final it in items) {
    final s = catalogFuzzyScore(q, labelOf(it));
    if (s >= minScore) scored.add((item: it, score: s));
  }
  scored.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;
    final aLabel = normalizeCatalogSearch(labelOf(a.item));
    final bLabel = normalizeCatalogSearch(labelOf(b.item));
    final aExact = aLabel == q;
    final bExact = bLabel == q;
    if (aExact != bExact) return aExact ? -1 : 1;
    final aPrefix = aLabel.startsWith(q);
    final bPrefix = bLabel.startsWith(q);
    if (aPrefix != bPrefix) return aPrefix ? -1 : 1;
    return aLabel.compareTo(bLabel);
  });
  return scored.take(limit).map((e) => e.item).toList();
}

bool catalogFuzzyMatches(String query, String candidate, {double minScore = 42}) {
  return catalogFuzzyScore(query, candidate) >= minScore;
}
