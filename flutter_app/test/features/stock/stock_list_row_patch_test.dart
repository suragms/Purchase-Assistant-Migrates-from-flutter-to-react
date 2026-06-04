import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/features/stock/stock_list_row_patch.dart';

void main() {
  test('applyStockListRowPatch merges overlay by id', () {
    final out = applyStockListRowPatch(
      {'id': 'a', 'current_stock': 10, 'physical_stock_qty': 9},
      {
        'a': {'physical_stock_qty': 11, 'physical_stock_difference_qty': 1},
      },
    );
    expect(out['physical_stock_qty'], 11);
    expect(out['physical_stock_difference_qty'], 1);
    expect(out['current_stock'], 10);
  });

  test('stockListPatchFromPhysicalCount maps API fields', () {
    final patch = stockListPatchFromPhysicalCount({
      'counted_qty': 5001,
      'system_qty': 5000,
      'difference_qty': 1,
      'counted_by_name': 'Ananduk',
      'counted_at': '2026-06-04T12:00:00Z',
    });
    expect(patch['physical_stock_qty'], 5001);
    expect(patch['physical_stock_difference_qty'], 1);
    expect(patch['physical_stock_counted_by'], 'Ananduk');
  });
}
