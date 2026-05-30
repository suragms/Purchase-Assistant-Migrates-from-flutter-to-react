import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/providers/recent_unified_search_provider.dart';
import '../../../core/providers/search_focus_provider.dart';
import '../../../core/router/navigation_ext.dart';
import '../../../core/design_system/hexa_responsive.dart';
import '../../../core/router/post_auth_route.dart';
import 'widgets/search_desktop_preview_pane.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../../../shared/widgets/trade_intel_cards.dart';
import '../../shell/shell_branch_provider.dart';
import '../../staff/staff_shell_branch_provider.dart';

const Duration _unifiedSearchTtl = Duration(seconds: 12);
const int _unifiedSearchCacheMaxEntries = 40;

final Map<String, ({DateTime at, Map<String, dynamic> data})> _unifiedSearchCache =
    {};

String _unifiedSearchCacheKey(String businessId, String query) =>
    '$businessId|${query.trim().toLowerCase()}';

/// Server-backed unified search (catalog items, catalog types, trade bills, suppliers).
final unifiedSearchProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
  (ref, q) async {
    final session = ref.watch(sessionProvider);
    if (session == null || q.trim().isEmpty) {
      return {
        'catalog_items': <dynamic>[],
        'suppliers': <dynamic>[],
        'brokers': <dynamic>[],
        'catalog_subcategories': <dynamic>[],
        'recent_purchases': <dynamic>[],
      };
    }
    final bid = session.primaryBusiness.id;
    final key = _unifiedSearchCacheKey(bid, q);
    final now = DateTime.now();
    final hit = _unifiedSearchCache[key];
    if (hit != null && now.difference(hit.at) < _unifiedSearchTtl) {
      return hit.data;
    }
    final data = await ref.read(hexaApiProvider).unifiedSearch(
          businessId: bid,
          q: q.trim(),
        );
    _unifiedSearchCache[key] = (at: now, data: data);
    while (_unifiedSearchCache.length > _unifiedSearchCacheMaxEntries) {
      String? oldestK;
      DateTime? oldestT;
      for (final e in _unifiedSearchCache.entries) {
        if (oldestT == null || e.value.at.isBefore(oldestT)) {
          oldestT = e.value.at;
          oldestK = e.key;
        }
      }
      if (oldestK != null) _unifiedSearchCache.remove(oldestK);
    }
    return data;
  },
);

double? _toD(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

String _fmtInr(dynamic v, {int digits = 2}) {
  final n = _toD(v);
  if (n == null) return '—';
  return NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: digits,
  ).format(n);
}

String _fmtQty(dynamic v) {
  final n = _toD(v);
  if (n == null) return '—';
  if (n == n.roundToDouble()) return n.round().toString();
  return n.toStringAsFixed(2);
}

int _searchYmdKey(Object? dtRaw) {
  if (dtRaw is String && dtRaw.length >= 10) {
    final s = dtRaw.substring(0, 10).replaceAll('-', '');
    return int.tryParse(s) ?? 0;
  }
  return 0;
}

int _catalogSearchPrefixRank(Map<String, dynamic> item, String query) {
  if (query.isEmpty) return 0;
  final name = (item['name']?.toString() ?? '').toLowerCase();
  final code = (item['item_code']?.toString() ?? '').toLowerCase();
  if (name.startsWith(query) || code.startsWith(query)) return 0;
  if (name.contains(query) || code.contains(query)) return 1;
  return 2;
}

void _sortCatalogItemsByPrefix(List<Map<String, dynamic>> items, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return;
  items.sort((a, b) {
    final pr = _catalogSearchPrefixRank(a, q)
        .compareTo(_catalogSearchPrefixRank(b, q));
    if (pr != 0) return pr;
    return (a['name']?.toString() ?? '')
        .toLowerCase()
        .compareTo((b['name']?.toString() ?? '').toLowerCase());
  });
}

List<Map<String, dynamic>> _asMapListSkipBad(String key, Map<String, dynamic> data) {
  final raw = data[key];
  if (raw is! List) return [];
  final out = <Map<String, dynamic>>[];
  for (final e in raw) {
    if (e is Map) out.add(Map<String, dynamic>.from(e));
  }
  return out;
}

/// Align with trade reports / dashboard: omit soft-deleted, cancelled, and drafts.
bool _purchaseVisibleInUnifiedSearchHints(Map<String, dynamic> p) {
  final s = (p['status'] ?? '').toString().toLowerCase().trim();
  return s != 'deleted' && s != 'cancelled' && s != 'draft';
}

