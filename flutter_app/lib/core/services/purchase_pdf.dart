import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../calc_engine.dart' show lineMoney;
import '../models/business_profile.dart';
import '../models/trade_purchase_models.dart';
import '../utils/trade_purchase_rate_display.dart';
import '../utils/unit_utils.dart';
import '../units/dynamic_unit_label_engine.dart' as unit_lbl;
import '../config/app_config.dart';
import 'pdf_actions.dart';
import 'pdf_locale.dart';
import 'pdf_purchase_fonts.dart';
import 'purchase_invoice_amount_words.dart';
import 'purchase_invoice_pdf_layout.dart';
import 'pdf_text_safe.dart';

final _money = NumberFormat('#,##,##0.00', 'en_IN');
String _inrPdf(num n) => 'Rs. ${_money.format(n)}';
final _dateTimePdf = DateFormat('dd MMM yyyy, hh:mm a');

String _supplierSlug(String? name) {
  final raw = (name ?? '').trim().toUpperCase();
  if (raw.isEmpty) return 'PURCHASE';
  final cleaned = raw
      .replaceAll(RegExp(r'[^A-Z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
  if (cleaned.isEmpty) return 'PURCHASE';
  return cleaned.length > 40 ? cleaned.substring(0, 40) : cleaned;
}

/// Share-friendly filename, e.g. `PO_AMBAL_MODERN_RICE_MILL_25_MAY_2026.pdf`.
String buildPurchaseSharePdfFileName(
  TradePurchase p, {
  bool fullInvoice = false,
}) {
  final d = p.purchaseDate.toLocal();
  final months = const [
    'JAN',
    'FEB',
    'MAR',
    'APR',
    'MAY',
    'JUN',
    'JUL',
    'AUG',
    'SEP',
    'OCT',
    'NOV',
    'DEC',
  ];
  final slug = _supplierSlug(p.supplierName);
  if (slug == 'PURCHASE') {
    final hid = p.humanId.replaceAll(RegExp(r'[^\w\-]+'), '_');
    final ymd =
        '${d.year}_${d.month.toString().padLeft(2, '0')}_${d.day.toString().padLeft(2, '0')}';
    return 'PO_${hid}_$ymd${fullInvoice ? '_full' : ''}.pdf';
  }
  final datePart =
      '${d.day.toString().padLeft(2, '0')}_${months[d.month - 1]}_${d.year}';
  return 'PO_${slug}_$datePart${fullInvoice ? '_full' : ''}.pdf';
}

const _muted = PdfColor.fromInt(0xFF475569);
const _border = PdfColor.fromInt(0xFFD1D5DB);

String _partyName(String? s) =>
    safePdfCell(s);

String _pdfReceiptPurchase(TradePurchaseLine l) {
  final r = tradePurchaseLineDisplayPurchaseRate(l);
  return '${_inrPdf(r)}/${unit_lbl.purchaseRateSuffix(l)}';
}

String _pdfReceiptSelling(TradePurchaseLine l) {
  final r = tradePurchaseLineDisplaySellingRate(l);
  if (r == null) return pdfEmpty;
  return '${_inrPdf(r)}/${unit_lbl.sellingRateSuffix(l)}';
}

/// One-page receipt: minimal lines (Unicode-safe when [pdfTheme] set).
Future<pw.Document> buildPurchaseReceiptDoc(
  TradePurchase p,
  BusinessProfile biz, {
  pw.ThemeData? pdfTheme,
}) async {
  final brokerAmt = purchaseBrokerCommissionForReceipt(p);
  final doc = pw.Document(theme: pdfTheme);
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      theme: pdfTheme,
      build: (ctx) => [
        pw.Text(
          safePdfText(
            biz.displayTitle.trim().isNotEmpty ? biz.displayTitle : 'Business',
          ),
          style: pw.TextStyle(
            fontSize: 16,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        if (biz.address != null && biz.address!.trim().isNotEmpty)
          pw.Text(
            safePdfText(biz.address!.trim()),
            style: const pw.TextStyle(fontSize: 9, color: _muted, height: 1.35),
          ),
        if (biz.phone != null && biz.phone!.trim().isNotEmpty)
          pw.Text(
            'Phone: ${biz.phone!.trim()}',
            style: const pw.TextStyle(fontSize: 9, color: _muted),
          ),
        pw.SizedBox(height: 14),
        pw.Text(
          'Purchase ${p.humanId}',
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          'Supplier: ${_partyName(p.supplierName)}',
          style: const pw.TextStyle(fontSize: 10.5),
        ),
        if (p.brokerName != null && p.brokerName!.trim().isNotEmpty)
          pw.Text(
            'Broker: ${_partyName(p.brokerName)}',
            style: const pw.TextStyle(fontSize: 10.5),
          ),
        pw.Text(
          'Date: ${_dateTimePdf.format(p.purchaseDate)}',
          style: const pw.TextStyle(fontSize: 10.5),
        ),
        pw.SizedBox(height: 12),
        pw.Text(
          'Items',
          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        for (final l in p.lines) ...[
          pw.Text(
            safePdfText(l.itemName),
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(
            safePdfText(
              '  ${formatStockQtyForUnit(l.unit, l.qty.toDouble())} ${l.unit.trim()}  |  P ${_pdfReceiptPurchase(l)}  |  S ${_pdfReceiptSelling(l)}  |  ${_inrPdf(l.lineTotal ?? lineMoney(tradePurchaseLineToCalcLine(l)))}',
            ),
            style: const pw.TextStyle(fontSize: 9, color: _muted),
          ),
          pw.SizedBox(height: 6),
        ],
        pw.Container(height: 1, color: _border),
        pw.SizedBox(height: 8),
        pw.Text(
          'Total: ${_inrPdf(p.totalAmount)}',
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
        ),
        if (brokerAmt > 0)
          pw.Text(
            'Broker commission: ${_inrPdf(brokerAmt)}',
            style: const pw.TextStyle(fontSize: 10),
          ),
        pw.SizedBox(height: 6),
        pw.Text(
          safePdfText(
            'Paid ${_inrPdf(p.paidAmount)}  |  Balance ${_inrPdf(p.remaining)}',
          ),
          style: const pw.TextStyle(fontSize: 9, color: _muted),
        ),
        pw.SizedBox(height: 10),
        pw.Text(
          'Amount in words: ${amountInWordsInr(p.totalAmount)}',
          style: const pw.TextStyle(fontSize: 8, color: _muted, height: 1.2),
        ),
        pw.SizedBox(height: 8),
        pw.Text(
          safePdfText(AppConfig.appName),
          style: const pw.TextStyle(fontSize: 7.5, color: _muted),
        ),
      ],
    ),
  );
  return doc;
}

/// Professional A4 purchase order; footer uses server [TradePurchase.totalAmount].
Future<pw.Document> buildPurchaseDoc(
  TradePurchase p,
  BusinessProfile biz, {
  String? generatedByName,
}) async {
  final logo = await tryFetchPdfLogo(biz.logoUrl);
  final pdfTheme = await loadPurchasePdfTheme();
  final doc = await buildProfessionalPurchaseInvoiceDoc(
    purchase: p,
    business: biz,
    logo: logo,
    pdfTheme: pdfTheme,
    generatedByName: generatedByName,
  );
  return doc;
}

Future<Uint8List> buildPurchasePdfBytes(
  TradePurchase p,
  BusinessProfile biz, {
  String? generatedByName,
}) async {
  await ensurePdfLocalesInitialized();
  final doc = await buildPurchaseDoc(
    p,
    biz,
    generatedByName: generatedByName,
  );
  return doc.save();
}

/// Returns a user-facing result; failures never reach [FlutterError.onError].
Future<PdfActionResult> sharePurchasePdf(TradePurchase p, BusinessProfile biz) {
  return sharePdfBytes(
    buildBytes: () => buildPurchasePdfBytes(p, biz),
    filename: buildPurchaseSharePdfFileName(p),
    subject: '${p.supplierName ?? 'Purchase'} - ${p.humanId}',
    source: 'purchase_pdf',
  );
}

Future<PdfActionResult> printPurchasePdf(TradePurchase p, BusinessProfile biz) {
  return printPdfBytes(
    buildBytes: () => buildPurchasePdfBytes(p, biz),
    filename: buildPurchaseSharePdfFileName(p),
    source: 'purchase_pdf',
  );
}

Future<PdfActionResult> downloadPurchasePdf(
    TradePurchase p, BusinessProfile biz) {
  return savePdfBytes(
    buildBytes: () => buildPurchasePdfBytes(p, biz),
    filename: buildPurchaseSharePdfFileName(p),
    subject: '${p.supplierName ?? 'Purchase'} - ${p.humanId}',
    source: 'purchase_pdf',
  );
}

Future<PdfActionResult> sharePurchaseFullInvoicePdf(
  TradePurchase p,
  BusinessProfile biz,
) {
  return sharePdfBytes(
    buildBytes: () => buildPurchasePdfBytes(p, biz),
    filename: buildPurchaseSharePdfFileName(p, fullInvoice: true),
    subject: '${p.supplierName ?? 'Purchase'} - ${p.humanId}',
    source: 'purchase_pdf',
  );
}
