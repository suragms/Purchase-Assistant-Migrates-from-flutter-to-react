import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/features/barcode/presentation/widgets/scan_item_stock_summary_card.dart';

void main() {
  testWidgets('shows system, physical, and last purchased tiles', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScanItemStockSummaryCard(
            item: {
              'name': 'Rice',
              'item_code': 'RICE-1',
              'barcode': '8901',
              'stock_unit': 'bag',
              'current_stock': 10,
              'physical_stock_qty': 9,
              'last_purchase_qty': 5,
              'last_purchase_unit': 'bag',
              'last_purchase_date': '2026-05-01T00:00:00Z',
              'supplier_name': 'Acme Traders',
              'last_purchase_rate': 120,
            },
          ),
        ),
      ),
    );

    expect(find.text('Current Stock'), findsOneWidget);
    expect(find.text('Physical Count'), findsOneWidget);
    expect(find.text('Last Purchase'), findsOneWidget);
    expect(find.textContaining('Acme'), findsOneWidget);
  });
}
