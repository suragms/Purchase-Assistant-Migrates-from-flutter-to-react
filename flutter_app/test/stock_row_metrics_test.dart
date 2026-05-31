import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/core/utils/unit_utils.dart';
import 'package:harisree_warehouse/features/stock/presentation/widgets/stock_row_metrics.dart';

void main() {
  group('StockRowMetrics.diffQty', () {
    test('uses physical minus ledger on-hand when both present', () {
      final item = {
        'current_stock': 100,
        'expected_system_qty': 120,
        'physical_stock_qty': 80,
      };
      expect(StockRowMetrics.diffQty(item), -20);
    });

    test('prefers physical_stock_difference_qty when physical missing', () {
      final item = {
        'current_stock': 100,
        'expected_system_qty': 100,
        'physical_stock_difference_qty': 5,
      };
      expect(StockRowMetrics.diffQty(item), 5);
    });

    test('ledgerQty reads current_stock not expected formula', () {
      final item = {
        'current_stock': 42,
        'expected_system_qty': 99,
        'opening_stock_qty': 10,
        'total_delivered_qty': 50,
      };
      expect(StockRowMetrics.ledgerQty(item), 42);
      expect(StockRowMetrics.systemQty(item), 42);
      expect(StockRowMetrics.expectedSystemQty(item), 99);
    });

    test('does not subtract purchased qty', () {
      final item = {
        'current_stock': 101,
        'period_purchased_qty': 711,
        'physical_stock_qty': null,
      };
      final diff = StockRowMetrics.diffQty(item);
      expect(diff.isNaN, isTrue);
    });
  });

  group('StockRowMetrics table cell labels', () {
    test('physicalCellLabel returns em dash when not counted', () {
      expect(
        StockRowMetrics.physicalCellLabel(const {'current_stock': 10}),
        '—',
      );
    });

    test('physicalCellLabel formats counted qty', () {
      expect(
        StockRowMetrics.physicalCellLabel(const {
          'current_stock': 10,
          'physical_stock_qty': 8.5,
        }),
        '8.5',
      );
    });

    test('diffCellLabel signed when physical present', () {
      expect(
        StockRowMetrics.diffCellLabel(const {
          'current_stock': 100,
          'physical_stock_qty': 80,
        }),
        '-20',
      );
    });

    test('diffCellLabel em dash when unknown', () {
      expect(
        StockRowMetrics.diffCellLabel(const {'current_stock': 5}),
        '—',
      );
    });
  });

  group('formatStockQtyForUnit', () {
    test('bag uses integer without decimals', () {
      expect(formatStockQtyForUnit('bag', 101), '101');
      expect(formatStockQtyForUnit('BAG', 101.000), '101');
    });

    test('kg keeps decimals', () {
      expect(formatStockQtyForUnit('kg', 23.22), '23.22');
    });
  });

  group('StockRowMetrics pendingCellDisplay', () {
    test('shows pending qty and days', () {
      final cell = StockRowMetrics.pendingCellDisplay(const {
        'pending_delivery_qty': 12,
        'pending_order_days': 4,
        'has_pending_order': true,
        'stock_unit': 'bag',
      });
      expect(cell.primary, '12');
      expect(cell.secondary, '4d');
    });

    test('pending truck shows today when days is zero', () {
      final cell = StockRowMetrics.pendingCellDisplay(const {
        'pending_delivery_qty': 5,
        'pending_order_days': 0,
        'has_pending_order': true,
        'stock_unit': 'piece',
      });
      expect(cell.secondary, 'today');
    });

    test('delivered truck uses last_line_qty not period total', () {
      final cell = StockRowMetrics.pendingCellDisplay({
        'current_stock': 101,
        'period_purchased_qty': 711,
        'last_line_qty': 100,
        'last_purchase_at': DateTime.now()
            .subtract(const Duration(days: 4))
            .toIso8601String(),
        'last_purchase_human_id': 'PUR-1',
        'last_purchase_delivered': true,
        'stock_unit': 'bag',
      });
      expect(cell.primary, '100');
      expect(cell.secondary, '4d');
    });
  });

  group('formatStockQtyDisplay', () {
    test('bag omits unit suffix', () {
      expect(formatStockQtyDisplay('bag', 101), '101');
    });
    test('kg keeps decimals and unit', () {
      expect(formatStockQtyDisplay('kg', 23.22), '23.22 KG');
    });
  });

  group('StockRowMetrics.deliveryMetaLine', () {
    test('pending truck with qty and days', () {
      final line = StockRowMetrics.deliveryMetaLine({
        'has_pending_order': true,
        'pending_delivery_qty': 12,
        'pending_order_days': 3,
        'last_purchase_human_id': 'PO-1',
      });
      expect(line, contains('Pending truck'));
      expect(line, contains('3d'));
    });
  });
}
