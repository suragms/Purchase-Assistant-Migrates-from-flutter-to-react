import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:harisree_warehouse/features/home/presentation/widgets/home_owner_quick_actions.dart';

void main() {
  testWidgets('HomeOwnerQuickActions renders all tiles without null badge crash',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeOwnerQuickActions(
            onStock: () {},
            onPurchase: () {},
            onLowStock: () {},
            onPendingDeliveries: () {},
            onReports: () {},
            onUsers: () {},
            onBarcode: () {},
            onReorder: () {},
            lowStockCount: 3,
          ),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('Purchase'), findsOneWidget);
    expect(find.text('Stock'), findsOneWidget);
    expect(find.text('Low stock'), findsOneWidget);
    expect(find.text('Reports'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });
}
