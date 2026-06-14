import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../catalog/item_trade_history.dart';
import '../models/trade_purchase_models.dart';
import '../providers/business_profile_provider.dart';
import '../providers/trade_purchases_provider.dart';
import 'item_statement_pdf.dart';
import 'pdf_actions.dart';

String buildItemStatementFilename({
  required String itemName,
  required DateTime asOf,
}) {
  final slug = itemName
      .trim()
      .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
  final safe = slug.isEmpty ? 'Item' : slug;
  final df = DateFormat('ddMMMyyyy');
  return '${safe}_Statement_${df.format(asOf)}.pdf';
}

/// Shares a PDF item statement for the current catalog-intel purchase window.
///
/// Financials are already redacted server-side for staff in the list response.
Future<PdfActionResult> exportShareItemStatementPdf({
  required WidgetRef ref,
  required String catalogItemId,
  required String itemName,
  DateTime? fromDate,
  DateTime? toDate,
}) async {
  final business = ref.read(invoiceBusinessProfileProvider);
  final purchasesAll =
      ref.read(tradePurchasesCatalogIntelParsedProvider) ?? const <TradePurchase>[];
  final filtered = purchasesAll.where((p) {
    return p.lines.any(
      (ln) => itemLineBelongsToCatalog(
        ln,
        catalogItemId,
        catalogItemName: itemName,
      ),
    );
  }).toList();

  final now = DateTime.now();
  final from = fromDate ?? now.subtract(const Duration(days: 89));
  final to = toDate ?? now;

  return shareItemStatementPdf(
    business: business,
    itemName: itemName,
    purchases: filtered,
    fromDate: from,
    toDate: to,
    filename: buildItemStatementFilename(itemName: itemName, asOf: to),
  );
}

