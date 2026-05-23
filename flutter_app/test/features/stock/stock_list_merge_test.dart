import 'package:flutter_test/flutter_test.dart';
import 'package:hexa_purchase_assistant/features/stock/stock_list_merge.dart';

void main() {
  test('mergeStockListPage replaces on page 1', () {
    final out = mergeStockListPage(
      previous: null,
      incoming: {
        'items': [
          {'id': 'a', 'name': 'A'},
        ],
        'total': 10,
      },
      page: 1,
    );
    expect((out['items'] as List).length, 1);
    expect(out['total'], 10);
  });

  test('mergeStockListPage appends on page 2', () {
    final out = mergeStockListPage(
      previous: {
        'items': [
          {'id': 'a', 'name': 'A'},
        ],
        'total': 2,
      },
      incoming: {
        'items': [
          {'id': 'b', 'name': 'B'},
        ],
        'total': 2,
      },
      page: 2,
    );
    expect((out['items'] as List).length, 2);
  });
}
