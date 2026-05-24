import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:printing/printing.dart';

import '../auth/auth_error_messages.dart';

enum BarcodeOperationKind {
  pdfGeneration,
  barcodeRender,
  printUnavailable,
  batchPartial,
  cameraPermission,
  photoUnreadable,
  network,
  emptySelection,
  unknown,
}

enum BarcodeOperationContext { bulkPrint, singlePrint, scanner, preview }

class BarcodeOperationException implements Exception {
  BarcodeOperationException(
    this.message, {
    this.kind = BarcodeOperationKind.unknown,
    this.cause,
    this.failedItemIds = const [],
  });

  final String message;
  final BarcodeOperationKind kind;
  final Object? cause;
  final List<String> failedItemIds;

  @override
  String toString() => message;
}

/// User-safe message for barcode/PDF/print/scanner flows (no generic "Something went wrong").
String barcodeMessageForUser(
  Object error, {
  BarcodeOperationContext ctx = BarcodeOperationContext.bulkPrint,
}) {
  if (error is BarcodeOperationException) return error.message;
  if (error is DioException) return friendlyApiError(error);
  final s = error.toString().toLowerCase();
  if (s.contains('printing') || s.contains('print')) {
    return 'Print is not available on this device. Download the PDF instead.';
  }
  if (s.contains('barcode') && (s.contains('empty') || s.contains('invalid'))) {
    return 'Barcode image could not be generated. Check item codes and barcodes.';
  }
  if (s.contains('pdf') || s.contains('document')) {
    return 'PDF generation failed. Try fewer items or switch label format.';
  }
  if (error is StateError || error is ArgumentError) {
    return error.toString().replaceFirst(RegExp(r'^[^:]*:\s*'), '');
  }
  switch (ctx) {
    case BarcodeOperationContext.scanner:
      return 'Scan could not complete. Try again or enter the code manually.';
    case BarcodeOperationContext.singlePrint:
      return 'Could not prepare this label. Check barcode and item code.';
    case BarcodeOperationContext.preview:
    case BarcodeOperationContext.bulkPrint:
      if (s.contains('infinity') ||
          s.contains('nan') ||
          s.contains('unsupported operation')) {
        return 'Some label numbers were invalid. Try A4 + Code128, or fewer items per batch.';
      }
      if (s.contains('too big') ||
          s.contains('memory') ||
          s.contains('overflow') ||
          s.contains('widget')) {
        return 'PDF too large for browser. Use A4 + Code128 and try 50 items.';
      }
      return 'Could not prepare labels. Use A4 + Code128, or fewer items per batch.';
  }
}

void logBarcodeOperationError(Object error, [StackTrace? stack]) {
  if (!kDebugMode) return;
  debugPrint('[BarcodeOp] $error');
  if (stack != null) debugPrint('$stack');
}

Future<void> guardWebPrint(Future<void> Function() printAction) async {
  final info = await Printing.info();
  if (!info.canPrint) {
    throw BarcodeOperationException(
      'Print is not available in this browser. Use PDF to download or share.',
      kind: BarcodeOperationKind.printUnavailable,
    );
  }
  await printAction();
}
