import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/design_system/hexa_operational_tokens.dart';
import '../../../core/json_coerce.dart';
import '../../../core/providers/staff_home_providers.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/utils/unit_utils.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../../../core/widgets/hexa_elevated_autocomplete.dart';
import '../../stock/presentation/quick_stock_action_sheet.dart';
import '../../stock/presentation/widgets/stock_update_mode_toggle.dart';

enum _StaffGalleryFilter {
  all,
  missingCode,
  missingBarcode,
  lowStock,
  openingMissing,
}

String _staffGalleryFilterLabel(_StaffGalleryFilter f) => switch (f) {
      _StaffGalleryFilter.all => 'All',
      _StaffGalleryFilter.missingCode => 'No item code',
      _StaffGalleryFilter.missingBarcode => 'No barcode',
      _StaffGalleryFilter.lowStock => 'Low / out',
      _StaffGalleryFilter.openingMissing => 'Opening',
    };

bool _itemMatchesGalleryFilter(
  Map<String, dynamic> item,
  _StaffGalleryFilter filter,
) {
  return switch (filter) {
    _StaffGalleryFilter.all => true,
    _StaffGalleryFilter.missingCode =>
      (item['item_code']?.toString().trim() ?? '').isEmpty,
    _StaffGalleryFilter.missingBarcode => item['missing_barcode'] == true,
    _StaffGalleryFilter.lowStock => _itemLowOrOut(item),
    _StaffGalleryFilter.openingMissing =>
      item['opening_stock_set'] == false ||
          item['needs_opening_stock'] == true,
  };
}

bool _itemLowOrOut(Map<String, dynamic> item) {
  final stock = coerceToDouble(item['current_stock']);
  final reorder = coerceToDouble(item['reorder_level']);
  final status = (item['stock_status']?.toString() ?? '').toLowerCase();
  return stock <= 0 ||
      status == 'out' ||
      status == 'low' ||
      status == 'critical' ||
      (reorder > 0 && stock <= reorder);
}

Map<String, Map<String, List<Map<String, dynamic>>>> _groupGalleryItems(
  Iterable<Map<String, dynamic>> items,
) {
  final grouped = <String, Map<String, List<Map<String, dynamic>>>>{};
  for (final raw in items) {
    final cat = raw['category_name']?.toString().trim().isNotEmpty == true
        ? raw['category_name'].toString().trim()
        : 'Uncategorized';
    final sub = raw['subcategory_name']?.toString().trim().isNotEmpty == true
        ? raw['subcategory_name'].toString().trim()
        : raw['type_name']?.toString().trim().isNotEmpty == true
            ? raw['type_name'].toString().trim()
            : '—';
    grouped.putIfAbsent(cat, () => {});
    grouped[cat]!.putIfAbsent(sub, () => []);
    grouped[cat]![sub]!.add(raw);
  }
  for (final subMap in grouped.values) {
    for (final list in subMap.values) {
      list.sort(
        (a, b) => (a['name']?.toString() ?? '')
            .toLowerCase()
            .compareTo((b['name']?.toString() ?? '').toLowerCase()),
      );
    }
  }
  return grouped;
}

List<String> _gallerySuggestions(List<Map<String, dynamic>> items) {
  final out = <String>{};
  for (final it in items) {
    final name = it['name']?.toString().trim();
    if (name != null && name.isNotEmpty) out.add(name);
    final code = it['item_code']?.toString().trim();
    if (code != null && code.isNotEmpty) out.add(code);
    final sub = it['subcategory_name']?.toString().trim();
    if (sub != null && sub.isNotEmpty) out.add(sub);
    final cat = it['category_name']?.toString().trim();
    if (cat != null && cat.isNotEmpty) out.add(cat);
  }
  final list = out.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return list;
}

/// Staff browse: category → subcategory → items with stock + code status.
class StaffItemGalleryPage extends ConsumerStatefulWidget {
  const StaffItemGalleryPage({super.key, this.initialFilter});

  /// Query key: `missing_code`, `missing_barcode`, `low`, `opening`.
  final String? initialFilter;

  @override
  ConsumerState<StaffItemGalleryPage> createState() =>
      _StaffItemGalleryPageState();
}

