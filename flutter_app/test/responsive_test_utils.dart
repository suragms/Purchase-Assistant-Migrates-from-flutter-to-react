import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const responsiveAuditWidths = <double>[
  320,
  375,
  390,
  414,
  768,
  1024,
  1280,
  1440,
  1920,
];

Future<void> pumpAtSize(
  WidgetTester tester,
  Size size,
  Widget widget,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(widget);
  await tester.pump();
}

Future<void> expectNoResponsiveOverflow(
  WidgetTester tester,
  Widget widget, {
  Iterable<double> widths = responsiveAuditWidths,
  double height = 740,
}) async {
  for (final width in widths) {
    await pumpAtSize(tester, Size(width, height), widget);
    expect(
      tester.takeException(),
      isNull,
      reason: 'No layout exception at ${width.toInt()}px',
    );
  }
}
