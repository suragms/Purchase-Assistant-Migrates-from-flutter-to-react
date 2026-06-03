import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../calc_engine.dart';
import '../catalog/item_trade_history.dart' show tradeLineToCalc;
import '../models/business_profile.dart';
import '../models/trade_purchase_models.dart';
import '../providers/business_profile_provider.dart';
import '../router/navigation_ext.dart';
import '../units/dynamic_unit_label_engine.dart' as unit_lbl;
import '../utils/trade_purchase_rate_display.dart';
import 'pdf_actions.dart';
import 'purchase_accounts_share_stub.dart'
    if (dart.library.html) 'purchase_accounts_share_web.dart' as web_share;
import 'purchase_pdf.dart';
import 'whatsapp_phone_normalize.dart';

export 'whatsapp_phone_normalize.dart'
    show normalizeAccountsWhatsappPhone, normalizeGulfMobile, normalizeIndiaMobile10;

const int _kMaxSummaryLines = 40;

final NumberFormat _inr = NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 0,
);

String _formatQtyUnit(TradePurchaseLine l) {
  final u = l.unit.trim();
  if (u.isEmpty) return '${l.qty}';
  return '${l.qty} $u';
}

String _formatLineRate(TradePurchaseLine l) {
  final rate = tradePurchaseLineDisplayPurchaseRate(l);
  final suffix = unit_lbl.purchaseRateSuffix(l);
  return '${_inr.format(rate)}/$suffix';
}

double _lineTotalAmount(TradePurchaseLine l) =>
    l.lineTotal ?? lineMoney(tradeLineToCalc(l));

String buildAccountsWhatsAppSummary(TradePurchase p, BusinessProfile biz) {
  final title = biz.displayTitle.trim().isNotEmpty
      ? biz.displayTitle.trim()
      : biz.legalName.trim();
  final supplier = (p.supplierName ?? '').trim().isNotEmpty
      ? p.supplierName!.trim()
      : '—';
  final dateStr = DateFormat('dd/MM/yyyy').format(p.purchaseDate);
  final ref = p.humanId.trim().isNotEmpty ? p.humanId.trim() : p.id;
  final total = _inr.format(p.totalAmount);

  final buf = StringBuffer()
    ..writeln(title)
    ..writeln('Purchase date: $dateStr')
    ..writeln('Supplier: $supplier')
    ..writeln('Ref: $ref')
    ..writeln()
    ..writeln('Items:');

  final lines = p.lines;
  final show = lines.length > _kMaxSummaryLines ? _kMaxSummaryLines : lines.length;
  for (var i = 0; i < show; i++) {
    final l = lines[i];
    final lineTotal = _inr.format(_lineTotalAmount(l));
    buf.writeln(
      '${i + 1}) ${l.itemName.trim()} | ${_formatQtyUnit(l)} @ ${_formatLineRate(l)} = $lineTotal',
    );
  }
  if (lines.length > _kMaxSummaryLines) {
    buf.writeln('…and ${lines.length - _kMaxSummaryLines} more items');
  }

  buf
    ..writeln()
    ..writeln('Grand total: $total');

  return buf.toString().trim();
}

/// Short PO message for Save & Share → accounts WhatsApp (fixed recipient).
String buildPurchaseOrderWhatsAppMessage(TradePurchase p, BusinessProfile biz) {
  final po = p.humanId.trim().isNotEmpty ? p.humanId.trim() : p.id;
  final supplier = (p.supplierName ?? '').trim().isNotEmpty
      ? p.supplierName!.trim()
      : '—';
  final broker = (p.brokerName ?? '').trim();
  final itemCount = p.lines.length;
  final qtyLine = _aggregateQuantityLine(p);
  final expected = p.dueDate != null
      ? DateFormat('dd-MMM-yyyy').format(p.dueDate!)
      : '—';
  final total = _inr.format(p.totalAmount);

  final buf = StringBuffer()
    ..writeln('New Purchase Order Created')
    ..writeln()
    ..writeln('PO Number:')
    ..writeln(po)
    ..writeln()
    ..writeln('Supplier:')
    ..writeln(supplier);
  if (broker.isNotEmpty) {
    buf
      ..writeln()
      ..writeln('Broker:')
      ..writeln(broker);
  }
  buf
    ..writeln()
    ..writeln('Items:')
    ..writeln('$itemCount')
    ..writeln()
    ..writeln('Quantity:')
    ..writeln(qtyLine)
    ..writeln()
    ..writeln('Total:')
    ..writeln(total)
    ..writeln()
    ..writeln('Expected Delivery:')
    ..writeln(expected)
    ..writeln()
    ..writeln('Please verify when goods arrive.')
    ..writeln()
    ..writeln('PDF attached');

  final title = biz.displayTitle.trim().isNotEmpty
      ? biz.displayTitle.trim()
      : biz.legalName.trim();
  final body = buf.toString().trim();
  if (title.isEmpty) return body;
  return '$title\n\n$body';
}

