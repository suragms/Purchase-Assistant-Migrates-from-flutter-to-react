import 'dart:isolate';
import 'dart:math' as math;

import 'package:barcode/barcode.dart';
import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

enum LabelSize { small, medium, large }

class BarcodeLabelData {
  const BarcodeLabelData({
    required this.itemCode,
    required this.itemName,
    this.unit,
    this.currentStock,
    this.lastPurchaseDate,
    this.lastPurchaseQty,
    this.lastPurchaseUnit,
    this.lastPurchaseRate,
  });

  final String itemCode;
  final String itemName;
  final String? unit;
  final double? currentStock;
  final DateTime? lastPurchaseDate;
  final double? lastPurchaseQty;
  final String? lastPurchaseUnit;
  final double? lastPurchaseRate;

  Map<String, dynamic> toJson() => {
        'itemCode': itemCode,
        'itemName': itemName,
        'unit': unit,
        'currentStock': currentStock,
        'lastPurchaseDate': lastPurchaseDate?.toUtc().toIso8601String(),
        'lastPurchaseQty': lastPurchaseQty,
        'lastPurchaseUnit': lastPurchaseUnit,
        'lastPurchaseRate': lastPurchaseRate,
      };

  factory BarcodeLabelData.fromJson(Map<String, dynamic> j) {
    DateTime? lpDate;
    final lpRaw = j['lastPurchaseDate'];
    if (lpRaw is String && lpRaw.isNotEmpty) {
      lpDate = DateTime.tryParse(lpRaw);
    }
    return BarcodeLabelData(
      itemCode: j['itemCode'] as String? ?? '',
      itemName: j['itemName'] as String? ?? '',
      unit: j['unit'] as String?,
      currentStock: (j['currentStock'] as num?)?.toDouble(),
      lastPurchaseDate: lpDate,
      lastPurchaseQty: (j['lastPurchaseQty'] as num?)?.toDouble(),
      lastPurchaseUnit: j['lastPurchaseUnit'] as String?,
      lastPurchaseRate: (j['lastPurchaseRate'] as num?)?.toDouble(),
    );
  }

  static BarcodeLabelData? fromApiMap(Map<String, dynamic> j) {
    final code = j['item_code']?.toString() ?? '';
    if (code.isEmpty) return null;
    DateTime? lpDate;
    final lpRaw = j['last_purchase_date'];
    if (lpRaw is String && lpRaw.isNotEmpty) {
      lpDate = DateTime.tryParse(lpRaw);
    }
    return BarcodeLabelData(
      itemCode: code,
      itemName: j['item_name']?.toString() ?? code,
      unit: j['unit']?.toString(),
      currentStock: (j['current_stock'] as num?)?.toDouble(),
      lastPurchaseDate: lpDate,
      lastPurchaseQty: (j['last_purchase_qty'] as num?)?.toDouble(),
      lastPurchaseUnit: j['last_purchase_unit']?.toString(),
      lastPurchaseRate: (j['last_purchase_rate'] as num?)?.toDouble(),
    );
  }
}