Map<String, dynamic>? _pickPurchaseLine(Map<String, dynamic> p, String q) {
  final lines = (p['lines'] as List<dynamic>?) ?? [];
  for (final raw in lines) {
    if (raw is! Map) continue;
    final m = Map<String, dynamic>.from(raw);
    final nm = (m['item_name'] ?? '').toString().toLowerCase();
    if (q.isNotEmpty && nm.contains(q)) return m;
  }
  if (lines.isNotEmpty && lines.first is Map) {
    return Map<String, dynamic>.from(lines.first as Map);
  }
  return null;
}

Widget _purchaseLineSummaryRich(
  BuildContext context,
  Map<String, dynamic> line, {
  bool hideFinancials = false,
}) {
  final nm = line['item_name']?.toString() ?? 'Line';
  final qty = _fmtQty(line['qty']);
  final unit = line['unit']?.toString().trim().toLowerCase();
  final pr = line['purchase_rate'];
  final lc = line['landing_cost'];
  final prN = _toD(pr);
  final rate = !hideFinancials && prN != null && prN > 0
      ? 'Rate ${_fmtInr(pr)}'
      : (!hideFinancials ? 'Landing ${_fmtInr(lc)}' : '');
  final tw = _toD(line['total_weight_kg'] ?? line['total_weight']);
  final tt = Theme.of(context).textTheme;
  final cs = Theme.of(context).colorScheme;
  final base = tt.bodySmall?.copyWith(
    color: cs.onSurface,
    height: 1.35,
    fontWeight: FontWeight.w500,
  );
  final qtyStyle = tt.bodySmall?.copyWith(
    color: cs.error,
    height: 1.35,
    fontWeight: FontWeight.w800,
  );
  return Text.rich(
    TextSpan(
      style: base,
      children: [
        TextSpan(text: nm),
        const TextSpan(text: ' · '),
        TextSpan(text: qty, style: qtyStyle),
        if (tw != null && tw > 1e-6 && unit == 'bag') ...[
          const TextSpan(text: ' · '),
          TextSpan(text: _fmtQty(tw), style: qtyStyle),
        ],
        if (rate.isNotEmpty) TextSpan(text: ' · $rate', style: base),
      ],
    ),
  );
}

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({
    super.key,
    this.embeddedInShell = false,
    this.staffShellEmbedded = false,
  });

  /// When true (main shell tab), hide back affordance and refocus search when tab is selected.
  final bool embeddedInShell;

  /// Staff shell tab — refocus when [StaffShellBranch.search] is selected.
  final bool staffShellEmbedded;

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  String _debounced = '';
  Map<String, dynamic>? _cachedSearchData;
  String _section = 'all';
  /// Avoid recording the same completed search repeatedly on rebuilds.
  String? _recordedQueryKey;
  String? _desktopPreviewItemId;
  String? _desktopPreviewItemName;

  static const _sections = {
    'all',
    'types',
    'items',
    'bills',
    'suppliers',
    'brokers',
    'contacts',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.staffShellEmbedded) {
        setState(() => _section = 'items');
      }
      final sec = GoRouterState.of(context).uri.queryParameters['section'];
      if (sec != null && _sections.contains(sec)) {
        setState(() => _section = sec);
      }
      if (widget.staffShellEmbedded &&
          ref.read(searchFocusRequestedProvider)) {
        ref.read(searchFocusRequestedProvider.notifier).state = false;
        _focus.requestFocus();
      } else if (!widget.staffShellEmbedded) {
        _focus.requestFocus();
      } else {
        _focus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _scheduleSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      final next = v.trim();
      if (next == _debounced) return;
      setState(() {
        _debounced = next;
        _recordedQueryKey = null;
        _desktopPreviewItemId = null;
        _desktopPreviewItemName = null;
      });
    });
  }

  void _applyQuery(String raw) {
    _debounce?.cancel();
    final t = raw.trim();
    setState(() {
      _controller.text = raw;
      _debounced = t;
      _recordedQueryKey = null;
      _desktopPreviewItemId = null;
      _desktopPreviewItemName = null;
    });
    _focus.requestFocus();
  }

  Widget _embeddedSearchTextField(ColorScheme cs) {
    final hint = widget.staffShellEmbedded
        ? 'Item name, code, barcode, category…'
        : 'Search purchases, suppliers, items…';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        autofocus: true,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: const Icon(Icons.search_rounded),
          isDense: false,
          contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
          suffixIcon: _controller.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded),
                  onPressed: () {
                    _controller.clear();
                    setState(() {
                      _debounced = '';
                      _recordedQueryKey = null;
                      _desktopPreviewItemId = null;
                      _desktopPreviewItemName = null;
                    });
                    _scheduleSearch('');
                  },
                )
              : null,
          filled: true,
          fillColor: cs.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
        onChanged: (v) {
          setState(() {});
          _scheduleSearch(v);
        },
      ),
    );
  }

  Widget _embeddedCategoryChips() {
    final meta = widget.staffShellEmbedded
        ? const <(String, String)>[
            ('items', 'Items'),
            ('types', 'Subcategories'),
            ('bills', 'Purchases'),
          ]
        : const <(String, String)>[
            ('all', 'All'),
            ('bills', 'Purchases'),
            ('items', 'Items'),
            ('suppliers', 'Suppliers'),
            ('brokers', 'Brokers'),
            ('types', 'Types'),
            ('contacts', 'Contacts'),
          ];
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        itemCount: meta.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final e = meta[i];
          return ChoiceChip(
            materialTapTargetSize: MaterialTapTargetSize.padded,
            labelPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            label: Text(
              e.$2,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            selected: _section == e.$1,
            onSelected: (_) => setState(() => _section = e.$1),
          );
        },
      ),
    );
  }

  Widget _standaloneTopSearchBar(ColorScheme cs) {
    return Material(
      elevation: 1,
      shadowColor: Colors.black26,
      color: cs.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        child: SearchBar(
          focusNode: _focus,
          controller: _controller,
          hintText: 'Item, type, bill, supplier, broker, HSN…',
          textInputAction: TextInputAction.search,
          textStyle: const WidgetStatePropertyAll(TextStyle()),
          leading: const Icon(Icons.search_rounded),
          trailing: [
            if (_controller.text.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () {
                  _controller.clear();
                  setState(() {
                    _debounced = '';
                    _recordedQueryKey = null;
                  });
                  _scheduleSearch('');
                },
              ),
          ],
          onChanged: (v) {
            setState(() {});
            _scheduleSearch(v);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embeddedInShell) {
      ref.listen<int>(shellCurrentBranchProvider, (prev, next) {
        if (next == ShellBranch.search) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _focus.requestFocus();
          });
        }
      });
    }
    if (widget.staffShellEmbedded) {
      ref.listen<int>(staffShellCurrentBranchProvider, (prev, next) {
        if (next == StaffShellBranch.search) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (ref.read(searchFocusRequestedProvider)) {
              ref.read(searchFocusRequestedProvider.notifier).state = false;
            }
            _focus.requestFocus();
          });
        }
      });
    }
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final q = _debounced.toLowerCase();
    final searchAsync = q.isNotEmpty
        ? ref.watch(unifiedSearchProvider(_debounced))
        : const AsyncValue<Map<String, dynamic>>.data({});
    if (searchAsync.hasValue && q.isNotEmpty) {
      _cachedSearchData = searchAsync.value;
    }
    final searchReloading =
        searchAsync.isLoading && _cachedSearchData != null && q.isNotEmpty;
    final recents = ref.watch(recentUnifiedSearchQueriesProvider);
    final session = ref.watch(sessionProvider);
    final hideFinancials =
        session != null && !sessionCanSeeFinancials(session);

    final listPadding = EdgeInsets.fromLTRB(
      16,
      (widget.embeddedInShell || widget.staffShellEmbedded) ? 4 : 12,
      16,
      ((widget.embeddedInShell || widget.staffShellEmbedded) ? 96 : 32) +
          MediaQuery.viewPaddingOf(context).bottom +
          MediaQuery.viewInsetsOf(context).bottom,
    );

    final Widget scrollBody;
    if (q.isEmpty) {
      scrollBody = ListView(
        padding: listPadding,
        children: [
          if (recents.isNotEmpty) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    'Recent',
                    style: tt.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    await ref
                        .read(recentUnifiedSearchQueriesProvider.notifier)
                        .clearAll();
                    if (mounted) setState(() {});
                  },
                  child: const Text('Clear'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final r in recents)
                  ActionChip(
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 10,
                    ),
                    label: Text(
                      r,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onPressed: () => _applyQuery(r),
                  ),
              ],
            ),
            const SizedBox(height: 20),
          ],
          Text(
            'Quick filters',
            style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800, fontSize: 17),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (widget.staffShellEmbedded) ...[
                ActionChip(
                  avatar: const Icon(Icons.grid_view_rounded, size: 18),
                  label: const Text('Item gallery'),
                  onPressed: () => context.push('/staff/items'),
                ),
                ActionChip(
                  avatar: const Icon(Icons.qr_code_2_outlined, size: 18),
                  label: const Text('Missing barcode'),
                  onPressed: () => context.push(
                    '/staff/items?filter=missing_barcode',
                  ),
                ),
                ActionChip(
                  avatar: const Icon(Icons.tag_outlined, size: 18),
                  label: const Text('Missing item code'),
                  onPressed: () => context.push(
                    '/staff/items?filter=missing_code',
                  ),
                ),
                ActionChip(
                  avatar: const Icon(Icons.inventory_outlined, size: 18),
                  label: const Text('Opening stock'),
                  onPressed: () => context.push('/stock/opening-setup'),
                ),
              ],
              ActionChip(
                avatar: const Icon(Icons.warning_amber_rounded, size: 18),
                label: const Text('Low stock'),
                onPressed: () => context.push(
                  widget.staffShellEmbedded
                      ? '/staff/low-stock'
                      : '/stock',
                ),
              ),
              if (!widget.staffShellEmbedded) ...[
                ActionChip(
                  avatar: const Icon(Icons.qr_code_2_rounded, size: 18),
                  label: const Text('Missing barcode'),
                  onPressed: () => context.push('/barcode/print'),
                ),
                ActionChip(
                  avatar: const Icon(Icons.edit_note_rounded, size: 18),
                  label: const Text('Recently updated'),
                  onPressed: () => context.push('/stock'),
                ),
                ActionChip(
                  avatar: const Icon(Icons.history_rounded, size: 18),
                  label: const Text('Recent scans'),
                  onPressed: () => context.push('/barcode/scan?return=search'),
                ),
              ] else
                ActionChip(
                  avatar: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                  label: const Text('Scan barcode'),
                  onPressed: () => context.go('/staff/scan'),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              widget.staffShellEmbedded
                  ? 'Search items by name, item code, category, or subcategory. '
                      'Use quick filters for missing labels and opening stock.'
                  : 'Search catalog items (name, HSN, code, category, catalog type), '
                      'recent purchase bills, suppliers, and brokers.',
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      );
    } else {
      scrollBody = searchAsync.when(
        skipLoadingOnReload: true,
        loading: () {
          if (searchReloading) {
            return ListView(
              padding: listPadding,
              children: [
                const LinearProgressIndicator(minHeight: 2),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'Updating results…',
                    style: tt.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            );
          }
          return _SearchLoadingFallback(
            padding: listPadding,
            recents: recents,
            onApplyQuery: _applyQuery,
          );
        },
        error: (_, __) => ListView(
          padding: listPadding,
          children: [
            FriendlyLoadError(
              message: 'Search failed',
              onRetry: () =>
                  ref.invalidate(unifiedSearchProvider(_debounced)),
            ),
          ],
        ),
        data: (data) {
                final keyNorm = _debounced.trim().toLowerCase();
                if (keyNorm.length >= 2 && _recordedQueryKey != keyNorm) {
                  _recordedQueryKey = keyNorm;
                  Future.microtask(() {
                    if (!mounted) return;
                    ref
                        .read(recentUnifiedSearchQueriesProvider.notifier)
                        .addQuery(_debounced);
                  });
                }
                final rawItems = _asMapListSkipBad('catalog_items', data);
                final suppliers = _asMapListSkipBad('suppliers', data);
                final brokers = _asMapListSkipBad('brokers', data);
                final types = _asMapListSkipBad('catalog_subcategories', data);
                final bills = _asMapListSkipBad('recent_purchases', data)
                    .where(_purchaseVisibleInUnifiedSearchHints)
                    .toList();
                final fuzzyItems = data['fuzzy_catalog_used'] == true;
                final fuzzySup = data['fuzzy_suppliers_used'] == true;
                final fuzzyBro = data['fuzzy_brokers_used'] == true;

                // Enrich catalog item hits with last-line qty/kg from matched recent purchases
                // so the UI can show "last bags/kg" even when the server only returns prices.
                final lastLineByItemId = <String, Map<String, dynamic>>{};
                final lastDateKeyByItemId = <String, int>{};
                final lastDateStringByItemId = <String, String>{};
                final lastBillHidByItemId = <String, String>{};
                final lastDeliveredByItemId = <String, bool>{};
                for (final p in bills) {
                  final dtK = _searchYmdKey(p['purchase_date']);
                  final dtStr = p['purchase_date']?.toString() ?? '';
                  final hid = p['human_id']?.toString() ?? '';
                  final delivered = p['is_delivered'] == true;
                  final lines = (p['lines'] is List) ? (p['lines'] as List) : const [];
                  for (final raw in lines) {
                    if (raw is! Map) continue;
                    final ln = Map<String, dynamic>.from(raw);
                    final cid = ln['catalog_item_id']?.toString() ?? '';
                    if (cid.isEmpty) continue;
                    final prevK = lastDateKeyByItemId[cid] ?? 0;
                    if (dtK >= prevK) {
                      lastDateKeyByItemId[cid] = dtK;
                      lastLineByItemId[cid] = ln;
                      lastDeliveredByItemId[cid] = delivered;
                      if (dtStr.length >= 10) {
                        lastDateStringByItemId[cid] = dtStr.substring(0, 10);
                      }
                      if (hid.isNotEmpty) lastBillHidByItemId[cid] = hid;
                    }
                  }
                }

                final items = rawItems.map((m) {
                  final id = m['id']?.toString() ?? '';
                  if (id.isEmpty) return m;

                  final ln = lastLineByItemId[id];
                  final next = Map<String, dynamic>.from(m);

                  final needsLineFromBills = next['last_line_qty'] == null &&
                      next['last_line_weight_kg'] == null;
                  if (ln != null && needsLineFromBills) {
                    next['last_line_qty'] = ln['qty'];
                    next['last_line_unit'] = ln['unit'];
                    next['last_line_weight_kg'] =
                        ln['total_weight_kg'] ?? ln['total_weight'];
                    next['kg_per_unit'] =
                        ln['kg_per_unit'] ?? ln['default_kg_per_bag'];
                    if (!hideFinancials) {
                      next['purchase_rate_dim'] =
                          (ln['landing_cost_per_kg'] != null ||
                                  ln['kg_per_unit'] != null)
                              ? 'kg'
                              : (ln['unit'] ?? '');
                      next['last_purchase_price'] = ln['landing_cost_per_kg'] ??
                          ln['purchase_rate'] ??
                          ln['landing_cost'];
                      next['last_selling_rate'] =
                          ln['selling_rate'] ?? ln['selling_cost'];
                      next['selling_rate_dim'] = next['purchase_rate_dim'];
                    }
                  }

                  if (ln != null) {
                    final billDate = lastDateStringByItemId[id];
                    final billKey = lastDateKeyByItemId[id] ?? 0;
                    final serverKey = _searchYmdKey(next['last_purchase_date']);
                    if (billDate != null && billKey >= serverKey) {
                      next['last_purchase_date'] = billDate;
                      final bh = lastBillHidByItemId[id];
                      if (bh != null && bh.isNotEmpty) {
                        next['last_purchase_human_id'] = bh;
                      }
                      if (lastDeliveredByItemId.containsKey(id)) {
                        next['last_purchase_delivered'] =
                            lastDeliveredByItemId[id] == true;
                      }
                    }
                  }

                  return next;
                }).toList();
                _sortCatalogItemsByPrefix(items, keyNorm);
                if (context.isDesktopLayout && items.isNotEmpty) {
                  final firstId = items.first['id']?.toString() ?? '';
                  if (_desktopPreviewItemId == null ||
                      _desktopPreviewItemId != firstId) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      setState(() {
                        _desktopPreviewItemId = firstId.isEmpty ? null : firstId;
                        _desktopPreviewItemName =
                            items.first['name']?.toString();
                      });
                    });
                  }
                }
                final contactHits = suppliers.length + brokers.length;
                final sectionCounts = <String, int>{
                  'types': types.length,
                  'items': items.length,
                  'bills': bills.length,
                  'suppliers': suppliers.length,
                  'brokers': brokers.length,
                  'contacts': contactHits,
                };
                final hasAny = types.isNotEmpty ||
                    items.isNotEmpty ||
                    bills.isNotEmpty ||
                    suppliers.isNotEmpty ||
                    brokers.isNotEmpty;

                return ListView(
                  padding: listPadding,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                    if (fuzzyItems || fuzzySup || fuzzyBro)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          [
                            if (fuzzyItems)
                              hideFinancials
                                  ? 'No exact item title match — showing close catalog matches. '
                                      'Open the item to confirm qty and supplier.'
                                  : 'No exact item title match — showing close catalog matches. '
                                      'Do not trust rates until you open the item.',
                            if (fuzzySup)
                              'No exact supplier name match — showing close supplier matches.',
                            if (fuzzyBro)
                              'No exact broker name match — showing close broker matches.',
                          ].join(' '),
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            height: 1.35,
                          ),
                        ),
                      ),
                    if (!(widget.embeddedInShell || widget.staffShellEmbedded)) ...[
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            ChoiceChip(
                              label: const Text(
                                'All',
                                style: TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w700),
                              ),
                              labelPadding:
                                  const EdgeInsets.symmetric(horizontal: 10),
                              selected: _section == 'all',
                              onSelected: (_) =>
                                  setState(() => _section = 'all'),
                            ),
                            const SizedBox(width: 10),
                            ChoiceChip(
                              label: Text(
                                'Types (${sectionCounts['types']})',
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                              labelPadding:
                                  const EdgeInsets.symmetric(horizontal: 10),
                              selected: _section == 'types',
                              onSelected: (_) =>
                                  setState(() => _section = 'types'),
                            ),
                            const SizedBox(width: 10),
                            ChoiceChip(
                              label: Text(
                                'Items (${sectionCounts['items']})',
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                              labelPadding:
                                  const EdgeInsets.symmetric(horizontal: 10),
                              selected: _section == 'items',
                              onSelected: (_) =>
                                  setState(() => _section = 'items'),
                            ),
                            const SizedBox(width: 10),
                            ChoiceChip(
                              label: Text(
                                'Bills (${sectionCounts['bills']})',
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                              labelPadding:
                                  const EdgeInsets.symmetric(horizontal: 10),
                              selected: _section == 'bills',
                              onSelected: (_) =>
                                  setState(() => _section = 'bills'),
                            ),
                            const SizedBox(width: 10),
                            ChoiceChip(
                              label: Text(
                                'Suppliers (${sectionCounts['suppliers']})',
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                              labelPadding:
                                  const EdgeInsets.symmetric(horizontal: 10),
                              selected: _section == 'suppliers',
                              onSelected: (_) =>
                                  setState(() => _section = 'suppliers'),
                            ),
                            const SizedBox(width: 10),
                            ChoiceChip(
                              label: Text(
                                'Brokers (${sectionCounts['brokers']})',
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                              labelPadding:
                                  const EdgeInsets.symmetric(horizontal: 10),
                              selected: _section == 'brokers',
                              onSelected: (_) =>
                                  setState(() => _section = 'brokers'),
                            ),
                            const SizedBox(width: 10),
                            ChoiceChip(
                              label: Text(
                                'Contacts (${sectionCounts['contacts']})',
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                              labelPadding:
                                  const EdgeInsets.symmetric(horizontal: 10),
                              selected: _section == 'contacts',
                              onSelected: (_) =>
                                  setState(() => _section = 'contacts'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (!hasAny)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'No matching items found. Try recent items, low stock, missing barcode, or scan history.',
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    if (!widget.staffShellEmbedded &&
                        (_section == 'all' || _section == 'types')) ...[
                      Text(
                        'Catalog types',
                        style: tt.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (types.isEmpty)
                        Text(
                          'No matching category / subcategory (type) names.',
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        )
                      else
                        ...types.map((m) {
                          final tid = m['id']?.toString() ?? '';
                          final cid = m['category_id']?.toString() ?? '';
                          final tname = m['name']?.toString() ?? '—';
                          final cname = m['category_name']?.toString() ?? '';
                          final typeName = tname.toLowerCase();
                          final matchingItemIds = items
                              .where(
                                (it) =>
                                    (it['type_name'] ?? '')
                                        .toString()
                                        .toLowerCase() ==
                                    typeName,
                              )
                              .map((it) => it['id']?.toString() ?? '')
                              .where((id) => id.isNotEmpty)
                              .toSet();
                          var typeTotalBags = 0.0;
                          var typeTotalKg = 0.0;
                          for (final id in matchingItemIds) {
                            final ln = lastLineByItemId[id];
                            if (ln == null) continue;
                            final qty = _toD(ln['qty']) ?? 0;
                            final unit =
                                ln['unit']?.toString().toLowerCase() ?? '';
                            if (unit == 'bag' || unit == 'sack') {
                              typeTotalBags += qty;
                            }
                            if (unit == 'kg') typeTotalKg += qty;
                          }
                          final parts = <String>[];
                          if (typeTotalBags > 0) {
                            parts.add('${_fmtQty(typeTotalBags)} bags');
                          }
                          if (typeTotalKg > 0) {
                            parts.add('${_fmtQty(typeTotalKg)} kg');
                          }
                          final summaryText =
                              parts.isEmpty ? null : parts.join(' · ');
                          final sub = cname.isEmpty
                              ? 'Catalog type'
                              : 'Under $cname';
                          final subBody = summaryText != null
                              ? '$sub\n$summaryText'
                              : sub;
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            isThreeLine: summaryText != null,
                            leading: Icon(Icons.category_outlined,
                                color: cs.primary),
                            title: Text(tname),
                            subtitle: Text(
                              subBody,
                              style: tt.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: tid.isEmpty || cid.isEmpty
                                ? null
                                : () => context.push(
                                      '/catalog/category/$cid/type/$tid',
                                    ),
                          );
                        }),
                      const SizedBox(height: 20),
                    ],
                    if (_section == 'all' || _section == 'items') ...[
                      Text(
                        'Catalog items',
                        style: tt.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (items.isEmpty)
                        Text(
                          'No matching catalog items.',
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        )
                      else
                        ...items.map((m) {
                          final id = m['id']?.toString() ?? '';
                          return TradeIntelCatalogSearchTile(
                            item: m,
                            fuzzyNameMatch: fuzzyItems,
                            hideFinancials: hideFinancials,
                            onTap: id.isEmpty
                                ? null
                                : () => context.push('/catalog/item/$id'),
                          );
                        }),
                      const SizedBox(height: 20),
                    ],
                    if (_section == 'all' || _section == 'bills') ...[
                      Text(
                        'Recent purchase bills',
                        style: tt.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (bills.isEmpty)
                        Text(
                          'No bills matched (try item name, supplier, or bill id).',
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        )
                      else
                        ...bills.map((p) {
                          final id = p['id']?.toString() ?? '';
                          final hid = p['human_id']?.toString() ?? '';
                          final dtRaw = p['purchase_date'];
                          String dateIso = '';
                          if (dtRaw is String && dtRaw.length >= 10) {
                            dateIso = dtRaw.substring(0, 10);
                          } else if (dtRaw != null) {
                            final s = dtRaw.toString();
                            dateIso =
                                s.length >= 10 ? s.substring(0, 10) : s.trim();
                          }
                          final datePretty =
                              tradeIntelFormatSearchBillDate(dateIso);
                          final ageLabel = dateIso.length >= 10
                              ? tradeIntelRelativeAgeFromIsoDateString(dateIso)
                              : null;
                          final sup =
                              p['supplier_name']?.toString() ?? 'Supplier';
                          final line = _pickPurchaseLine(p, q);
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            isThreeLine: line != null,
                            leading: Icon(Icons.receipt_long_outlined,
                                color: cs.secondary),
                            title: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: hid.isEmpty ? 'Purchase' : hid,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      color: cs.primary,
                                      fontSize: tt.titleSmall?.fontSize,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text.rich(
                                  TextSpan(
                                    style: tt.bodySmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    children: [
                                      if (datePretty.isNotEmpty)
                                        TextSpan(text: datePretty),
                                      if (ageLabel != null) ...[
                                        if (datePretty.isNotEmpty)
                                          const TextSpan(text: ' · '),
                                        TextSpan(
                                          text: ageLabel,
                                          style: tt.bodySmall?.copyWith(
                                            color: cs.error,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ],
                                      if (sup.isNotEmpty) ...[
                                        if (datePretty.isNotEmpty ||
                                            ageLabel != null)
                                          const TextSpan(text: ' · '),
                                        TextSpan(text: sup),
                                      ],
                                    ],
                                  ),
                                ),
                                if (line != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: _purchaseLineSummaryRich(
                                      context,
                                      line,
                                      hideFinancials: hideFinancials,
                                    ),
                                  ),
                              ],
                            ),
                            trailing:
                                const Icon(Icons.chevron_right_rounded),
                            onTap: id.isEmpty
                                ? null
                                : () {
                                    if (widget.staffShellEmbedded) {
                                      context.push(
                                        '/staff/purchase-history/$id',
                                      );
                                    } else {
                                      context.push('/purchase/detail/$id');
                                    }
                                  },
                          );
                        }),
                      const SizedBox(height: 20),
                    ],
                    if (!widget.staffShellEmbedded &&
                        (_section == 'all' || _section == 'suppliers')) ...[
                      Text(
                        'Suppliers',
                        style: tt.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (suppliers.isEmpty)
                        Text(
                          'No matching suppliers.',
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        )
                      else
                        ...suppliers.map((m) {
                          final id = m['id']?.toString() ?? '';
                          final name = m['name']?.toString() ?? 'Supplier';
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.storefront_outlined,
                                color: cs.primary),
                            title: Text(name),
                            trailing:
                                const Icon(Icons.chevron_right_rounded),
                            onTap: id.isEmpty
                                ? null
                                : () => context.push('/supplier/$id'),
                          );
                        }),
                    ],
                    if (_section == 'all' && brokers.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Brokers',
                        style: tt.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ...brokers.map((m) {
                        final id = m['id']?.toString() ?? '';
                        final name = m['name']?.toString() ?? 'Broker';
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.handshake_outlined,
                              color: cs.secondary),
                          title: Text(name),
                          trailing:
                              const Icon(Icons.chevron_right_rounded),
                          onTap: id.isEmpty
                              ? null
                              : () => context.push('/broker/$id'),
                        );
                      }),
                    ],
                    if (_section == 'brokers') ...[
                      Text(
                        'Brokers',
                        style: tt.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (brokers.isEmpty)
                        Text(
                          'No matching brokers.',
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        )
                      else
                        ...brokers.map((m) {
                          final id = m['id']?.toString() ?? '';
                          final name = m['name']?.toString() ?? 'Broker';
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.handshake_outlined,
                                color: cs.secondary),
                            title: Text(name),
                            trailing:
                                const Icon(Icons.chevron_right_rounded),
                            onTap: id.isEmpty
                                ? null
                                : () => context.push('/broker/$id'),
                          );
                        }),
                    ],
                    if (_section == 'contacts') ...[
                      Text(
                        'Contacts',
                        style: tt.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Suppliers and brokers (same hub as Contacts → search).',
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Suppliers',
                        style: tt.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (suppliers.isEmpty)
                        Text(
                          'No matching suppliers.',
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        )
                      else
                        ...suppliers.map((m) {
                          final id = m['id']?.toString() ?? '';
                          final name = m['name']?.toString() ?? 'Supplier';
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.storefront_outlined,
                                color: cs.primary),
                            title: Text(name),
                            trailing:
                                const Icon(Icons.chevron_right_rounded),
                            onTap: id.isEmpty
                                ? null
                                : () => context.push('/supplier/$id'),
                          );
                        }),
                      const SizedBox(height: 12),
                      Text(
                        'Brokers',
                        style: tt.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (brokers.isEmpty)
                        Text(
                          'No matching brokers.',
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        )
                      else
                        ...brokers.map((m) {
                          final id = m['id']?.toString() ?? '';
                          final name = m['name']?.toString() ?? 'Broker';
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.handshake_outlined,
                                color: cs.secondary),
                            title: Text(name),
                            trailing:
                                const Icon(Icons.chevron_right_rounded),
                            onTap: id.isEmpty
                                ? null
                                : () => context.push('/broker/$id'),
                          );
                        }),
                    ],
                  ],
                    ),
                  ],
                );
              },
      );
    }

    final resultsBody = _wrapDesktopSearchSplit(
      context: context,
      query: q,
      scrollBody: scrollBody,
    );

    if (widget.embeddedInShell || widget.staffShellEmbedded) {
      return Scaffold(
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _embeddedSearchTextField(cs),
              _embeddedCategoryChips(),
              Expanded(child: resultsBody),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            final s = ref.read(sessionProvider);
            context.popOrGo(
                s != null ? authenticatedHomePath(s) : '/login');
          },
        ),
        title: const Text('Search'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _standaloneTopSearchBar(cs),
          Expanded(child: resultsBody),
        ],
      ),
    );
  }

  Widget _wrapDesktopSearchSplit({
    required BuildContext context,
    required String query,
    required Widget scrollBody,
  }) {
    if (!context.isDesktopLayout || query.isEmpty) {
      return scrollBody;
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 4, child: scrollBody),
        const VerticalDivider(width: 1, thickness: 1),
        Expanded(
          flex: 5,
          child: SearchDesktopPreviewPane(
            itemId: _desktopPreviewItemId,
            itemName: _desktopPreviewItemName,
          ),
        ),
      ],
    );
  }
}

class _SearchLoadingFallback extends StatefulWidget {
  const _SearchLoadingFallback({
    required this.padding,
    required this.recents,
    required this.onApplyQuery,
  });

  final EdgeInsets padding;
  final List<String> recents;
  final ValueChanged<String> onApplyQuery;

  @override
  State<_SearchLoadingFallback> createState() => _SearchLoadingFallbackState();
}

class _SearchLoadingFallbackState extends State<_SearchLoadingFallback> {
  bool _showFallback = false;

  @override
  void initState() {
    super.initState();
    Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showFallback = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_showFallback) {
      return ListView(
        padding: widget.padding,
        children: const [
          Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
      );
    }
    return ListView(
      padding: widget.padding,
      children: [
        const Text(
          'Search is taking longer than expected. You can keep navigating or try a recent item.',
          style: TextStyle(fontSize: 13, color: Colors.black54),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final r in widget.recents.take(8))
              ActionChip(label: Text(r), onPressed: () => widget.onApplyQuery(r)),
          ],
        ),
      ],
    );
  }
}
