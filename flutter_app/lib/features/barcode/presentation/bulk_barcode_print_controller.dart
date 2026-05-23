import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/errors/barcode_operation_errors.dart';
import '../../../core/router/post_auth_route.dart';
import '../services/barcode_pdf_service.dart';
import '../services/bulk_label_batch.dart';
import '../services/bulk_label_from_stock.dart';
import '../services/bulk_pdf_chunks.dart';

/// Resolves symbology for dense A4 cells (no Code128+QR combo — overflows small cells).
BarcodeSymbolMode bulkPrintSymbolMode({
  required bool denseA4,
  required bool useQr,
}) {
  if (useQr) return BarcodeSymbolMode.qrCode;
  return BarcodeSymbolMode.code128;
}

Future<BulkLabelBatchResult> fetchBulkLabels({
  required WidgetRef ref,
  required List<String> ids,
  Map<String, Map<String, dynamic>>? stockById,
  void Function(int done, int total)? onProgress,
}) async {
  final session = ref.read(sessionProvider);
  if (session == null) {
    throw BarcodeOperationException(
      'Sign in to print labels.',
      kind: BarcodeOperationKind.network,
    );
  }
  if (ids.isEmpty) {
    return const BulkLabelBatchResult(labels: []);
  }

  final stock = stockById ?? const <String, Map<String, dynamic>>{};
  const chunkSize = 50;
  final api = ref.read(hexaApiProvider);
  final labels = <BarcodeLabelData>[];
  final failedIds = <String>[];
  final failuresById = <String, String>{};
  final labeledIds = <String>{};

  bool tryStockFallback(String rawId) {
    final nid = normalizeItemId(rawId);
    if (labeledIds.contains(nid)) {
      failedIds.remove(rawId);
      failuresById.remove(rawId);
      return true;
    }
    final built = labelDataFromStockRow(stock[nid]);
    if (built == null) return false;
    labels.add(built);
    labeledIds.add(nid);
    failedIds.remove(rawId);
    failuresById.remove(rawId);
    return true;
  }

  for (var i = 0; i < ids.length; i += chunkSize) {
    final end = (i + chunkSize < ids.length) ? i + chunkSize : ids.length;
    final chunk = ids.sublist(i, end);
    onProgress?.call(end, ids.length);

    try {
      final rows = await api.barcodeLabelBatch(
        businessId: session.primaryBusiness.id,
        itemIds: chunk,
      );
      final returned = <String>{};
      for (final j in rows) {
        final id = j['id']?.toString() ?? j['item_id']?.toString() ?? '';
        final label = BarcodeLabelData.fromApiMap(j);
        if (label != null) {
          labels.add(label);
          if (id.isNotEmpty) {
            final nid = normalizeItemId(id);
            returned.add(nid);
            labeledIds.add(nid);
          }
        } else if (id.isNotEmpty) {
          failedIds.add(id);
          failuresById[id] = 'Missing barcode and item code';
        }
      }
      for (final rawId in chunk) {
        final nid = normalizeItemId(rawId);
        if (returned.contains(nid)) continue;
        if (failedIds.contains(rawId)) {
          tryStockFallback(rawId);
          continue;
        }
        failedIds.add(rawId);
        failuresById[rawId] = 'No label data returned';
        tryStockFallback(rawId);
      }
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401 || status == 403) {
        throw BarcodeOperationException(
          friendlyApiError(e),
          kind: BarcodeOperationKind.network,
        );
      }
      final offline = e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.unknown;
      if (offline && stock.isNotEmpty) {
        for (final rawId in chunk) {
          if (tryStockFallback(rawId)) {
            failuresById.remove(rawId);
          } else {
            failedIds.add(rawId);
            failuresById[rawId] =
                'Offline — item needs a barcode or code on the list.';
          }
        }
        continue;
      }
      if (offline) {
        throw BarcodeOperationException(
          'No internet connection. Check your network and try again.',
          kind: BarcodeOperationKind.network,
        );
      }
      for (final rawId in chunk) {
        failedIds.add(rawId);
        failuresById[rawId] = friendlyApiError(e);
        tryStockFallback(rawId);
      }
    } catch (e) {
      if (e is BarcodeOperationException) rethrow;
      for (final rawId in chunk) {
        failedIds.add(rawId);
        failuresById[rawId] = barcodeMessageForUser(e);
        tryStockFallback(rawId);
      }
    }
  }

  return BulkLabelBatchResult(
    labels: labels,
    failedIds: failedIds,
    failuresById: failuresById,
  );
}

