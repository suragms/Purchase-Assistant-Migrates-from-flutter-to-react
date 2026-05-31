import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/features/catalog/presentation/widgets/item_physical_verification_card.dart';

void main() {
  test('purchase maps to DELIVERED', () {
    expect(stockAdjustmentTypeLabel('purchase'), 'DELIVERED');
    expect(stockAdjustmentTypeLabel('delivery_receive'), 'DELIVERED');
  });

  test('verification maps to VERIFICATION', () {
    expect(stockAdjustmentTypeLabel('verification'), 'VERIFICATION');
  });
}
