import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Saves export bytes under:
/// - Android/iOS: app documents `warehouse_exports/{year}/{month}/{category}/`
/// - Windows/macOS/Linux: Downloads `warehouse_exports/{year}/{month}/{category}/`
Future<String?> saveBackupExportBytes({
  required Uint8List bytes,
  required String filename,
  required String category,
}) async {
  try {
    final now = DateTime.now();
    final Directory root;
    if (Platform.isAndroid || Platform.isIOS) {
      root = await getApplicationDocumentsDirectory();
    } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final downloads = await getDownloadsDirectory();
      root = downloads ?? await getApplicationDocumentsDirectory();
    } else {
      return null;
    }
    final dirPath = [
      root.path,
      'warehouse_exports',
      now.year.toString(),
      now.month.toString().padLeft(2, '0'),
      category,
    ].join(Platform.pathSeparator);
    final dir = Directory(dirPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File('$dirPath${Platform.pathSeparator}$filename');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  } catch (_) {
    return null;
  }
}