String _aggregateQuantityLine(TradePurchase p) {
  if (p.lines.isEmpty) return '—';
  final byUnit = <String, double>{};
  for (final l in p.lines) {
    final u = l.unit.trim().isEmpty ? 'units' : l.unit.trim();
    byUnit[u] = (byUnit[u] ?? 0) + l.qty.toDouble();
  }
  if (byUnit.length == 1) {
    final e = byUnit.entries.first;
    final q = e.value == e.value.roundToDouble()
        ? e.value.round().toString()
        : e.value.toStringAsFixed(2);
    return '$q ${e.key}';
  }
  final parts = <String>[];
  byUnit.forEach((u, q) {
    final s = q == q.roundToDouble() ? q.round().toString() : q.toStringAsFixed(2);
    parts.add('$s $u');
  });
  return parts.join(', ');
}

String maskWhatsappRecipient(String waMeDigits) {
  final d = waMeDigits.replaceAll(RegExp(r'\D'), '');
  if (d.length <= 4) return '****';
  return '***${d.substring(d.length - 4)}';
}

Uri whatsappUriForPhone(String waMeDigits, String message) {
  return Uri.parse(
    'https://wa.me/$waMeDigits?text=${Uri.encodeComponent(message)}',
  );
}

@Deprecated('Use whatsappUriForPhone with waMeDigits from normalizeAccountsWhatsappPhone')
Uri whatsappUriForAccounts(String phone10, String message) {
  return whatsappUriForPhone('91$phone10', message);
}

/// Generic WhatsApp summary (no fixed recipient).
Future<void> openWhatsAppSummaryMessage(
  TradePurchase p, {
  BusinessProfile? biz,
}) async {
  final profile = biz ??
      const BusinessProfile(
        legalName: 'Workspace',
        displayTitle: 'Purchase order',
      );
  final text = buildAccountsWhatsAppSummary(p, profile);
  final uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}');
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// Returns true when share may proceed (number configured or user chose Skip).
Future<bool> ensureAccountsWhatsappConfigured(
  BuildContext context,
  WidgetRef ref,
) async {
  final stored =
      ref.read(invoiceBusinessProfileProvider).accountsWhatsappNumber;
  if (normalizedFromStoredAccountsWhatsapp(stored) != null) return true;
  if (!context.mounted) return false;

  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Accounts staff WhatsApp not set'),
      content: const Text(
        'Go to Settings → Business Profile to add the accounts staff WhatsApp number before sharing.',
      ),
      actions: [
        TextButton(
          onPressed: () => popOverlay(ctx, false),
          child: const Text('Skip'),
        ),
        FilledButton(
          onPressed: () => popOverlay(ctx, true),
          child: const Text('Go to Settings'),
        ),
      ],
    ),
  );
  if (go == true && context.mounted) {
    await context.push('/settings');
  }
  if (!context.mounted) return false;
  final after =
      ref.read(invoiceBusinessProfileProvider).accountsWhatsappNumber;
  return normalizedFromStoredAccountsWhatsapp(after) != null;
}

/// Save & Share: PDF + summary to [biz.accountsWhatsappNumber] only.
Future<PdfActionResult> sharePurchaseToAccountsStaff(
  TradePurchase p,
  BusinessProfile biz, {
  String? generatedByName,
}) async {
  final phone = normalizedFromStoredAccountsWhatsapp(biz.accountsWhatsappNumber) ??
      normalizeAccountsWhatsappPhone(biz.accountsWhatsappNumber);
  if (phone == null) {
    return const PdfActionResult(
      ok: false,
      message: 'Accounts WhatsApp number is not configured.',
    );
  }

  try {
    final bytes = await buildPurchasePdfBytes(
      p,
      biz,
      generatedByName: generatedByName,
    );
    final filename = buildPurchaseSharePdfFileName(p);
    final message = buildPurchaseOrderWhatsAppMessage(p, biz);
    final subject = '${p.supplierName ?? 'Purchase'} - ${p.humanId}';
    final waUri = whatsappUriForPhone(phone.waMeDigits, message);

    if (kIsWeb) {
      final shared = await web_share.tryWebSharePurchasePdf(
        bytes: bytes,
        filename: filename,
        text: message,
        title: subject,
      );
      if (shared) {
        if (await canLaunchUrl(waUri)) {
          await launchUrl(waUri, mode: LaunchMode.externalApplication);
        }
        return const PdfActionResult(
          ok: true,
          message: 'Purchase shared to accounts WhatsApp',
        );
      }
    }

    try {
      await Share.shareXFiles(
        [
          XFile.fromData(
            bytes,
            mimeType: 'application/pdf',
            name: filename,
          ),
        ],
        text: message,
        subject: subject,
      );
    } catch (e, st) {
      logPdfFailure('purchase_accounts_share', 'shareXFiles', e, st);
      return const PdfActionResult(
        ok: false,
        message: 'Could not share PDF. Try again.',
      );
    }

    if (await canLaunchUrl(waUri)) {
      await launchUrl(waUri, mode: LaunchMode.externalApplication);
    }

    return const PdfActionResult(
      ok: true,
      message: 'Purchase shared to accounts WhatsApp',
    );
  } catch (e, st) {
    logPdfFailure('purchase_accounts_share', 'share', e, st);
    return const PdfActionResult(
      ok: false,
      message: 'Could not export PDF. Check connection and retry.',
    );
  }
}
