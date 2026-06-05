import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

import 'backup_export.dart';
import 'file_download_stub.dart'
    if (dart.library.html) 'file_download_web.dart' as browser_dl;

class BackupDeliverResult {
  const BackupDeliverResult({
    required this.ok,
    required this.message,
    this.savedPath,
  });

  final bool ok;
  final String message;
  final String? savedPath;
}

/// Save locally when possible; on web trigger browser download (no share sheet).
Future<BackupDeliverResult> deliverBackupFile({
  required Uint8List bytes,
  required String filename,
  required String mimeType,
  required String shareText,
  required String saveCategory,
}) async {
  final savedPath = await saveBackupExportBytes(
    bytes: bytes,
    filename: filename,
    category: saveCategory,
  );

  if (kIsWeb) {
    final started = await browser_dl.triggerBrowserFileDownload(
      bytes,
      filename,
      mimeType,
    );
    if (started) {
      return const BackupDeliverResult(
        ok: true,
        message: 'Download started — check your Downloads folder',
      );
    }
    return const BackupDeliverResult(
      ok: false,
      message: 'Could not start download. Allow downloads for this site.',
    );
  }

  if (savedPath != null) {
    try {
      await Share.shareXFiles(
        [
          XFile.fromData(
            bytes,
            mimeType: mimeType,
            name: filename,
          ),
        ],
        text: shareText,
      );
      return BackupDeliverResult(
        ok: true,
        message: 'Saved and ready to share',
        savedPath: savedPath,
      );
    } catch (_) {
      return BackupDeliverResult(
        ok: true,
        message: 'Saved to $savedPath',
        savedPath: savedPath,
      );
    }
  }

  try {
    await Share.shareXFiles(
      [
        XFile.fromData(
          bytes,
          mimeType: mimeType,
          name: filename,
        ),
      ],
      text: shareText,
    );
    return const BackupDeliverResult(ok: true, message: 'Ready to share');
  } catch (_) {
    return const BackupDeliverResult(
      ok: false,
      message: 'Could not save or share file. Check Downloads access and try again.',
    );
  }
}
