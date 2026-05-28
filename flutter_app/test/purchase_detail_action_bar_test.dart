import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/core/models/trade_purchase_models.dart';
import 'package:harisree_warehouse/features/purchase/presentation/widgets/purchase_detail_action_bar.dart';

void main() {
  TradePurchase purchase() {
    return TradePurchase(
      id: 'id',
      humanId: 'PO-1',
      purchaseDate: DateTime(2026, 5, 25),
      paidAmount: 0,
      totalAmount: 100,
      storedStatus: 'confirmed',
      derivedStatus: 'confirmed',
      remaining: 100,
      discount: 0,
      commissionPercent: 0,
      freightType: 'separate',
      lines: [
        TradePurchaseLine(
          id: 'l1',
          itemName: 'Rice',
          qty: 1,
          unit: 'bag',
          landingCost: 100,
        ),
      ],
    );
  }

  Future<void> pumpBar(WidgetTester tester, double width) async {
    await tester.binding.setSurfaceSize(Size(width, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PurchaseDetailActionBar(
            purchase: purchase(),
            hideFinancials: false,
            onMarkPaid: () {},
            onEdit: () {},
            onExportPdf: () {},
            onShare: () {},
            onPrint: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows full action labels at 320px without overflow', (tester) async {
    await pumpBar(tester, 320);
    expect(find.text('Mark as Paid'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Export PDF'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('Share'), findsOneWidget);
    expect(find.text('Print'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hides bar when hideFinancials', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 600));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PurchaseDetailActionBar(
            purchase: purchase(),
            hideFinancials: true,
            onMarkPaid: () {},
            onEdit: () {},
            onExportPdf: () {},
            onShare: () {},
            onPrint: () {},
          ),
        ),
      ),
    );
    expect(find.text('Export PDF'), findsNothing);
  });
}
