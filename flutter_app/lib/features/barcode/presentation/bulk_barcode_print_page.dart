import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/design_system/hexa_operational_tokens.dart';
import '../../../core/json_coerce.dart';
import '../../../core/router/post_auth_route.dart';
import '../../../core/providers/catalog_providers.dart';
import '../../../core/providers/stock_providers.dart';
import '../../../core/errors/user_facing_errors.dart';
import '../../../core/widgets/hexa_error_card.dart';
import '../services/barcode_pdf_service.dart';

class BulkBarcodePrintPage extends ConsumerStatefulWidget {
  const BulkBarcodePrintPage({super.key});

  @override
  ConsumerState<BulkBarcodePrintPage> createState() =>
      _BulkBarcodePrintPageState();
}

class _BulkBarcodePrintPageState extends ConsumerState<BulkBarcodePrintPage> {
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  static const LabelSize _thermalSize = LabelSize.medium;
  int _copies = 1;
  int _perRow = 2;

  /// When true, narrow the loaded "all status" list to low + critical only (client-side).
  bool _lowStockOnly = false;

  /// When true, show only catalog rows with no item_code (needs label setup).
  bool _missingCodeOnly = false;
  String _searchText = '';
  bool _busy = false;
  bool _denseA4 = true;
  BarcodeSymbolMode _symbol = BarcodeSymbolMode.code128WithQr;
  String? _pdfStatus;
  int _labelProgressDone = 0;
  int _labelProgressTotal = 0;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Set<String> get _selected => ref.read(bulkBarcodeSelectionProvider);

  void _setSelected(Set<String> next) {
    ref.read(bulkBarcodeSelectionProvider.notifier).state = next;
  }

  void _toggleSelected(String id, bool on) {
    final next = Set<String>.from(_selected);
    if (on) {
      next.add(id);
    } else {
      next.remove(id);
    }
    _setSelected(next);
  }

  Future<List<BarcodeLabelData>> _fetchLabels() async {
    final session = ref.read(sessionProvider);
    final ids = ref.read(bulkBarcodeSelectionProvider).toList();
    if (session == null || ids.isEmpty) return [];
    if (mounted) {
      setState(() {
        _labelProgressTotal = ids.length;
        _labelProgressDone = 0;
      });
    }
    const chunkSize = 200;
    final api = ref.read(hexaApiProvider);
    final batch = <BarcodeLabelData>[];
    for (var i = 0; i < ids.length; i += chunkSize) {
      if (!mounted) break;
      final end = (i + chunkSize < ids.length) ? i + chunkSize : ids.length;
      if (mounted) {
        setState(() {
          _labelProgressDone = end;
          _pdfStatus = 'Preparing labels… $end / ${ids.length}';
        });
      }
      final labels = await api.barcodeLabelBatch(
        businessId: session.primaryBusiness.id,
        itemIds: ids.sublist(i, end),
      );
      for (final j in labels) {
        final label = BarcodeLabelData.fromApiMap(j);
        if (label != null) batch.add(label);
      }
    }
    return batch;
  }

  Future<Uint8List?> _buildPdf() async {
    setState(() => _pdfStatus = 'Fetching labels…');
    final batch = await _fetchLabels();
    if (batch.isEmpty) {
      if (mounted) setState(() => _pdfStatus = null);
      return null;
    }
    setState(() => _pdfStatus = 'Generating PDF…');
    final session = ref.read(sessionProvider);
    final hideFinancials =
        session != null && !sessionCanSeeFinancials(session);
    try {
      if (_denseA4) {
        final cols = MediaQuery.sizeOf(context).width >= 600 ? 4 : 2;
        return BarcodePdfService.generateBatchA4Dense(
          items: batch,
          size: _thermalSize,
          copiesPerItem: _copies,
          hideFinancials: hideFinancials,
          columns: cols,
        );
      }
      return BarcodePdfService.generateBatch(
        items: batch,
        size: _thermalSize,
        copiesPerItem: _copies,
        labelsPerRow: _perRow,
        hideFinancials: hideFinancials,
        symbol: _symbol,
      );
    } finally {
      if (mounted) setState(() => _pdfStatus = null);
    }
  }