class BarcodePdfService {
  static Future<Uint8List> generateSingleLabel({
    required BarcodeLabelData data,
    LabelSize size = LabelSize.medium,
    int copies = 1,
    bool showLastPurchase = true,
  }) async {
    final doc = pw.Document();
    final fmt = _pageFormat(size);
    for (var c = 0; c < copies; c++) {
      doc.addPage(
        pw.Page(
          pageFormat: fmt,
          build: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: _labelBody(
              data: data,
              size: size,
              showLastPurchase: showLastPurchase,
            ),
          ),
        ),
      );
    }
    return doc.save();
  }

  static Future<Uint8List> generateBatch({
    required List<BarcodeLabelData> items,
    LabelSize size = LabelSize.medium,
    int copiesPerItem = 1,
    bool showLastPurchase = true,
    int labelsPerRow = 1,
  }) async {
    final expanded = <BarcodeLabelData>[];
    for (final data in items) {
      for (var c = 0; c < copiesPerItem; c++) {
        expanded.add(data);
      }
    }
    if (expanded.isEmpty) {
      return pw.Document().save();
    }

    final perRow = labelsPerRow.clamp(1, 3);
    final doc = pw.Document();

    if (perRow <= 1) {
      final fmt = _pageFormat(size);
      for (final data in expanded) {
        doc.addPage(
          pw.Page(
            pageFormat: fmt,
            build: (ctx) => pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: _labelBody(
                data: data,
                size: size,
                showLastPurchase: showLastPurchase,
              ),
            ),
          ),
        );
      }
      return doc.save();
    }

    final labelFmt = _pageFormat(size);
    const sheet = PdfPageFormat.a4;
    for (var i = 0; i < expanded.length; i += perRow) {
      final row = expanded.skip(i).take(perRow).toList();
      doc.addPage(
        pw.Page(
          pageFormat: sheet,
          margin: const pw.EdgeInsets.all(10),
          build: (ctx) => pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              for (final d in row)
                pw.Expanded(
                  child: pw.Container(
                    height: labelFmt.height + 8,
                    margin: const pw.EdgeInsets.symmetric(horizontal: 3),
                    padding: const pw.EdgeInsets.all(4),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(
                        color: PdfColors.grey400,
                        width: 0.4,
                      ),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                      children: _labelBody(
                        data: d,
                        size: size,
                        showLastPurchase: showLastPurchase,
                      ),
                    ),
                  ),
                ),
              for (var pad = row.length; pad < perRow; pad++)
                pw.Expanded(child: pw.SizedBox()),
            ],
          ),
        ),
      );
    }
    return doc.save();
  }

  /// Maximizes labels per A4 page: 5mm margins, 2mm gaps; cell size 30×10 (S),
  /// 50×25 (M), 80×40 (L). Runs off the UI thread on VM via [Isolate.run].
  static Future<Uint8List> generateBatchA4Dense({
    required List<BarcodeLabelData> items,
    LabelSize size = LabelSize.medium,
    int copiesPerItem = 1,
    bool showLastPurchase = true,
  }) async {
    final expanded = <BarcodeLabelData>[];
    for (final data in items) {
      for (var c = 0; c < copiesPerItem; c++) {
        expanded.add(data);
      }
    }
    if (expanded.isEmpty) {
      return pw.Document().save();
    }
    final payload = <String, dynamic>{
      'labels': [for (final e in expanded) e.toJson()],
      'size': size.index,
      'showLastPurchase': showLastPurchase,
    };
    if (kIsWeb) {
      return _barcodeA4DenseFromPayload(payload);
    }
    return Isolate.run(() => _barcodeA4DenseFromPayload(payload));
  }

  static (double wMm, double hMm) a4DenseCellMm(LabelSize size) => switch (size) {
        LabelSize.small => (30.0, 10.0),
        LabelSize.medium => (50.0, 25.0),
        LabelSize.large => (80.0, 40.0),
      };

  /// PDF builder for [Isolate.run] / web (uses async [pw.Document.save]).
  static Future<Uint8List> buildA4DenseGridPdf(Map<String, dynamic> payload) async {
    final rawList = payload['labels'] as List<dynamic>;
    final labels = <BarcodeLabelData>[
      for (final e in rawList)
        BarcodeLabelData.fromJson(Map<String, dynamic>.from(e as Map)),
    ];
    final sizeIdx = (payload['size'] as int?) ?? 1;
    final size = LabelSize.values[sizeIdx.clamp(0, LabelSize.values.length - 1)];
    final showLastPurchase = payload['showLastPurchase'] as bool? ?? true;

    final mm = PdfPageFormat.mm;
    const margin = 5.0 * PdfPageFormat.mm;
    const gap = 2.0 * PdfPageFormat.mm;
    final (lwMm, lhMm) = a4DenseCellMm(size);
    final labelW = lwMm * mm;
    final labelH = lhMm * mm;
    const sheet = PdfPageFormat.a4;
    final innerW = sheet.width - 2 * margin;
    final innerH = sheet.height - 2 * margin;
    final cols = math.max(1, ((innerW + gap) / (labelW + gap)).floor());
    final rows = math.max(1, ((innerH + gap) / (labelH + gap)).floor());
    final perPage = cols * rows;

    final doc = pw.Document();
    for (var base = 0; base < labels.length; base += perPage) {
      final chunk = labels.sublist(base, math.min(base + perPage, labels.length));
      doc.addPage(
        pw.Page(
          pageFormat: sheet,
          margin: const pw.EdgeInsets.all(margin),
          build: (ctx) {
            final pageRows = <pw.Widget>[];
            for (var r = 0; r < rows; r++) {
              final rowCells = <pw.Widget>[];
              for (var c = 0; c < cols; c++) {
                final idx = r * cols + c;
                final right = c < cols - 1 ? gap : 0.0;
                final bottom = r < rows - 1 ? gap : 0.0;
                if (idx < chunk.length) {
                  rowCells.add(
                    pw.Padding(
                      padding: pw.EdgeInsets.only(right: right, bottom: bottom),
                      child: pw.Container(
                        width: labelW,
                        height: labelH,
                        padding: const pw.EdgeInsets.all(0.5),
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(
                            color: PdfColors.grey400,
                            width: 0.25,
                          ),
                        ),
                        child: pw.FittedBox(
                          fit: pw.BoxFit.scaleDown,
                          alignment: pw.Alignment.topCenter,
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                            mainAxisSize: pw.MainAxisSize.min,
                            children: _labelBody(
                              data: chunk[idx],
                              size: size,
                              showLastPurchase: showLastPurchase,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                } else {
                  rowCells.add(
                    pw.Padding(
                      padding: pw.EdgeInsets.only(right: right, bottom: bottom),
                      child: pw.SizedBox(width: labelW, height: labelH),
                    ),
                  );
                }
              }
              pageRows.add(
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: rowCells,
                ),
              );
            }
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: pageRows,
            );
          },
        ),
      );
    }
    return doc.save();
  }

  static PdfPageFormat _pageFormat(LabelSize size) => switch (size) {
        LabelSize.small =>
          const PdfPageFormat(30 * PdfPageFormat.mm, 10 * PdfPageFormat.mm),
        LabelSize.large =>
          const PdfPageFormat(100 * PdfPageFormat.mm, 50 * PdfPageFormat.mm),
        LabelSize.medium =>
          const PdfPageFormat(57 * PdfPageFormat.mm, 32 * PdfPageFormat.mm),
      };

  static (double titleSize, double codeSize, double bcHeight, double qrSize)
      _sizes(LabelSize size) => switch (size) {
            LabelSize.small => (5.0, 4.0, 12.0, 0.0),
            LabelSize.large => (10.0, 8.0, 40.0, 36.0),
            LabelSize.medium => (8.0, 7.0, 36.0, 28.0),
          };

  static List<pw.Widget> _labelBody({
    required BarcodeLabelData data,
    required LabelSize size,
    required bool showLastPurchase,
  }) {
    final code = data.itemCode.trim().isEmpty ? data.itemName : data.itemCode;
    final bc = Barcode.code128();
    final (titleSize, codeSize, bcHeight, qrSize) = _sizes(size);

    final children = <pw.Widget>[
      pw.Text(
        data.itemName,
        maxLines: 2,
        style: pw.TextStyle(fontSize: titleSize, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 3),
      pw.BarcodeWidget(
        barcode: bc,
        data: code,
        drawText: false,
        height: bcHeight,
      ),
      pw.Text(code, style: pw.TextStyle(fontSize: codeSize)),
    ];

    if (qrSize > 0) {
      children.addAll([
        pw.SizedBox(height: 3),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.BarcodeWidget(
              barcode: Barcode.qrCode(),
              data: code,
              width: qrSize,
              height: qrSize,
            ),
            if (data.currentStock != null && size == LabelSize.large)
              pw.Text(
                'Stock: ${data.currentStock!.toStringAsFixed(0)} ${data.unit ?? ''}',
                style: pw.TextStyle(fontSize: codeSize - 1),
              ),
          ],
        ),
      ]);
    }

    final lastLine = _lastPurchaseLine(data, showLastPurchase: showLastPurchase, size: size);
    if (lastLine != null) {
      children.add(pw.SizedBox(height: 2));
      children.add(
        pw.Text(lastLine, style: pw.TextStyle(fontSize: codeSize - 1)),
      );
    }

    final bags = _bagsLine(data);
    if (bags != null && size != LabelSize.small) {
      children.add(
        pw.Text(bags, style: pw.TextStyle(fontSize: codeSize - 1.5)),
      );
    }

    return children;
  }

  static String? _lastPurchaseLine(
    BarcodeLabelData data, {
    required bool showLastPurchase,
    required LabelSize size,
  }) {
    if (!showLastPurchase || size == LabelSize.small) return null;
    if (data.lastPurchaseDate == null) return 'No purchase yet';
    final d = data.lastPurchaseDate!;
    final ds =
        '${d.day.toString().padLeft(2, '0')} ${_month(d.month)} ${d.year % 100}';
    final qty = data.lastPurchaseQty;
    final qtyStr = qty == null
        ? ''
        : (qty == qty.roundToDouble() ? '${qty.round()}' : qty.toStringAsFixed(1));
    final u = data.lastPurchaseUnit ?? data.unit ?? '';
    final rate = data.lastPurchaseRate != null
        ? '₹${data.lastPurchaseRate!.toStringAsFixed(0)}'
        : '';
    return 'Last: $ds  $qtyStr $u  $rate'.trim();
  }

  static String? _bagsLine(BarcodeLabelData data) {
    final qty = data.lastPurchaseQty;
    if (qty == null || qty <= 0) return null;
    final u = (data.lastPurchaseUnit ?? data.unit ?? '').toLowerCase();
    if (u.contains('bag') || u == 'sack') {
      final n = qty == qty.roundToDouble() ? '${qty.round()}' : qty.toStringAsFixed(1);
      return 'Bags: $n';
    }
    return null;
  }

  static String _month(int m) {
    const names = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return names[m - 1];
  }
}

/// Top-level for [Isolate.run] (must be a library function).
Future<Uint8List> _barcodeA4DenseFromPayload(Map<String, dynamic> payload) {
  return BarcodePdfService.buildA4DenseGridPdf(payload);
}
