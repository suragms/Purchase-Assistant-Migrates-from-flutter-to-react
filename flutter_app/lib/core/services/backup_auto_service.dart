import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../auth/session_notifier.dart';
import '../providers/prefs_provider.dart';
import 'backup_export.dart';

const kAutoDailyBackupEnabledKey = 'backup_auto_daily_enabled';
const kAutoDailyBackupLastYmdKey = 'backup_auto_daily_last_ymd';

/// Runs at most once per calendar day on desktop/mobile when enabled.
Future<void> maybeRunDailyAutoBackup(WidgetRef ref) async {
  if (kIsWeb) return;
  final prefs = ref.read(sharedPreferencesProvider);
  if (!(prefs.getBool(kAutoDailyBackupEnabledKey) ?? false)) return;

  final session = ref.read(sessionProvider);
  if (session == null) return;

  final ymd = DateFormat('yyyy-MM-dd').format(DateTime.now());
  if (prefs.getString(kAutoDailyBackupLastYmdKey) == ymd) return;

  try {
    await ref.read(sessionProvider.notifier).ensureFreshSessionForExport();
  } catch (_) {
    return;
  }

  final businessId = session.primaryBusiness.id;
  final api = ref.read(hexaApiProvider);

  try {
    final zipBytes = await api.downloadBusinessBackup(
      businessId: businessId,
      rangePreset: 'month',
    );
    if (zipBytes.isEmpty) return;

    final filename = 'purchase_assistant_backup_$ymd.zip';
    await saveBackupExportBytes(
      bytes: zipBytes,
      filename: filename,
      category: 'auto',
      useDesktopFolder: true,
    );

    final stockBytes = await api.downloadStockInventoryXlsx(businessId: businessId);
    if (stockBytes.isNotEmpty) {
      await saveBackupExportBytes(
        bytes: stockBytes,
        filename: 'harisree_stock_$ymd.xlsx',
        category: 'auto',
        useDesktopFolder: true,
      );
    }

    try {
      final pdfBytes = await api.downloadPurchasesMonthPdf(businessId: businessId);
      if (pdfBytes.isNotEmpty) {
        final now = DateTime.now();
        final pdfName =
            'harisree_purchases_${now.year}-${now.month.toString().padLeft(2, '0')}.pdf';
        await saveBackupExportBytes(
          bytes: pdfBytes,
          filename: pdfName,
          category: 'auto',
          useDesktopFolder: true,
        );
      }
    } catch (_) {
      // No purchases this month — ZIP + stock still saved.
    }

    await prefs.setString(kAutoDailyBackupLastYmdKey, ymd);
  } catch (_) {
    // Silent — user can retry manually from Export & Backup.
  }
}