  Future<void> _preview() async {
    if (_selected.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final pdf = await _buildPdf();
      if (pdf == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No printable labels')),
        );
        return;
      }
      if (!mounted) return;
      final count = _selected.length * _copies;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (ctx) => Scaffold(
            appBar: AppBar(
              title: Text('Preview ($count labels)'),
            ),
            body: PdfPreview(
              build: (_) async => pdf,
              canChangeOrientation: false,
              canChangePageFormat: false,
              canDebug: false,
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userFacingError(e)),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _print() async {
    if (_selected.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final pdf = await _buildPdf();
      if (pdf == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No printable labels')),
        );
        return;
      }
      await Printing.layoutPdf(
        name: _bulkBarcodeFilename(),
        onLayout: (_) async => pdf,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userFacingError(e)),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _downloadPdf() async {
    if (_selected.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final pdf = await _buildPdf();
      if (pdf == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No printable labels')),
        );
        return;
      }
      await Printing.sharePdf(
        bytes: pdf,
        filename: _bulkBarcodeFilename(),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userFacingError(e)),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<Map<String, dynamic>> _filterItems(List<Map<String, dynamic>> items) {
    final q = _searchText.trim().toLowerCase();
    return [
      for (final it in items)
        if (_matches(it, q)) it,
    ];
  }

  bool _matches(Map<String, dynamic> it, String q) {
    final st = it['stock_status']?.toString() ?? 'healthy';
    if (_lowStockOnly && st != 'low' && st != 'critical') {
      return false;
    }
    final barcode = it['barcode']?.toString().trim() ?? '';
    if (_missingCodeOnly && barcode.isNotEmpty) {
      return false;
    }
    if (q.isEmpty) return true;
    final name = it['name']?.toString().toLowerCase() ?? '';
    final codeQ = it['item_code']?.toString().toLowerCase() ?? '';
    final barcodeQ = it['barcode']?.toString().toLowerCase() ?? '';
    return name.contains(q) || codeQ.contains(q) || barcodeQ.contains(q);
  }

  String _bulkBarcodeFilename() {
    final q = ref.read(stockListQueryProvider);
    final raw = q.category.trim().isNotEmpty
        ? q.category.trim()
        : (_missingCodeOnly
            ? 'missing_code'
            : (_lowStockOnly ? 'low_stock' : 'all_items'));
    final category = raw
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    final date = DateFormat('yyyyMMdd').format(DateTime.now());
    return 'harisree_barcodes_${category.isEmpty ? 'all_items' : category}_$date.pdf';
  }

  String? _categoryIdForName(List<Map<String, dynamic>> cats, String name) {
    final t = name.trim();
    if (t.isEmpty) return null;
    for (final c in cats) {
      if ((c['name']?.toString().trim() ?? '') == t) {
        return c['id']?.toString();
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(bulkBarcodeSelectionProvider);
    final listQ = ref.watch(stockListQueryProvider);
    final listAsync = ref.watch(bulkStockListProvider);
    final catsAsync = ref.watch(itemCategoriesListProvider);

    final progress = _labelProgressTotal > 0
        ? _labelProgressDone / _labelProgressTotal
        : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          selected.isEmpty
              ? 'Bulk print barcodes'
              : 'Bulk print (${selected.length})',
        ),
        actions: [
          if (selected.isNotEmpty)
            TextButton(
              onPressed: () => _setSelected({}),
              child: const Text('Clear'),
            ),
        ],
      ),
      bottomNavigationBar: _buildStickyBar(selected, progress),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          final filters = <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              HexaOp.pageGutter,
              8,
              HexaOp.pageGutter,
              0,
            ),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search items…',
                prefixIcon: const Icon(Icons.search_rounded),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (v) {
                _searchDebounce?.cancel();
                _searchDebounce = Timer(const Duration(milliseconds: 300), () {
                  if (mounted) setState(() => _searchText = v.trim().toLowerCase());
                });
              },
            ),
          ),
          const SizedBox(height: 6),
          catsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: LinearProgressIndicator(minHeight: 2),
            ),
            error: (_, __) => const SizedBox.shrink(),
            data: (cats) {
              final names = [
                'All',
                for (final c in cats)
                  if ((c['name'] ?? '').toString().trim().isNotEmpty)
                    c['name'].toString().trim(),
              ];
              final cid = _categoryIdForName(cats, listQ.category);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final name in names)
                          FilterChip(
                            label: Text(
                              name,
                              style: const TextStyle(fontSize: 12),
                            ),
                            selected: name == 'All'
                                ? listQ.category.isEmpty
                                : listQ.category == name,
                            onSelected: (_) {
                              final cur = ref.read(stockListQueryProvider);
                              final n =
                                  ref.read(stockListQueryProvider.notifier);
                              if (name == 'All') {
                                n.state =
                                    cur.copyWith(category: '', subcategory: '');
                              } else {
                                n.state = cur.copyWith(
                                    category: name, subcategory: '');
                              }
                            },
                          ),
                      ],
                    ),
                    if (cid != null && cid.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      ref.watch(categoryTypesListProvider(cid)).when(
                            loading: () => const LinearProgressIndicator(
                              minHeight: 2,
                            ),
                            error: (_, __) => const SizedBox.shrink(),
                            data: (types) {
                              final typeNames = [
                                for (final t in types)
                                  if ((t['name'] ?? '')
                                      .toString()
                                      .trim()
                                      .isNotEmpty)
                                    t['name'].toString().trim(),
                              ];
                              return Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  FilterChip(
                                    label: const Text(
                                      'All types',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                    selected: listQ.subcategory.isEmpty,
                                    onSelected: (_) {
                                      final cur =
                                          ref.read(stockListQueryProvider);
                                      ref
                                          .read(stockListQueryProvider.notifier)
                                          .state = cur.copyWith(subcategory: '');
                                    },
                                  ),
                                  for (final sub in typeNames)
                                    FilterChip(
                                      label: Text(
                                        sub,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      selected: listQ.subcategory == sub,
                                      onSelected: (_) {
                                        final cur =
                                            ref.read(stockListQueryProvider);
                                        ref
                                                .read(stockListQueryProvider
                                                    .notifier)
                                                .state =
                                            cur.copyWith(subcategory: sub);
                                      },
                                    ),
                                ],
                              );
                            },
                          ),
                    ],
                  ],
                ),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                FilterChip(
                  label: const Text('All', style: TextStyle(fontSize: 12)),
                  selected: listQ.status == 'all' &&
                      !_lowStockOnly &&
                      !_missingCodeOnly,
                  onSelected: (_) {
                    ref.read(stockListQueryProvider.notifier).state = ref
                        .read(stockListQueryProvider)
                        .copyWith(status: 'all');
                    setState(() {
                      _lowStockOnly = false;
                      _missingCodeOnly = false;
                    });
                  },
                ),
                FilterChip(
                  label:
                      const Text('Low stock', style: TextStyle(fontSize: 12)),
                  selected: listQ.status == 'all' &&
                      _lowStockOnly &&
                      !_missingCodeOnly,
                  onSelected: (_) {
                    ref.read(stockListQueryProvider.notifier).state = ref
                        .read(stockListQueryProvider)
                        .copyWith(status: 'all');
                    setState(() {
                      _lowStockOnly = true;
                      _missingCodeOnly = false;
                    });
                  },
                ),
                FilterChip(
                  label: const Text('Missing barcode',
                      style: TextStyle(fontSize: 12)),
                  selected: _missingCodeOnly,
                  onSelected: (_) {
                    ref.read(stockListQueryProvider.notifier).state = ref
                        .read(stockListQueryProvider)
                        .copyWith(status: 'all');
                    setState(() {
                      _missingCodeOnly = true;
                      _lowStockOnly = false;
                    });
                  },
                ),
                FilterChip(
                  label: const Text('Out of stock',
                      style: TextStyle(fontSize: 12)),
                  selected: listQ.status == 'out',
                  onSelected: (_) {
                    ref.read(stockListQueryProvider.notifier).state = ref
                        .read(stockListQueryProvider)
                        .copyWith(status: 'out');
                    setState(() {
                      _lowStockOnly = false;
                      _missingCodeOnly = false;
                    });
                  },
                ),
              ],
            ),
          ),
          ];
          final listPane = listAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => HexaErrorCard.fromError(
                error: e,
                title: 'Could not load items',
                onRetry: () => ref.invalidate(bulkStockListProvider),
              ),
              data: (data) {
                final raw = (data['items'] as List?) ?? const [];
                final items = [
                  for (final e in raw)
                    if (e is Map) Map<String, dynamic>.from(e),
                ];
                final visible = _filterItems(items);
                final total = coerceToIntNullable(data['total']);
                final loadedRaw = coerceToInt(data['loaded']);
                final loadedShown =
                    loadedRaw > 0 ? loadedRaw : items.length;
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${selected.length} selected · '
                              '${visible.length} shown'
                              '${total != null ? ' · $loadedShown of $total loaded' : ''}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                          TextButton(
                            onPressed: visible.isEmpty
                                ? null
                                : () => _setSelected({
                                      for (final e in visible)
                                        if (e['id'] != null) e['id'].toString(),
                                    }),
                            child: const Text('Select all'),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: visible.length,
                        itemBuilder: (context, i) {
                          final it = visible[i];
                          final id = it['id']?.toString() ?? '';
                          final name = it['name']?.toString() ?? '';
                          final code = it['item_code']?.toString() ?? '';
                          final barcode = it['barcode']?.toString() ?? '';
                          final st = it['stock_status']?.toString() ?? '';
                          final stock = it['current_stock']?.toString() ?? '—';
                          final sub = barcode.isEmpty
                              ? (code.isEmpty ? 'No barcode · $st' : '$code · $st')
                              : (code.isEmpty
                                  ? '$barcode · $st'
                                  : '$code · $barcode · $st');
                          return _BulkPrintRow(
                            selected: selected.contains(id),
                            name: name,
                            subtitle: sub,
                            stock: stock,
                            stockHighlight: st == 'low' || st == 'critical',
                            onChanged: (v) => _toggleSelected(id, v),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            );
          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 300,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: filters,
                    ),
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: listPane),
              ],
            );
          }
          return Column(
            children: [
              ...filters,
              Expanded(child: listPane),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStickyBar(Set<String> selected, double? progress) {
    return Material(
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            HexaOp.pageGutter,
            8,
            HexaOp.pageGutter,
            8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (progress != null || _pdfStatus != null) ...[
                LinearProgressIndicator(
                  minHeight: 3,
                  value: progress,
                ),
                if (_pdfStatus != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _pdfStatus!,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                const SizedBox(height: 8),
              ],
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  FilterChip(
                    label: const Text('A4', style: TextStyle(fontSize: 12)),
                    selected: _denseA4,
                    onSelected: _busy ? null : (_) => setState(() => _denseA4 = true),
                  ),
                  FilterChip(
                    label: const Text('Thermal', style: TextStyle(fontSize: 12)),
                    selected: !_denseA4,
                    onSelected:
                        _busy ? null : (_) => setState(() => _denseA4 = false),
                  ),
                  DropdownButton<int>(
                    value: _copies,
                    isDense: true,
                    items: [
                      for (final n in [1, 2, 3, 4, 5])
                        DropdownMenuItem(value: n, child: Text('$n×')),
                    ],
                    onChanged: _busy ? null : (v) => setState(() => _copies = v ?? 1),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: selected.isEmpty || _busy ? null : _preview,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(HexaOp.buttonHeight),
                      ),
                      child: const Text('Preview'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: selected.isEmpty || _busy ? null : _downloadPdf,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(HexaOp.buttonHeight),
                      ),
                      child: const Text('PDF'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: selected.isEmpty || _busy ? null : _print,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(HexaOp.buttonHeight),
                      ),
                      child: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Print'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BulkPrintRow extends StatelessWidget {
  const _BulkPrintRow({
    required this.selected,
    required this.name,
    required this.subtitle,
    required this.stock,
    required this.stockHighlight,
    required this.onChanged,
  });

  final bool selected;
  final String name;
  final String subtitle;
  final String stock;
  final bool stockHighlight;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: HexaOp.listRowMax,
      child: Material(
        color: Colors.white,
        child: InkWell(
          onTap: () => onChanged(!selected),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Checkbox(
                  value: selected,
                  onChanged: (v) => onChanged(v ?? false),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
                Text(
                  stock,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: stockHighlight ? const Color(0xFFE65100) : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
