import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/features/stock/presentation/widgets/stock_row_actions.dart';

void main() {
  testWidgets('stock row tap shows compact warehouse actions', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                return TextButton(
                  onPressed: () => showStockRowActions(
                    context: context,
                    ref: ref,
                    item: const {
                      'id': 'item-1',
                      'name': '916 RAVA 50KG',
                      'current_stock': 150,
                      'stock_unit': 'bag',
                    },
                  ),
                  child: const Text('open'),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('916 RAVA 50KG'), findsOneWidget);
    expect(find.text('Update physical stock'), findsOneWidget);
    expect(find.text('Add purchase quantity'), findsOneWidget);
    expect(find.text('View item activity'), findsOneWidget);
  });
}
