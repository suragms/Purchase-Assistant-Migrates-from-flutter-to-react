import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../json_coerce.dart';
import '../models/business_profile.dart';
import '../models/trade_purchase_models.dart';
import '../reporting/trade_report_aggregate.dart';
import 'pdf_text_safe.dart';

final _money = NumberFormat('#,##,##0', 'en_IN');
final _df = DateFormat('dd MMM yyyy');
final _genDf = DateFormat('dd MMM yyyy, h:mm a');

String _rs(num n) => 'Rs. ${_money.format(n)}';

Future<pw.ImageProvider?> _tryLogo(String? url) async {
  final u = url?.trim();
  if (u == null || u.isEmpty) return null;
  try {
    final r = await Dio().get<List<int>>(
      u,
      options: Options(
        responseType: ResponseType.bytes,
        receiveTimeout: const Duration(seconds: 8),
      ),
    );
    final data = r.data;
    if (data == null || data.isEmpty) return null;
    return pw.MemoryImage(Uint8List.fromList(data));
  } catch (_) {
    return null;
  }
}

String _businessTitle(BusinessProfile business) => safePdfText(
      business.displayTitle.trim().isNotEmpty
          ? business.displayTitle
          : (business.legalName.trim().isNotEmpty
              ? business.legalName
              : 'NEW HARISREE AGENCY'),
    );

Future<pw.Widget> _businessPdfHeader(
  BusinessProfile business, {
  String? headline,
  String? subline,
}) async {
  final logo = await _tryLogo(business.logoUrl);
  final title = _businessTitle(business);
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      if (logo != null) ...[
        pw.Image(logo, width: 48, height: 48),
        pw.SizedBox(width: 10),
      ],
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              title.toUpperCase(),
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            if (headline != null && headline.isNotEmpty)
              pw.Text(
                safePdfText(headline),
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            if (subline != null && subline.isNotEmpty)
              pw.Text(
                safePdfText(subline),
                style: const pw.TextStyle(fontSize: 9, color: _muted),
              ),
            pw.SizedBox(height: 2),
            pw.Text(
              'Generated on: ${_genDf.format(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 7.5, color: _muted),
            ),
          ],
        ),
      ),
    ],
  );
}

const _border = PdfColor.fromInt(0xFFD1D5DB);
const _muted = PdfColor.fromInt(0xFF475569);
const _headerBg = PdfColor.fromInt(0xFFF1F5F9);

pw.Widget _hdr(String t) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 0),
      child: pw.Text(t,
          style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.black)),
    );

pw.Widget _kv(String k, String v, {bool bold = false}) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(k, style: const pw.TextStyle(fontSize: 9, color: _muted)),
          pw.Text(v,
              style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight:
                      bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
        ],
      ),
    );

pw.Widget _divider() => pw.Container(
      height: 0.5,
      margin: const pw.EdgeInsets.symmetric(vertical: 4),
      decoration: const pw.BoxDecoration(color: _border),
    );

pw.Widget _totCell(String label, String value, {bool bold = false}) =>
    pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(
            label,
            style: const pw.TextStyle(fontSize: 7.5, color: _muted),
          ),
          pw.Text(
            value,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              fontSize: bold ? 10 : 9,
              fontWeight:
                  bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        ],
      ),
    );

pw.Widget _tableSection({
  required List<String> headers,
  required List<List<String>> rows,
  List<pw.FlexColumnWidth>? widths,
}) {
  final cols = headers.length;
  final cw = widths ??
      List.generate(cols, (i) => pw.FlexColumnWidth(i == 0 ? 3 : 1));
  pw.Widget cell(String t,
          {bool bold = false, bool right = false, PdfColor? color}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: pw.Text(
          t,
          textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
          style: pw.TextStyle(
              fontSize: 8.5,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: color ?? PdfColors.black),
        ),
      );
  return pw.Table(
    border: pw.TableBorder.all(color: _border, width: 0.5),
    columnWidths: {for (var i = 0; i < cols; i++) i: cw[i]},
    children: [
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: _headerBg),
        children: [
          for (var i = 0; i < headers.length; i++)
            cell(headers[i], bold: true, right: i == headers.length - 1),
        ],
      ),
      for (final row in rows)
        pw.TableRow(children: [
          for (var i = 0; i < row.length; i++)
            cell(row[i],
                right: i == row.length - 1,
                bold: i == row.length - 1,
                color: i == row.length - 1
                    ? const PdfColor.fromInt(0xFF0E4F46)
                    : null),
        ]),
    ],
  );
}

