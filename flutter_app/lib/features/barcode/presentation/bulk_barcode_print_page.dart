import 'dart:async';
import 'dart:math' show min;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/design_system/hexa_operational_tokens.dart';
import '../../../core/errors/barcode_operation_errors.dart';
import '../../../core/json_coerce.dart';
import '../../../core/providers/stock_providers.dart';
import '../../stock/presentation/widgets/stock_table_layout.dart';
import '../../../shared/widgets/stock_number_display.dart';
import '../../../core/widgets/hexa_error_card.dart';
import '../../stock/presentation/widgets/operational_stock_filter_sheet.dart';
import '../../../core/providers/api_degraded_provider.dart';
import '../services/barcode_pdf_service.dart';
import '../services/bulk_label_batch.dart';
import '../services/bulk_label_from_stock.dart';
import '../services/bulk_pdf_chunks.dart';
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
  static const LabelSize _thermalSize = LabelSize.small;
  int _copies = 1;
  final int _perRow = 2;
  bool _busy = false;
  bool _denseA4 = true;
  bool _useQr = false;
  BulkLabelsPerPdfFile _labelsPerPdfFile = BulkLabelsPerPdfFile.n50;
  String? _pdfStatus;
  int _labelProgressDone = 0;
  int _labelProgressTotal = 0;
  Future<void> Function()? _lastPdfRetry;
  bool _pdfCancelled = false;
  BuildContext? _pdfProgressDialogContext;

  @override
  void initState() {
    super.initState();
    _searchCtrl.text = ref.read(stockListQueryProvider).q;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncPdfFormatForSelection(ref.read(bulkBarcodeSelectionProvider).length);
    });
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
    _syncPdfFormatForSelection(next.length);
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

  /// Large batches: A4 sheet + Code128 + 50 labels per PDF file (web-safe).
  void _syncPdfFormatForSelection(int count) {
    if (count <= 25) return;
    var changed = false;
    if (!_denseA4) {
      _denseA4 = true;
      changed = true;
    }
    if (_useQr) {
      _useQr = false;
      changed = true;
    }
    if (_labelsPerPdfFile != BulkLabelsPerPdfFile.n50) {
      _labelsPerPdfFile = BulkLabelsPerPdfFile.n50;
      changed = true;
    }
    if (changed && mounted) setState(() {});
  }

  Map<String, Map<String, dynamic>> _stockRowsById() {
    final data = ref.read(bulkStockListProvider).valueOrNull;
    final items = data?['items'];
    if (items is! List) return const {};
    return stockRowsByIdFromList([
      for (final e in items)
        if (e is Map) Map<String, dynamic>.from(e),
    ]);
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
      stockById: _stockRowsById(),
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

  static const int _kMaxLabelsPerPdf = 100;

  int _pdfBatchCount(int selectedCount) =>
      (selectedCount + _kMaxLabelsPerPdf - 1) ~/ _kMaxLabelsPerPdf;

  List<List<String>> _chunkItemIds(List<String> ids) {
    final out = <List<String>>[];
    for (var i = 0; i < ids.length; i += _kMaxLabelsPerPdf) {
      out.add(ids.sublist(i, min(i + _kMaxLabelsPerPdf, ids.length)));
    }
    return out;
  }

  void _markIdsDownloaded(Iterable<String> ids) {
    final prev = ref.read(bulkBarcodeDownloadedIdsProvider);
    ref.read(bulkBarcodeDownloadedIdsProvider.notifier).state = {
      ...prev,
      ...ids,
    };
  }

  Future<void> _runPdfFlow({
    required Future<void> Function(
      List<Uint8List> pdfs,
      List<String> batchItemIds,
    ) action,
    required Future<void> Function() retry,
    bool multiBatch = false,
    bool previewMode = false,
  }) async {
    if (_selected.isEmpty || _busy) return;
    _lastPdfRetry = retry;
    _pdfCancelled = false;
    setState(() => _busy = true);
    try {
      var allIds = ref.read(bulkBarcodeSelectionProvider).toList();
      final rowsById = _stockRowsById();
      final printableIds = filterPrintableItemIds(allIds, rowsById);
      final skippedUnprintable = allIds.length - printableIds.length;
      if (skippedUnprintable > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              skippedUnprintable == allIds.length
                  ? 'None of the selected items have a barcode or item code.'
                  : 'Skipped $skippedUnprintable without barcode or item code.',
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
      if (printableIds.isEmpty) {
        if (mounted) {
          _showError(
            'No printable labels. Add barcodes or item codes in catalog first.',
          );
        }
        return;
      }
      allIds = printableIds;
      if (!multiBatch && allIds.length > _kMaxLabelsPerPdf) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              previewMode
                  ? 'Preview shows the first $_kMaxLabelsPerPdf of ${allIds.length} selected.'
                  : 'Processing first $_kMaxLabelsPerPdf of ${allIds.length} selected.',
            ),
          ),
        );
        allIds = allIds.sublist(0, _kMaxLabelsPerPdf);
      }

      final idBatches = multiBatch ? _chunkItemIds(allIds) : [allIds];
      var batchesDone = 0;

      for (var bi = 0; bi < idBatches.length; bi++) {
        if (_pdfCancelled) break;
        final targetIds = idBatches[bi];
        if (idBatches.length > 1 && mounted) {
          setState(() {
            _pdfStatus =
                'Batch ${bi + 1} of ${idBatches.length} (${targetIds.length} items)…';
          });
        }
        final ok = await _runOnePdfBatch(
          targetIds: targetIds,
          action: action,
          previewMode: previewMode,
          quietReadySnack: idBatches.length > 1,
        );
        if (!ok || _pdfCancelled) break;
        if (!previewMode) {
          _markIdsDownloaded(targetIds);
        }
        batchesDone++;
        if (multiBatch &&
            bi < idBatches.length - 1 &&
            mounted &&
            !_pdfCancelled) {
          if (kIsWeb) {
            final cont = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text('Batch ${bi + 1} of ${idBatches.length} ready'),
                content: Text(
                  '${targetIds.length} labels in this batch. '
                  'Continue to batch ${bi + 2}?',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Stop'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Next batch'),
                  ),
                ],
              ),
            );
            if (cont != true) break;
          } else {
            await Future<void>.delayed(const Duration(milliseconds: 400));
          }
        }
      }

      if (!mounted || _pdfCancelled || batchesDone == 0) return;
      if (multiBatch && idBatches.length > 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Finished $batchesDone of ${idBatches.length} batches. '
              'Use Select remaining for the next set.',
            ),
          ),
        );
      }
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

  /// Returns false if user cancelled or generation failed before [action].
  Future<bool> _runOnePdfBatch({
    required List<String> targetIds,
    required Future<void> Function(
      List<Uint8List> pdfs,
      List<String> batchItemIds,
    ) action,
    required bool previewMode,
    bool quietReadySnack = false,
  }) async {
    try {
      final batch = await _loadLabels(ids: targetIds);
      if (batch.labels.isEmpty) {
        if (!mounted) return false;
        _showError(
          batch.isTotalFailure
              ? (batch.failuresById.values.isNotEmpty
                  ? batch.failuresById.values.first
                  : 'Could not load labels. Sign in, check network, or pick items with barcodes.')
              : 'No printable labels in selection.',
        );
        return false;
      }
      if (batch.isTotalFailure) {
        if (!mounted) return false;
        final hint = batch.failuresById.values.isNotEmpty
            ? batch.failuresById.values.first
            : 'Check barcodes and try again.';
        _showError(
          '${batch.failedIds.length} items could not be loaded. $hint',
        );
        return false;
      }
      if (batch.hasPartialFailure) {
        final cont = await showPartialLabelFailureDialog(context, batch);
        if (cont != true) return false;
      }
      var denseA4 = _denseA4;
      if (!denseA4 && batch.labels.length > 25) {
        denseA4 = true;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Switched to A4 sheet — thermal roll is only for small batches.',
              ),
            ),
          );
        }
      }
      _pdfProgressDialogContext = null;
      if (!mounted) return false;
      unawaited(
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (dlgCtx) {
            _pdfProgressDialogContext = dlgCtx;
            return AlertDialog(
              content: Row(
                children: [
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(_pdfStatus ?? 'Generating PDF…'),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    _pdfCancelled = true;
                    Navigator.pop(dlgCtx);
                  },
                  child: const Text('Cancel'),
                ),
              ],
            );
          },
        ).whenComplete(() => _pdfProgressDialogContext = null),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (!mounted) return false;
      setState(() => _pdfStatus = 'Generating PDF…');
      final symbol = bulkPrintSymbolMode(denseA4: denseA4, useQr: _useQr);
      List<Uint8List>? pdfs;
      try {
        pdfs = await generateBulkPdfParts(
          context: context,
          ref: ref,
          batch: batch,
          denseA4: denseA4,
          copies: _copies,
          perRow: _perRow,
          symbol: symbol,
          thermalSize: _thermalSize,
          labelsPerFile: _labelsPerPdfFile.count,
        );
        if (_pdfCancelled) return false;
        await action(pdfs, targetIds);
      } finally {
        _dismissPdfProgressDialog();
      }
      if (!mounted || _pdfCancelled) return false;
      if (!previewMode && !quietReadySnack) {
        final perFile = _labelsPerPdfFile.count;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _denseA4
                  ? (pdfs.length == 1
                      ? 'One A4 PDF ready — up to $perFile labels per page. Print once and cut.'
                      : '${pdfs.length} A4 PDFs ready — tap each download button on web.')
                  : (pdfs.length == 1
                      ? 'PDF ready (up to $perFile labels per file).'
                      : '${pdfs.length} PDFs ready (up to $perFile labels each).'),
            ),
          ),
        );
      }
      return true;
    } on BarcodeOperationException catch (e) {
      if (!mounted) return false;
      _showError(e.message);
      return false;
    } catch (e, st) {
      logBarcodeOperationError(e, st);
      if (!mounted) return false;
      _showError(barcodeMessageForUser(e));
      return false;
    }
  }

  void _dismissPdfProgressDialog() {
    final dlg = _pdfProgressDialogContext;
    if (dlg != null && dlg.mounted) {
      Navigator.of(dlg).pop();
    }
    _pdfProgressDialogContext = null;
  }

  Future<bool> _sharePdfSafe(Uint8List bytes, String filename) async {
    try {
      await Printing.sharePdf(bytes: bytes, filename: filename);
      return true;
    } catch (e, st) {
      logBarcodeOperationError(e, st);
      if (!mounted) return false;
      _showError(
        kIsWeb
            ? 'Download blocked by browser. Allow downloads, or use Preview then Download PDF.'
            : barcodeMessageForUser(e),
      );
      return false;
    }
  }

  void _showError(String message) {
    final retry = _lastPdfRetry;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 6),
        backgroundColor: Colors.red.shade700,
        action: SnackBarAction(
          label: retry == null ? 'Dismiss' : 'Retry',
          textColor: Colors.white,
          onPressed: retry == null ? () {} : () => unawaited(retry()),
        ),
      ),
    );
  }

  String _bulkBarcodeFilename({int? part, int? partCount}) {
    final q = ref.read(stockListQueryProvider);
    final raw = q.category.trim().isNotEmpty ? q.category.trim() : 'all_items';
    final category = raw
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final date = DateFormat('yyyyMMdd').format(DateTime.now());
    final base =
        'harisree_barcodes_${category.isEmpty ? 'all_items' : category}_$date';
    if (part != null && partCount != null && partCount > 1) {
      return '${base}_part${part}_of_$partCount.pdf';
    }
    return '$base.pdf';
  }

  Future<void> _openPdfPage(
    Uint8List pdf, {
    required String title,
    String? filename,
  }) async {
    if (!mounted) return;
    final name = filename ?? _bulkBarcodeFilename();
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (ctx) => Scaffold(
          appBar: AppBar(
            title: Text(title),
            actions: [
              TextButton.icon(
                onPressed: () => unawaited(_sharePdfSafe(pdf, name)),
                icon: const Icon(Icons.download_rounded),
                label: const Text('Download PDF'),
              ),
            ],
          ),
          body: PdfPreview(
            build: (_) async => pdf,
            canChangeOrientation: false,
            canChangePageFormat: false,
            canDebug: false,
            actions: const [],
          ),
        ),
      ),
    );
  }

  /// Web: one preview or a sheet with explicit per-file download buttons.
  Future<void> _deliverPdfParts(
    List<Uint8List> pdfs, {
    required int labelCount,
    bool forPrint = false,
  }) async {
    if (!mounted || pdfs.isEmpty) return;
    final n = pdfs.length;
    final names = List.generate(
      n,
      (i) => _bulkBarcodeFilename(part: i + 1, partCount: n),
    );
    if (kIsWeb) {
      if (!forPrint && n == 1) {
        await _openPdfPage(
          pdfs.first,
          title: 'Labels ($labelCount)',
          filename: names.first,
        );
        return;
      }
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  forPrint ? '$n PDFs to print' : '$n PDF files ready',
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  forPrint
                      ? 'Download each file, then print from your browser.'
                      : 'Tap each button to download. Browsers block automatic multi-downloads.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 12),
                for (var i = 0; i < n; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: FilledButton.icon(
                      onPressed: () =>
                          unawaited(_sharePdfSafe(pdfs[i], names[i])),
                      icon: Icon(
                        forPrint
                            ? Icons.print_rounded
                            : Icons.download_rounded,
                      ),
                      label: Text(
                        forPrint
                            ? 'Download part ${i + 1} of $n to print'
                            : 'Download part ${i + 1} of $n',
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
      return;
    }
    for (var i = 0; i < n; i++) {
      if (forPrint) {
        await guardWebPrint(
          () => Printing.layoutPdf(
            name: names[i],
            onLayout: (_) async => pdfs[i],
          ),
        );
      } else {
        final ok = await _sharePdfSafe(pdfs[i], names[i]);
        if (!ok) return;
      }
      if (i < n - 1) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
  }

  Future<void> _preview() => _runPdfFlow(
        retry: _preview,
        previewMode: true,
        action: (pdfs, batchIds) async {
          if (!mounted || pdfs.isEmpty) return;
          final total = batchIds.length * _copies;
          await _openPdfPage(
            pdfs.first,
            title: pdfs.length == 1
                ? 'Preview ($total labels)'
                : 'Preview part 1 of ${pdfs.length}',
            filename: _bulkBarcodeFilename(part: 1, partCount: pdfs.length),
          );
        },
      );

  Future<void> _downloadPdf() => _runPdfFlow(
        retry: _downloadPdf,
        multiBatch: true,
        action: (pdfs, batchIds) async {
          if (!mounted) return;
          await _deliverPdfParts(pdfs, labelCount: batchIds.length);
        },
      );

  Future<void> _print() => _runPdfFlow(
        retry: _print,
        multiBatch: true,
        action: (pdfs, batchIds) async {
          if (!mounted) return;
          await _deliverPdfParts(
            pdfs,
            labelCount: batchIds.length,
            forPrint: true,
          );
        },
      );

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
    if (op.purchasedInPeriodOnly) {
      final p = double.tryParse('${it['period_purchased_qty']}') ?? 0;
      if (p <= 0) return false;
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

    final sessionHint = ref.watch(apiDegradedProvider);

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
          if (ref.watch(bulkBarcodeDownloadedIdsProvider).isNotEmpty)
            TextButton(
              onPressed: () {
                ref.read(bulkBarcodeDownloadedIdsProvider.notifier).state = {};
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Cleared printed marks for this session.'),
                    ),
                  );
                }
              },
              child: const Text('Reset printed'),
            ),
        ],
      ),
      bottomNavigationBar: BulkBarcodePrintToolbar(
        selectedCount: selected.length,
        busy: _busy,
        denseA4: _denseA4,
        useQr: _useQr,
        copies: _copies,
        labelsPerPdfFile: _labelsPerPdfFile,
        progress: progress,
        statusText: _pdfStatus,
        onDenseA4Changed: (v) => setState(() {
          _denseA4 = v;
          if (v && _labelsPerPdfFile == BulkLabelsPerPdfFile.n30) {
            _labelsPerPdfFile = BulkLabelsPerPdfFile.n50;
          }
        }),
        onQrChanged: (v) => setState(() => _useQr = v),
        onCopiesChanged: (v) => setState(() => _copies = v),
        onLabelsPerPdfFileChanged: (v) => setState(() => _labelsPerPdfFile = v),
        onPreview: _preview,
        onPdf: _downloadPdf,
        onPrint: _print,
        pdfButtonLabel: selected.length > _kMaxLabelsPerPdf
            ? (kIsWeb
                ? 'Download (${_pdfBatchCount(selected.length)} batches)'
                : 'PDF (${_pdfBatchCount(selected.length)} batches)')
            : (kIsWeb ? 'Download' : 'PDF'),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final desktop = constraints.maxWidth >= kOperationalDesktopBreakpoint;
          final listPane = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (listAsync.valueOrNull?['partial'] == true)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    HexaOp.pageGutter,
                    8,
                    HexaOp.pageGutter,
                    0,
                  ),
                  child: Material(
                    color: const Color(0xFFFFF8E1),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.wifi_off_rounded,
                            size: 20,
                            color: Color(0xFFF57F17),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Connection dropped while loading items. '
                              'Showing ${listAsync.valueOrNull?['loaded'] ?? 0} loaded — retry when online.',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () =>
                                ref.invalidate(bulkStockListProvider),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (sessionHint != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    HexaOp.pageGutter,
                    8,
                    HexaOp.pageGutter,
                    0,
                  ),
                  child: Material(
                    color: const Color(0xFFFFEBEE),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            size: 20,
                            color: Color(0xFFC62828),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              sessionHint,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (!_denseA4)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    HexaOp.pageGutter,
                    6,
                    HexaOp.pageGutter,
                    0,
                  ),
                  child: Text(
                    'Tip: choose A4 + 50/pg for one sheet with many labels to cut.',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
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
    final downloaded = ref.watch(bulkBarcodeDownloadedIdsProvider);
    final remainingCount = visible.where((e) {
      final id = e['id']?.toString() ?? '';
      return id.isNotEmpty && !downloaded.contains(id);
    }).length;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: HexaOp.pageGutter),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${visible.length} shown · $loaded loaded'
                  '${total != null ? ' · $total total' : ''}'
                  '${downloaded.isNotEmpty ? ' · $remainingCount left' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                ),
              ),
              if (remainingCount > 0 &&
                  remainingCount < visible.length &&
                  downloaded.isNotEmpty)
                TextButton(
                  onPressed: () {
                    final ids = <String>{
                      for (final e in visible)
                        if (e['id'] != null &&
                            !downloaded.contains(e['id'].toString()))
                          e['id'].toString(),
                    };
                    _setSelected(ids);
                    if (ids.length > _kMaxLabelsPerPdf && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Selected $remainingCount remaining. '
                            'Download runs in batches of $_kMaxLabelsPerPdf.',
                          ),
                        ),
                      );
                    }
                  },
                  child: Text('Remaining ($remainingCount)'),
                ),
              TextButton(
                onPressed: visible.isEmpty
                    ? null
                    : () {
                        final ids = <String>{
                          for (final e in visible)
                            if (e['id'] != null) e['id'].toString(),
                        };
                        _setSelected(ids);
                        if (ids.length > _kMaxLabelsPerPdf && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Selected ${ids.length} items. '
                                'Download runs in batches of $_kMaxLabelsPerPdf.',
                              ),
                            ),
                          );
                        }
                      },
                child: Text('Select all (${visible.length})'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(HexaOp.pageGutter, 0, HexaOp.pageGutter, 2),
          child: Container(
            decoration: const BoxDecoration(
              color: StockTableLayout.headerFill,
              border: Border(
                left: StockTableLayout.cellBorder,
                right: StockTableLayout.cellBorder,
                top: StockTableLayout.cellBorder,
              ),
            ),
            child: Row(
              children: [
                const SizedBox(width: 44),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
                    child: Text(
                      'Item',
                      style: HexaDsType.label(10, color: HexaDsColors.textMuted),
                    ),
                  ),
                ),
                SizedBox(
                  width: StockTableLayout.metricWidth + 8,
                  child: Text(
                    'Ordered',
                    textAlign: TextAlign.center,
                    style: HexaDsType.label(10, color: HexaDsColors.textMuted),
                  ),
                ),
                SizedBox(
                  width: StockTableLayout.metricWidth + 8,
                  child: Text(
                    'Stock',
                    textAlign: TextAlign.center,
                    style: HexaDsType.label(10, color: HexaDsColors.textMuted),
                  ),
                ),
                const SizedBox(width: 40),
              ],
            ),
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
              final cur = coerceToDouble(it['current_stock']);
              final purchased = coerceToDouble(
                it['period_purchased_qty'] ?? it['purchased_today_qty'],
              );
              final unit =
                  it['stock_unit']?.toString() ?? it['unit']?.toString() ?? 'piece';
              final hasPending = it['has_pending_order'] == true;
              final pendingDays = (it['pending_order_days'] as num?)?.toInt();
              final sub = barcode.isEmpty
                  ? (code.isEmpty ? 'No barcode · $st' : '$code · $st')
                  : (code.isEmpty ? '$barcode · $st' : '$code · $barcode · $st');
              return _BulkPrintRow(
                selected: selected.contains(id),
                isFirstRow: i == 0,
                name: name,
                subtitle: sub,
                purchased: purchased,
                current: cur,
                unit: unit,
                stockStatus: st,
                hasPendingOrder: hasPending,
                pendingOrderDays: pendingDays,
                onChanged: (v) => _toggleSelected(id, v),
                onPreview: id.isEmpty
                    ? null
                    : () {
                        ref.read(bulkPreviewItemIdProvider.notifier).state = id;
                        if (!desktop) {
                          showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            showDragHandle: true,
                            builder: (sheetCtx) => Padding(
                              padding: EdgeInsets.only(
                                bottom: MediaQuery.viewInsetsOf(sheetCtx).bottom,
                              ),
                              child: SingleChildScrollView(
                                child: SizedBox(
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
    required this.isFirstRow,
    required this.name,
    required this.subtitle,
    required this.purchased,
    required this.current,
    required this.unit,
    required this.stockStatus,
    required this.hasPendingOrder,
    this.pendingOrderDays,
    required this.onChanged,
    this.onPreview,
  });

  final bool selected;
  final bool isFirstRow;
  final String name;
  final String subtitle;
  final double purchased;
  final double current;
  final String unit;
  final String stockStatus;
  final bool hasPendingOrder;
  final int? pendingOrderDays;
  final ValueChanged<bool> onChanged;
  final VoidCallback? onPreview;

  @override
  Widget build(BuildContext context) {
    final displayStatus = stockDisplayStatusFromApi(stockStatus);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: HexaOp.pageGutter),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onChanged(!selected),
          child: Container(
            constraints: const BoxConstraints(
              minHeight: StockTableLayout.rowMinHeight,
            ),
            decoration: StockTableLayout.rowDecoration(isFirst: isFirstRow),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 44,
                    alignment: Alignment.center,
                    decoration: StockTableLayout.cellDecoration(),
                    child: Checkbox(
                      value: selected,
                      onChanged: (v) => onChanged(v ?? false),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(6, 6, 4, 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    width: StockTableLayout.metricWidth + 8,
                    alignment: Alignment.center,
                    decoration: StockTableLayout.cellDecoration(),
                    child: StockNumberDisplay(
                      qty: purchased,
                      unit: unit,
                      status: StockDisplayStatus.normal,
                      hasPendingOrder: hasPendingOrder,
                      pendingDays: pendingOrderDays,
                      fontSize: 14,
                    ),
                  ),
                  Container(
                    width: StockTableLayout.metricWidth + 8,
                    alignment: Alignment.center,
                    decoration: StockTableLayout.cellDecoration(),
                    child: StockNumberDisplay(
                      qty: current,
                      unit: unit,
                      status: displayStatus,
                      fontSize: 14,
                    ),
                  ),
                  SizedBox(
                    width: 40,
                    child: onPreview != null
                        ? IconButton(
                            tooltip: 'Preview label',
                            icon: const Icon(Icons.visibility_outlined, size: 20),
                            onPressed: onPreview,
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
