import 'package:flutter_test/flutter_test.dart';

import 'package:hexa_purchase_assistant/features/barcode/presentation/warehouse_scan_action_sheet.dart';

void main() {
  test('formatQty rounds whole numbers', () {
    expect(formatQty(10), '10');
    expect(formatQty(10.5), '10.5');
  });
}
