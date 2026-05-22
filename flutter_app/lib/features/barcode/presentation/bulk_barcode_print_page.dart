import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../../core/design_system/hexa_operational_tokens.dart';
import '../../../core/errors/barcode_operation_errors.dart';
import '../../../core/providers/stock_providers.dart';
import '../../../core/widgets/hexa_error_card.dart';
import '../../stock/presentation/widgets/operational_stock_filter_sheet.dart';
import '../services/barcode_pdf_service.dart';
import '../services/bulk_label_batch.dart';
import 'bulk_barcode_print_controller.dart';
import 'bulk_barcode_print_preview_panel.dart';
import 'bulk_barcode_print_toolbar.dart';

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
  final int _perRow = 2;
  bool _busy = false;
  bool _denseA4 = true;
  bool _useQr = true;
  String? _pdfStatus;
  int _labelProgressDone = 0;
  int _labelProgressTotal = 0;

  @override
  void initState() {
    super.initState();
    _searchCtrl.text = ref.read(stockListQueryProvider).q;
  }

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

  Future<BulkLabelBatchResult> _loadLabels({List<String>? ids}) async {
    final target = ids ?? ref.read(bulkBarcodeSelectionProvider).toList();
    if (mounted) {
      setState(() {
        _labelProgressTotal = target.length;
        _labelProgressDone = 0;
      });
    }
    final batch = await fetchBulkLabels(
      ref: ref,
      ids: target,
      onProgress: (done, total) {
        if (!mounted) return;
        setState(() {
          _labelProgressDone = done;
          _labelProgressTotal = total;
          _pdfStatus = 'Preparing labels… $done / $total';
        });
      },
    );
    return batch;
  }

  Future<void> _runPdfFlow({
    required Future<void> Function(Uint8List pdf) action,
  }) async {
    if (_selected.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      var batch = await _loadLabels();
      if (batch.isTotalFailure) {
        if (!mounted) return;
        _showError(
          '${batch.failedIds.length} items could not be loaded. '
          'Check barcodes and try again.',
        );
        return;
      }
      if (batch.hasPartialFailure) {
        final cont = await showPartialLabelFailureDialog(context, batch);
        if (cont != true) return;
      }
      setState(() => _pdfStatus = 'Generating PDF…');
      final symbol = _useQr
          ? BarcodeSymbolMode.code128WithQr
          : BarcodeSymbolMode.code128;
      final pdf = await generateBulkPdfBytes(
        context: context,
        ref: ref,
        batch: batch,
        denseA4: _denseA4,
        copies: _copies,
        perRow: _perRow,
        symbol: symbol,
        thermalSize: _thermalSize,
      );
      await action(pdf);
    } on BarcodeOperationException catch (e) {
      if (!mounted) return;
      _showError(e.message);
    } catch (e, st) {
      logBarcodeOperationError(e, st);
      if (!mounted) return;
      _showError(barcodeMessageForUser(e));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _pdfStatus = null;
          _labelProgressDone = 0;
          _labelProgressTotal = 0;
        });
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
        action: SnackBarAction(
          label: 'Retry',
          textColor: Colors.white,
          onPressed: () {},
        ),
      ),
    );
  }

  Future<void> _preview() => _runPdfFlow(action: (pdf) async {
    if (!mounted) return;
    final count = _selected.length * _copies;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (ctx) => Scaffold(
          appBar: AppBar(title: Text('Preview ($count labels)')),
          body: PdfPreview(
            build: (_) async => pdf,
            canChangeOrientation: false,
            canChangePageFormat: false,
            canDebug: false,
          ),
        ),
      ),
    );
  });

  Future<void> _downloadPdf() => _runPdfFlow(action: (pdf) async {
    await Printing.sharePdf(
      bytes: pdf,
      filename: _bulkBarcodeFilename(),
    );
  });

  Future<void> _print() => _runPdfFlow(action: (pdf) async {
    if (kIsWeb) {
      await Printing.sharePdf(
        bytes: pdf,
        filename: _bulkBarcodeFilename(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'On web, use the downloaded PDF to print from your browser.',
          ),
        ),
      );
      return;
    }
    await guardWebPrint(() => Printing.layoutPdf(
          name: _bulkBarcodeFilename(),
          onLayout: (_) async => pdf,
        ));
  });

  String _bulkBarcodeFilename() {
    final q = ref.read(stockListQueryProvider);
    final raw = q.category.trim().isNotEmpty ? q.category.trim() : 'all_items';
    final category = raw
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final date = DateFormat('yyyyMMdd').format(DateTime.now());
    return 'harisree_barcodes_${category.isEmpty ? 'all_items' : category}_$date.pdf';
  }

  List<Map<String, dynamic>> _applyClientFilters(List<Map<String, dynamic>> items) {
    final op = ref.read(stockOperationalFiltersProvider);
    return [
      for (final it in items)
        if (_passesOperational(it, op)) it,
    ];
  }

  bool _passesOperational(Map<String, dynamic> it, StockOperationalFilters op) {
    if (op.missingBarcodeOnly && it['missing_barcode'] != true) return false;
    if (op.missingItemCodeOnly && it['missing_item_code'] != true) return false;
    if (op.reorderOnly) {
      final reorder = double.tryParse('${it['reorder_level']}') ?? 0;
      final current = double.tryParse('${it['current_stock']}') ?? 0;
      if (reorder <= 0 || current > reorder) return false;
    }
    if (op.unit.isNotEmpty) {
      final u = (it['unit']?.toString() ?? '').toLowerCase();
      if (u != op.unit) return false;
    }
    return true;
  }

  Widget _searchRow() {
    final q = ref.watch(stockListQueryProvider);
    final op = ref.watch(stockOperationalFiltersProvider);
    final filterCount = countOperationalActiveFilters(q, op);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        HexaOp.pageGutter,
        8,
        HexaOp.pageGutter,
        4,
      ),
      child: TextField(
        controller: _searchCtrl,
        decoration: InputDecoration(
          hintText: 'Search name, code, barcode, category…',
          prefixIcon: const Icon(Icons.search_rounded),
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          suffixIcon: IconButton(
            tooltip: 'Filters',
            onPressed: () => showOperationalStockFilter(context: context, ref: ref),
            icon: Badge(
              isLabelVisible: filterCount > 0,
              label: Text('$filterCount'),
              child: const Icon(Icons.tune_rounded),
            ),
          ),
        ),
        onChanged: (v) {
          _searchDebounce?.cancel();
          _searchDebounce = Timer(const Duration(milliseconds: 300), () {
            if (!mounted) return;
            ref.read(stockListQueryProvider.notifier).state =
                ref.read(stockListQueryProvider).copyWith(q: v.trim(), page: 1);
          });
        },
      ),
    );
  }

  Widget _filterSummaryChip() {
    final q = ref.watch(stockListQueryProvider);
    final op = ref.watch(stockOperationalFiltersProvider);
    final summary = stockActiveFilterSummary(q, op);
    if (summary.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: HexaOp.pageGutter),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ActionChip(
          label: Text('Filters: $summary', style: const TextStyle(fontSize: 11)),
          onPressed: () => showOperationalStockFilter(context: context, ref: ref),
        ),
      ),
    );
  }

  Widget _quickFilterChips() {
    final q = ref.watch(stockListQueryProvider);
    final op = ref.watch(stockOperationalFiltersProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(HexaOp.pageGutter, 2, HexaOp.pageGutter, 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          FilterChip(
            label: const Text('Missing code', style: TextStyle(fontSize: 11)),
            selected: op.missingItemCodeOnly,
            onSelected: (_) {
              ref.read(stockOperationalFiltersProvider.notifier).state = op.copyWith(
                missingItemCodeOnly: !op.missingItemCodeOnly,
              );
            },
            visualDensity: VisualDensity.compact,
          ),
          FilterChip(
            label: const Text('Missing barcode', style: TextStyle(fontSize: 11)),
            selected: op.missingBarcodeOnly,
            onSelected: (_) {
              ref.read(stockOperationalFiltersProvider.notifier).state = op.copyWith(
                missingBarcodeOnly: !op.missingBarcodeOnly,
              );
            },
            visualDensity: VisualDensity.compact,
          ),
          FilterChip(
            label: const Text('Low stock', style: TextStyle(fontSize: 11)),
            selected: q.status == 'low',
            onSelected: (_) {
              ref.read(stockListQueryProvider.notifier).state = q.copyWith(
                status: q.status == 'low' ? 'all' : 'low',
                page: 1,
              );
            },
            visualDensity: VisualDensity.compact,
          ),
          FilterChip(
            label: const Text('Reorder', style: TextStyle(fontSize: 11)),
            selected: op.reorderOnly,
            onSelected: (_) {
              ref.read(stockOperationalFiltersProvider.notifier).state = op.copyWith(
                reorderOnly: !op.reorderOnly,
              );
            },
            visualDensity: VisualDensity.compact,
          ),
          ActionChip(
            label: const Text('Category/Supplier', style: TextStyle(fontSize: 11)),
            onPressed: () => showOperationalStockFilter(context: context, ref: ref),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(bulkBarcodeSelectionProvider);
    final listAsync = ref.watch(bulkStockListProvider);
    final progress = _labelProgressTotal > 0
        ? _labelProgressDone / _labelProgressTotal
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bulk print'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Text(
                '${selected.length} selected',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
              ),
            ),
          ),
          if (selected.isNotEmpty)
            TextButton(
              onPressed: () => _setSelected({}),
              child: const Text('Clear'),
            ),
        ],
      ),
      bottomNavigationBar: BulkBarcodePrintToolbar(
        selectedCount: selected.length,
        busy: _busy,
        denseA4: _denseA4,
        useQr: _useQr,
        copies: _copies,
        progress: progress,
        statusText: _pdfStatus,
        onDenseA4Changed: (v) => setState(() => _denseA4 = v),
        onQrChanged: (v) => setState(() => _useQr = v),
        onCopiesChanged: (v) => setState(() => _copies = v),
        onPreview: _preview,
        onPdf: _downloadPdf,
        onPrint: _print,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final desktop = constraints.maxWidth >= kOperationalDesktopBreakpoint;
          final listPane = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _searchRow(),
              _quickFilterChips(),
              _filterSummaryChip(),
              Expanded(
                child: listAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => HexaErrorCard.fromError(
                    error: e,
                    title: 'Could not load items',
                    onRetry: () => ref.invalidate(bulkStockListProvider),
                  ),
                  data: (data) => _buildList(data, selected, desktop),
                ),
              ),
            ],
          );

          if (desktop) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: listPane),
                const VerticalDivider(width: 1),
                SizedBox(
                  width: 380,
                  child: BulkBarcodePrintPreviewPanel(
                    denseA4: _denseA4,
                    useQr: _useQr,
                    copies: _copies,
                    selectedCount: selected.length,
                    onPreviewAll: () => unawaited(_preview()),
                  ),
                ),
              ],
            );
          }
          return listPane;
        },
      ),
    );
  }

  Widget _buildList(
    Map<String, dynamic> data,
    Set<String> selected,
    bool desktop,
  ) {
    final raw = (data['items'] as List?) ?? const [];
    final items = [
      for (final e in raw)
        if (e is Map) Map<String, dynamic>.from(e),
    ];
    final visible = _applyClientFilters(items);
    final total = data['total'];
    final loaded = items.length;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: HexaOp.pageGutter),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${visible.length} shown · $loaded loaded'
                  '${total != null ? ' · $total total' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
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
                  : (code.isEmpty ? '$barcode · $st' : '$code · $barcode · $st');
              return _BulkPrintRow(
                selected: selected.contains(id),
                name: name,
                subtitle: sub,
                stock: stock,
                stockHighlight: st == 'low' || st == 'critical',
                onChanged: (v) => _toggleSelected(id, v),
                onPreview: id.isEmpty
                    ? null
                    : () {
                        ref.read(bulkPreviewItemIdProvider.notifier).state = id;
                        if (!desktop) {
                          showModalBottomSheet<void>(
                            context: context,
                            showDragHandle: true,
                            builder: (_) => SizedBox(
                              height: 280,
                              child: BulkBarcodePrintPreviewPanel(
                                denseA4: _denseA4,
                                useQr: _useQr,
                                copies: _copies,
                                selectedCount: selected.length,
                                onPreviewAll: () {
                                  Navigator.pop(context);
                                  unawaited(_preview());
                                },
                              ),
                            ),
                          );
                        }
                      },
              );
            },
          ),
        ),
      ],
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
    this.onPreview,
  });

  final bool selected;
  final String name;
  final String subtitle;
  final String stock;
  final bool stockHighlight;
  final ValueChanged<bool> onChanged;
  final VoidCallback? onPreview;

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
                if (onPreview != null)
                  IconButton(
                    tooltip: 'Preview label',
                    icon: const Icon(Icons.visibility_outlined, size: 20),
                    onPressed: onPreview,
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
