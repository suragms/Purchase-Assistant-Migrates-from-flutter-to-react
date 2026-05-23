import 'package:flutter_test/flutter_test.dart';
import 'package:hexa_purchase_assistant/features/barcode/services/bulk_label_from_stock.dart';

void main() {
  test('labelDataFromStockRow uses item_code when barcode empty', () {
    final label = labelDataFromStockRow({
      'id': 'abc',
      'name': 'Sugar 1kg',
      'item_code': '2095',
      'current_stock': 12,
      'unit': 'bag',
    });
    expect(label, isNotNull);
    expect(label!.itemCode, '2095');
    expect(label.symbologyValue, '2095');
  });

  test('labelDataFromStockRow returns null without code', () {
    expect(labelDataFromStockRow({'name': 'X'}), isNull);
  });
}
