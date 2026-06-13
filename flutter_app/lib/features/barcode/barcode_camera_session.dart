import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:mobile_scanner/mobile_scanner.dart';

import 'presentation/web_live_barcode_scanner.dart';

/// Keeps one camera stream on web so Safari/Chrome do not re-prompt every tab visit.
abstract final class BarcodeCameraSession {
  static MobileScannerController? mobile;
  static WebLiveBarcodeScanner? webDetector;
  static bool useWebDetectorPreview = false;

  static bool get hasLiveWebDetector =>
      useWebDetectorPreview && (webDetector?.isActive ?? false);

  static bool get hasLiveMobile {
    if (mobile == null) return false;
    return mobile!.value.isRunning && mobile!.value.error == null;
  }

  static void retainMobile(MobileScannerController controller) {
    if (!kIsWeb) return;
    mobile = controller;
  }

  static void retainWebDetector(WebLiveBarcodeScanner scanner) {
    if (!kIsWeb) return;
    webDetector = scanner;
    useWebDetectorPreview = true;
  }

  /// Drop streams (logout, permission denied, explicit retry).
  static Future<void> reset() async {
    await webDetector?.stop();
    webDetector = null;
    useWebDetectorPreview = false;
    await mobile?.dispose();
    mobile = null;
  }
}
