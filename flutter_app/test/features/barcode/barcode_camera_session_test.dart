import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/features/barcode/barcode_camera_session.dart';

void main() {
  tearDown(() async {
    await BarcodeCameraSession.reset();
  });

  test('hasLiveMobile is false when no controller retained', () {
    expect(BarcodeCameraSession.mobile, isNull);
    expect(BarcodeCameraSession.hasLiveMobile, isFalse);
  });

  test('reset clears retained mobile controller', () async {
    await BarcodeCameraSession.reset();
    expect(BarcodeCameraSession.mobile, isNull);
    expect(BarcodeCameraSession.hasLiveMobile, isFalse);
  });
}
