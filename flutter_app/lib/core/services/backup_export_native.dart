import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Saves export bytes under:
/// - Android/iOS: app documents `warehouse_exports/{year}/{month}/{category}/`
/// - Windows/macOS/Linux: Downloads `warehouse_exports/{year}/{month}/{category}/`
/// - When [useDesktopFolder] on Windows: `Desktop/Harisree_Backups/{year}/{month}/{category}/`
Future<String?> saveBackupExportBytes({
  required Uint8List bytes,
  required String filename,
  required String category,
  bool useDesktopFolder = false,
}) async {
  try {
    final now = DateTime.now();
    final Directory root;
    if (useDesktopFolder && Platform.isWindows) {
      final profile = Platform.environment['USERPROFILE'];
      if (profile != null && profile.isNotEmpty) {
        root = Directory('$profile${Platform.pathSeparator}Desktop${Platform.pathSeparator}Harisree_Backups');
      } else {
        root = await _defaultExportRoot();
      }
    } else {
      root = await _defaultExportRoot();
    }
    final dirPath = [
      root.path,
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

Future<Directory> _defaultExportRoot() async {
  if (Platform.isAndroid || Platform.isIOS) {
    return getApplicationDocumentsDirectory();
  }
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    final downloads = await getDownloadsDirectory();
    if (downloads != null) {
      return Directory('${downloads.path}${Platform.pathSeparator}warehouse_exports');
    }
  }
  return getApplicationDocumentsDirectory();
}
