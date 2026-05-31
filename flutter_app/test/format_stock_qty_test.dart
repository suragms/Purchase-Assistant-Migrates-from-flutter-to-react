import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/core/utils/unit_utils.dart';

void main() {
  test('formatStockQtyNumber strips near-integer decimals', () {
    expect(formatStockQtyNumber(101.0004), '101');
    expect(formatStockQtyNumber(100.9996), '101');
  });

  test('formatStockQtyNumber keeps meaningful fractions', () {
    expect(formatStockQtyNumber(101.25), '101.25');
    expect(formatStockQtyNumber(101.5), '101.5');
  });

  test('formatStockQtyForUnit — bag/box/tin integers, kg decimals', () {
    expect(formatStockQtyForUnit('bag', 101), '101');
    expect(formatStockQtyForUnit('BAG', 101.000), '101');
    expect(formatStockQtyForUnit('box', 12.001), '12');
    expect(formatStockQtyForUnit('tin', 5.9996), '6');
    expect(formatStockQtyForUnit('kg', 23.22), '23.22');
    expect(formatStockQtyForUnit('kg', 23.20), '23.2');
  });

  test('formatStockQtyDisplay adds KG suffix only for kg', () {
    expect(formatStockQtyDisplay('bag', 101), '101');
    expect(formatStockQtyDisplay('kg', 23.22), '23.22 KG');
  });
}
