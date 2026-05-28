import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/features/stock/presentation/widgets/stock_row_metrics.dart';

void main() {
  group('StockRowMetrics.purchasedQty', () {
    test('returns null when period_purchased_qty is absent', () {
      expect(StockRowMetrics.purchasedQty({}), isNull);
      expect(
        StockRowMetrics.purchasedQty({'period_purchased_qty': null}),
        isNull,
      );
    });

    test('returns value when period_purchased_qty is set', () {
      expect(
        StockRowMetrics.purchasedQty({'period_purchased_qty': 100}),
        100,
      );
      expect(
        StockRowMetrics.purchasedQty({'period_purchased_qty': 0}),
        0,
      );
    });

    test('qtyLine shows em dash for null and formats zero', () {
      expect(StockRowMetrics.qtyLine(null, 'BAG'), '—');
      expect(StockRowMetrics.qtyLine(0, 'BAG'), contains('0'));
      expect(StockRowMetrics.qtyLine(100, 'BAG'), contains('100'));
    });
  });
}