class _StaffItemGalleryPageState extends ConsumerState<StaffItemGalleryPage> {
  late _StaffGalleryFilter _filter;
  String _search = '';
  Timer? _debounce;
  final _expandedCats = <String>{};
  final _subTabByCat = <String, String?>{};

  @override
  void initState() {
    super.initState();
    _filter = _filterFromQuery(widget.initialFilter);
  }

  _StaffGalleryFilter _filterFromQuery(String? raw) {
    return switch (raw?.trim().toLowerCase()) {
      'missing_code' || 'code' => _StaffGalleryFilter.missingCode,
      'missing_barcode' || 'barcode' => _StaffGalleryFilter.missingBarcode,
      'low' || 'low_stock' => _StaffGalleryFilter.lowStock,
      'opening' || 'opening_stock' => _StaffGalleryFilter.openingMissing,
      _ => _StaffGalleryFilter.all,
    };
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  bool _itemMatchesSearch(Map<String, dynamic> it, String q) {
    if (q.isEmpty) return true;
    final hay = [
      it['name'],
      it['item_code'],
      it['category_name'],
      it['subcategory_name'],
      it['type_name'],
    ].whereType<String>().join(' ').toLowerCase();
    return hay.contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(staffGalleryStockProvider);

    return Scaffold(
      backgroundColor: HexaColors.brandBackground,
      appBar: AppBar(
        title: const Text('Item gallery'),
        backgroundColor: Colors.transparent,
        foregroundColor: HexaColors.brandPrimary,
      ),
      body: itemsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => FriendlyLoadError(
          message: 'Could not load items',
          onRetry: () => ref.invalidate(staffGalleryStockProvider),
        ),
        data: (allItems) {
          final q = _search.trim().toLowerCase();
          final filtered = allItems.where((it) {
            if (!_itemMatchesGalleryFilter(it, _filter)) return false;
            return _itemMatchesSearch(it, q);
          }).toList();
          final grouped = _groupGalleryItems(filtered);
          final cats = grouped.keys.toList()..sort();
          final suggestions = _gallerySuggestions(allItems);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  HexaOp.pageGutter,
                  0,
                  HexaOp.pageGutter,
                  4,
                ),
                child: Autocomplete<String>(
                  optionsViewBuilder: (context, onSelected, options) {
                    return hexaElevatedAutocompleteOptions<String>(
                      context,
                      onSelected,
                      options,
                      label: (v) => v,
                    );
                  },
                  optionsBuilder: (text) {
                    final needle = text.text.trim().toLowerCase();
                    if (needle.isEmpty) return const Iterable<String>.empty();
                    return suggestions
                        .where((s) => s.toLowerCase().contains(needle))
                        .take(12);
                  },
                  onSelected: (v) => setState(() => _search = v),
                  fieldViewBuilder: (ctx, ctrl, focus, onFieldSubmitted) {
                    if (ctrl.text != _search) ctrl.text = _search;
                    return TextField(
                      controller: ctrl,
                      focusNode: focus,
                      onChanged: (v) {
                        _debounce?.cancel();
                        _debounce = Timer(const Duration(milliseconds: 200), () {
                          if (!mounted) return;
                          setState(() => _search = v.trim());
                        });
                      },
                      onSubmitted: (_) => onFieldSubmitted(),
                      decoration: InputDecoration(
                        hintText: 'Name, item code, category, subcategory…',
                        isDense: true,
                        prefixIcon: const Icon(Icons.search, size: 20),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    );
                  },
                ),
              ),
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    for (final f in _StaffGalleryFilter.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(
                            _staffGalleryFilterLabel(f),
                            style: const TextStyle(fontSize: 11),
                          ),
                          selected: _filter == f,
                          onSelected: (_) => setState(() => _filter = f),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  '${filtered.length} items · ${cats.length} categories',
                  style: HexaDsType.label(11, color: HexaDsColors.textMuted),
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text(
                          'No items match',
                          style: HexaDsType.body(14,
                              color: HexaDsColors.textMuted),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 88),
                        itemCount: cats.length,
                        itemBuilder: (ctx, ci) {
                          final cat = cats[ci];
                          final subMap = grouped[cat]!;
                          final expanded = _expandedCats.contains(cat);
                          final subs = subMap.keys.toList()..sort();
                          return Card(
                            margin: const EdgeInsets.only(bottom: 6),
                            clipBehavior: Clip.antiAlias,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: const BorderSide(color: Color(0xFFE2E8E6)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                ListTile(
                                  dense: true,
                                  title: Text(
                                    cat,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                    ),
                                  ),
                                  trailing: Icon(
                                    expanded
                                        ? Icons.expand_less
                                        : Icons.expand_more,
                                    size: 20,
                                  ),
                                  onTap: () => setState(() {
                                    if (expanded) {
                                      _expandedCats.remove(cat);
                                    } else {
                                      _expandedCats.add(cat);
                                    }
                                  }),
                                ),
                                if (expanded) ...[
                                  if (subs.length > 1)
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          8, 0, 8, 6),
                                      child: SingleChildScrollView(
                                        scrollDirection: Axis.horizontal,
                                        child: Row(
                                          children: [
                                            ChoiceChip(
                                              label: const Text('All',
                                                  style: TextStyle(
                                                      fontSize: 11)),
                                              selected:
                                                  _subTabByCat[cat] == null,
                                              onSelected: (_) => setState(
                                                  () => _subTabByCat
                                                      .remove(cat)),
                                              visualDensity:
                                                  VisualDensity.compact,
                                            ),
                                            for (final sub in subs)
                                              if (sub != '—')
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          left: 6),
                                                  child: ChoiceChip(
                                                    label: Text(sub,
                                                        style: const TextStyle(
                                                            fontSize: 11)),
                                                    selected: _subTabByCat[
                                                            cat] ==
                                                        sub,
                                                    onSelected: (_) =>
                                                        setState(() =>
                                                            _subTabByCat[
                                                                cat] = sub),
                                                    visualDensity:
                                                        VisualDensity.compact,
                                                  ),
                                                ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  for (final subEntry in subMap.entries)
                                    if (_subTabByCat[cat] == null ||
                                        _subTabByCat[cat] == subEntry.key)
                                      ...subEntry.value.map(
                                        (item) => _StaffGalleryItemRow(
                                          item: item,
                                          hideSub: _subTabByCat[cat] != null ||
                                              subEntry.key == '—',
                                        ),
                                      ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StaffGalleryItemRow extends ConsumerWidget {
  const _StaffGalleryItemRow({
    required this.item,
    this.hideSub = false,
  });

  final Map<String, dynamic> item;
  final bool hideSub;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = item['id']?.toString() ?? '';
    final name = item['name']?.toString() ?? 'Item';
    final sub = item['subcategory_name']?.toString().trim() ??
        item['type_name']?.toString().trim() ??
        '';
    final unit = item['stock_unit']?.toString() ??
        item['default_unit']?.toString() ??
        'bag';
    final stock = coerceToDouble(item['current_stock']);
    final code = item['item_code']?.toString().trim() ?? '';
    final missingBc = item['missing_barcode'] == true;
    final low = _itemLowOrOut(item);

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
      title: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!hideSub && sub.isNotEmpty)
            Text(sub, style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
          Text(
            'Stock: ${formatStockQtyNumber(stock)} $unit'
            '${code.isNotEmpty ? ' · $code' : ' · No code'}'
            '${missingBc ? ' · No barcode' : ''}',
            style: TextStyle(
              fontSize: 12,
              color: low ? const Color(0xFFDC2626) : const Color(0xFF64748B),
              fontWeight: low ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, size: 20),
        onSelected: (v) async {
          if (id.isEmpty) return;
          if (v == 'stock') {
            await showQuickStockActionSheet(
              context: context,
              ref: ref,
              item: item,
              initialMode: StockUpdateMode.physical,
            );
          } else if (v == 'item') {
            if (context.mounted) context.push('/catalog/item/$id');
          } else if (v == 'reorder') {
            if (context.mounted) {
              context.push('/catalog/item/$id/edit');
            }
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'stock', child: Text('Update stock')),
          PopupMenuItem(value: 'reorder', child: Text('Reorder / opening')),
          PopupMenuItem(value: 'item', child: Text('Item profile')),
        ],
      ),
      onTap: id.isEmpty ? null : () => context.push('/catalog/item/$id'),
    );
  }
}