/// Summary for the Reports screen — white/black, no colours, clean tables.
Future<void> shareReportsSummaryPdf({
  required BusinessProfile business,
  required DateTime from,
  required DateTime to,
  required String modeLabel,
  required double totalPurchase,
  required double totalProfit,
  required int purchaseCount,
  required List<Map<String, dynamic>> tableRows,
  required String Function(Map<String, dynamic> r) rowLabel,
  required num Function(Map<String, dynamic> r) rowMetricPurchase,
  required num Function(Map<String, dynamic> r) rowMetricProfit,
  String? priorPeriodNote,
  // Optional unit totals (kg / bag / box / tin).
  double? totalKg,
  double? totalBags,
  double? totalBoxes,
  double? totalTins,
  // Optional per-category rows: [{category_name, total_purchase}]
  List<Map<String, dynamic>>? categoryRows,
  // Optional per-supplier rows: [{supplier_name, purchase_count, total_purchase}]
  List<Map<String, dynamic>>? supplierRows,
}) async {
  final modeSafe = safePdfText(modeLabel);
  final header = await _businessPdfHeader(
    business,
    headline: 'Purchase Report · $modeSafe',
    subline: '${_df.format(from)} – ${_df.format(to)}',
  );

  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (ctx) => [
        header,
        pw.SizedBox(height: 6),
        pw.Text(
          'Total purchases is the sum of trade line amounts for deals in this range (same method as the in-app reports). A single purchase PDF invoice total can differ because it includes header terms (discount, freight, etc.).',
          style: const pw.TextStyle(
              fontSize: 7.2, color: _muted, height: 1.3),
        ),
        _divider(),

        // ── SUMMARY BLOCK ─────────────────────────────────────────────────
        _hdr('Summary'),
        _kv('Total purchases', _rs(totalPurchase), bold: true),
        _kv('Number of deals', '$purchaseCount'),
        if (totalKg != null && totalKg > 0)
          _kv('Total kg', '${totalKg.toStringAsFixed(0)} kg'),
        if (totalBags != null && totalBags > 0)
          _kv('Total bags', '${totalBags.toStringAsFixed(0)} bag'),
        if (totalBoxes != null && totalBoxes > 0)
          _kv('Total boxes', '${totalBoxes.toStringAsFixed(0)} box'),
        if (totalTins != null && totalTins > 0)
          _kv('Total tins', '${totalTins.toStringAsFixed(0)} tin'),
        _divider(),

        // ── MAIN TABLE ────────────────────────────────────────────────────
        _hdr('By $modeLabel'),
        pw.SizedBox(height: 4),
        if (tableRows.isEmpty)
          pw.Text('No data for this period.',
              style: const pw.TextStyle(fontSize: 9, color: _muted))
        else
          _tableSection(
            headers: ['Item', 'Total ₹'],
            widths: [
              const pw.FlexColumnWidth(4),
              const pw.FlexColumnWidth(2),
            ],
            rows: tableRows
                .take(50)
                .map((r) => [
                      rowLabel(r),
                      _rs(rowMetricPurchase(r)),
                    ])
                .toList(),
          ),
        _divider(),

        // ── CATEGORY SUMMARY ──────────────────────────────────────────────
        if (categoryRows != null && categoryRows.isNotEmpty) ...[
          _hdr('Category summary'),
          pw.SizedBox(height: 4),
          _tableSection(
            headers: ['Category', 'Total ₹'],
            rows: categoryRows
                .take(30)
                .map((r) => [
                      r['category_name']?.toString() ?? '—',
                      _rs(
                          coerceToDouble(r['total_purchase'])),
                    ])
                .toList(),
          ),
          _divider(),
        ],

        // ── SUPPLIER SUMMARY ──────────────────────────────────────────────
        if (supplierRows != null && supplierRows.isNotEmpty) ...[
          _hdr('Supplier summary'),
          pw.SizedBox(height: 4),
          _tableSection(
            headers: ['Supplier', 'Deals', 'Total ₹'],
            widths: [
              const pw.FlexColumnWidth(3),
              const pw.FlexColumnWidth(1),
              const pw.FlexColumnWidth(2),
            ],
            rows: supplierRows
                .take(30)
                .map((r) => [
                      r['supplier_name']?.toString() ?? '—',
                      '${coerceToInt(r['purchase_count'])}',
                      _rs(
                          coerceToDouble(r['total_purchase'])),
                    ])
                .toList(),
          ),
          _divider(),
        ],

        pw.Text(
          'Period: ${_df.format(from)} – ${_df.format(to)} · Generated by Harisree Exp&Pur',
          style: const pw.TextStyle(fontSize: 7.5, color: _muted),
        ),
      ],
    ),
  );
  final safe =
      modeLabel.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  await Printing.sharePdf(
    bytes: await doc.save(),
    filename: 'report_${safe}_${_df.format(from)}.pdf',
  );
}