Future<Uint8List> _generatePdfForLabelChunk({
  required BuildContext context,
  required WidgetRef ref,
  required List<BarcodeLabelData> labels,
  required bool denseA4,
  required int perRow,
  required BarcodeSymbolMode symbol,
  required LabelSize thermalSize,
  required bool hideFinancials,
  int? targetLabelsPerPage,
}) async {
  if (denseA4) {
    return await BarcodePdfService.generateBatchA4Dense(
      items: labels,
      size: thermalSize,
      copiesPerItem: 1,
      hideFinancials: hideFinancials,
      columns: MediaQuery.sizeOf(context).width >= 600 ? 5 : 4,
      targetLabelsPerPage: targetLabelsPerPage,
      symbol: symbol,
    );
  }
  return await BarcodePdfService.generateBatch(
    items: labels,
    size: thermalSize,
    copiesPerItem: 1,
    labelsPerRow: perRow,
    hideFinancials: hideFinancials,
    symbol: symbol,
  );
}

Future<Uint8List> generateBulkPdfBytes({
  required BuildContext context,
  required WidgetRef ref,
  required BulkLabelBatchResult batch,
  required bool denseA4,
  required int copies,
  required int perRow,
  required BarcodeSymbolMode symbol,
  required LabelSize thermalSize,
  required int labelsPerFile,
}) async {
  final parts = await generateBulkPdfParts(
    context: context,
    ref: ref,
    batch: batch,
    denseA4: denseA4,
    copies: copies,
    perRow: perRow,
    symbol: symbol,
    thermalSize: thermalSize,
    labelsPerFile: labelsPerFile,
  );
  if (parts.isEmpty) {
    throw BarcodeOperationException(
      'No printable labels in selection.',
      kind: BarcodeOperationKind.emptySelection,
    );
  }
  return parts.first;
}

/// A4: one PDF, many labels per page. Thermal: optional split by [labelsPerFile].
Future<List<Uint8List>> generateBulkPdfParts({
  required BuildContext context,
  required WidgetRef ref,
  required BulkLabelBatchResult batch,
  required bool denseA4,
  required int copies,
  required int perRow,
  required BarcodeSymbolMode symbol,
  required LabelSize thermalSize,
  required int labelsPerFile,
}) async {
  if (batch.labels.isEmpty) {
    throw BarcodeOperationException(
      batch.failedIds.isEmpty
          ? 'No items selected.'
          : 'No printable labels — assign barcodes or item codes first.',
      kind: BarcodeOperationKind.emptySelection,
    );
  }
  final session = ref.read(sessionProvider);
  final hideFinancials =
      session != null && !sessionCanSeeFinancials(session);
  final perFile = labelsPerFile.clamp(1, 100);
  final copyN = copies.clamp(1, 5);

  try {
    if (denseA4) {
      final expanded = <BarcodeLabelData>[];
      for (final data in batch.labels) {
        for (var c = 0; c < copyN; c++) {
          expanded.add(data);
        }
      }
      final pdf = await _generatePdfForLabelChunk(
        context: context,
        ref: ref,
        labels: expanded,
        denseA4: true,
        perRow: perRow,
        symbol: symbol,
        thermalSize: thermalSize,
        hideFinancials: hideFinancials,
        targetLabelsPerPage: perFile,
      );
      return [pdf];
    }

    final chunks = chunkExpandedLabelsForPdfFiles(
      items: batch.labels,
      copiesPerItem: copyN,
      perFile: perFile,
    );
    final out = <Uint8List>[];
    for (final chunk in chunks) {
      out.add(
        await _generatePdfForLabelChunk(
          context: context,
          ref: ref,
          labels: chunk,
          denseA4: false,
          perRow: perRow,
          symbol: symbol,
          thermalSize: thermalSize,
          hideFinancials: hideFinancials,
        ),
      );
    }
    return out;
  } catch (e, st) {
    logBarcodeOperationError(e, st);
    if (e is BarcodeOperationException) rethrow;
    throw BarcodeOperationException(
      barcodeMessageForUser(e, ctx: BarcodeOperationContext.bulkPrint),
      kind: BarcodeOperationKind.pdfGeneration,
      cause: e,
    );
  }
}

Future<bool?> showPartialLabelFailureDialog(
  BuildContext context,
  BulkLabelBatchResult batch,
) {
  if (!batch.hasPartialFailure) return Future.value(true);
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Some labels failed'),
      content: Text(
        '${batch.failedIds.length} labels failed.\n'
        '${batch.labels.length} labels generated successfully.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Continue'),
        ),
      ],
    ),
  );
}