/// Item purchase statement from trade rows (black/white tables, ASCII-friendly).
Future<void> shareItemPurchaseTradeHistoryPdf({
  required BusinessProfile business,
  required String itemName,
  required List<List<String>> rows,
  DateTime? periodFrom,
  DateTime? periodTo,
  String? periodDescription,
  String? totalLineLabel,
}) async {
  if (rows.isEmpty) return;
  final periodParts = <String>[];
  if (periodDescription != null && periodDescription.isNotEmpty) {
    periodParts.add(periodDescription);
  }
  if (periodFrom != null && periodTo != null) {
    // Hyphen, not en-dash, so default PDF font encodes it.
    periodParts
        .add('${_df.format(periodFrom)} - ${_df.format(periodTo)}');
  }
  final periodLine = periodParts.isEmpty
      ? 'All available lines in export'
      : periodParts.join(' | ');
  final cleanItem = safePdfText(itemName);
  const headers = <String>[
    'Date',
    'Supplier',
    'Broker',
    'Qty',
    'Rate',
    'Landing',
    'Selling',
    'Line total',
  ];
  if (rows.any((r) => r.length != headers.length)) {
    throw ArgumentError(
      'Item statement rows must have ${headers.length} columns, '
      'got ${rows.map((r) => r.length).toSet()}',
    );
  }
  final header = await _businessPdfHeader(
    business,
    headline: 'Item statement — $cleanItem',
    subline: 'Period: ${safePdfText(periodLine)}',
  );
  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (context) => [
        header,
        pw.SizedBox(height: 10),
        pw.Table(
          border: pw.TableBorder.all(color: _border, width: 0.5),
          columnWidths: {
            0: const pw.FlexColumnWidth(1.4),
            1: const pw.FlexColumnWidth(1.6),
            2: const pw.FlexColumnWidth(1.2),
            3: const pw.FlexColumnWidth(1.1),
            4: const pw.FlexColumnWidth(1.4),
            5: const pw.FlexColumnWidth(1.2),
            6: const pw.FlexColumnWidth(1.1),
            7: const pw.FlexColumnWidth(1.3),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: _headerBg),
              children: [
                for (final h in headers)
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(3),
                    child: pw.Text(h,
                        style: pw.TextStyle(
                            fontSize: 7,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.black)),
                  ),
              ],
            ),
            for (final r in rows)
              pw.TableRow(
                children: [
                  for (var i = 0; i < r.length; i++)
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(3),
                      child: pw.Text(
                        safePdfText(r[i]),
                        textAlign:
                            i == r.length - 1 ? pw.TextAlign.right : pw.TextAlign.left,
                        style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.black),
                      ),
                    ),
                ],
              ),
          ],
        ),
        if (totalLineLabel != null && totalLineLabel.isNotEmpty) ...[
          pw.SizedBox(height: 8),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              safePdfText(totalLineLabel),
              style: pw.TextStyle(
                  fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.black),
            ),
          ),
        ],
        pw.SizedBox(height: 12),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Generated by Harisree Exp&Pur',
                style: const pw.TextStyle(fontSize: 7.5, color: _muted)),
            pw.Text('Generated on: ${_genDf.format(DateTime.now())}',
                style: const pw.TextStyle(fontSize: 7.5, color: _muted)),
          ],
        ),
      ],
    ),
  );
  final safe = itemName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  await Printing.sharePdf(
    bytes: await doc.save(),
    filename: 'item_statement_$safe.pdf',
  );
}

/// Line statement from `/trade-purchases` aggregate (reports SSOT) as PDF bytes.
Future<Uint8List> buildTradeStatementSsotPdfBytes({
  required BusinessProfile business,
  required DateTime from,
  required DateTime to,
  required List<TradePurchase> purchases,
}) async {
  final lines = buildTradeStatementLines(purchases);
  final header = await _businessPdfHeader(
    business,
    headline: 'Trade purchases statement',
    subline:
        'Period: ${_df.format(from)} → ${_df.format(to)} · ${purchases.length} purchases',
  );
  final money2 = NumberFormat('#,##,##0.00', 'en_IN');

  pw.Widget cell(String t, {bool hdr = false, bool right = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
        child: pw.Text(
          safePdfText(t),
          textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
          style: pw.TextStyle(
            fontSize: hdr ? 8 : 7.5,
            fontWeight:
                hdr ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      );

  const hdrs = [
    'Date',
    'Supplier',
    'Item',
    'Qty',
    'Unit',
    'Bags',
    'Kg',
    'Rate',
    'Amount',
  ];
  final rows = <List<String>>[];
  for (final l in lines) {
    rows.add([
      _df.format(l.date),
      l.supplierName,
      l.itemName,
      l.qty == l.qty.roundToDouble()
          ? '${l.qty.round()}'
          : money2.format(l.qty),
      l.unit,
      l.bagsCell,
      l.kg < 1e-9
          ? '—'
          : (l.kg == l.kg.roundToDouble()
              ? '${l.kg.round()}'
              : l.kg.toStringAsFixed(1)),
      money2.format(l.rate),
      money2.format(l.amountInr),
    ]);
  }

  // Pack + money totals: same aggregate engine as in-app Reports / dashboard
  // (classified BAG/BOX/TIN lines only — matches `buildTradeReportAgg`).
  final agg = buildTradeReportAgg(purchases);
  final tt = agg.totals;

  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(26),
      build: (_) => [
        header,
        pw.SizedBox(height: 8),
        pw.Table(
          border: pw.TableBorder.all(color: _border, width: 0.4),
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: _headerBg),
              children: [for (final h in hdrs) cell(h, hdr: true)],
            ),
            for (final r in rows)
              pw.TableRow(
                children: [
                  cell(r[0]),
                  cell(r[1]),
                  cell(r[2]),
                  cell(r[3]),
                  cell(r[4], right: true),
                  cell(r[5]),
                  cell(r[6], right: true),
                  cell(r[7], right: true),
                  cell(r[8], right: true),
                ],
              ),
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Container(
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: _border, width: 0.5),
            color: _headerBg,
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'REPORT TOTALS',
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Table(
                border: pw.TableBorder.all(color: _border, width: 0.3),
                children: [
                  pw.TableRow(
                    decoration:
                        const pw.BoxDecoration(color: PdfColors.white),
                    children: [
                      _totCell(
                        'Bags',
                        '${tt.bags > 1e-9 ? tt.bags.round() : 0}',
                        bold: tt.bags > 1e-9,
                      ),
                      _totCell(
                        'Boxes',
                        '${tt.boxes > 1e-9 ? tt.boxes.round() : 0}',
                        bold: tt.boxes > 1e-9,
                      ),
                      _totCell(
                        'Tins',
                        '${tt.tins > 1e-9 ? tt.tins.round() : 0}',
                        bold: tt.tins > 1e-9,
                      ),
                      _totCell(
                        'Total KG',
                        tt.kg > 1e-9
                            ? '${tt.kg.round()} KG'
                            : '—',
                        bold: true,
                      ),
                      _totCell(
                        'Total Amount',
                        'Rs. ${_money.format(tt.inr)}',
                        bold: true,
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Deals (pack-classified lines): ${tt.deals}',
                style: const pw.TextStyle(fontSize: 8, color: _muted),
              ),
              pw.Text(
                'Period: ${_df.format(from)} → ${_df.format(to)}   |   ${purchases.length} purchases',
                style: const pw.TextStyle(fontSize: 8, color: _muted),
              ),
              pw.Text(
                'Generated: ${_genDf.format(DateTime.now())}',
                style: const pw.TextStyle(fontSize: 8, color: _muted),
              ),
            ],
          ),
        ),
      ],
    ),
  );
  return doc.save();
}

/// Opens the print/share preview UI for the trade statement PDF.
Future<void> layoutTradeStatementSsotPdf({
  required BusinessProfile business,
  required DateTime from,
  required DateTime to,
  required List<TradePurchase> purchases,
}) async {
  await Printing.layoutPdf(
    onLayout: (_) async => buildTradeStatementSsotPdfBytes(
      business: business,
      from: from,
      to: to,
      purchases: purchases,
    ),
  );
}
