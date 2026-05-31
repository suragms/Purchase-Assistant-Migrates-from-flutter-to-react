import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/features/stock/presentation/widgets/stock_warehouse_row.dart';
import 'package:harisree_warehouse/features/stock/presentation/widgets/stock_warehouse_table_header.dart';
import 'package:harisree_warehouse/features/stock/presentation/widgets/stock_table_layout.dart';
import 'package:harisree_warehouse/features/stock/presentation/widgets/stock_status_badge.dart';
import 'package:harisree_warehouse/features/stock/presentation/widgets/stock_row_metrics.dart';

void main() {
  testWidgets('warehouse row shows SYSTEM PHYS DIFF metrics', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) {
              return Scaffold(
                body: StockWarehouseRow(
                  ref: ref,
                  item: const {
                    'id': '1',
                    'name': 'Rice Premium',
                    'category_name': 'Grocery',
                    'subcategory_name': 'Rice',
                    'current_stock': 42,
                    'physical_stock_qty': 40,
                    'stock_status': 'low',
                  },
                  isStaffMode: false,
                  onTap: () {},
                ),
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('42'), findsOneWidget);
    expect(find.text('40'), findsOneWidget);
    expect(find.text('-2'), findsOneWidget);
    expect(find.byType(StockStatusBadge), findsNothing);
    expect(find.text('LOW'), findsNothing);
  });

  testWidgets('header and staff row use four-column layout', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) {
              return Scaffold(
                body: Column(
                  children: [
                    const StockWarehouseTableHeader(),
                    StockWarehouseRow(
                      ref: ref,
                      item: const {
                        'id': '1',
                        'name': 'Rice Premium',
                        'physical_stock_qty': 10,
                        'current_stock': 12,
                      },
                      isStaffMode: true,
                      onTap: () {},
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('SYS'), findsOneWidget);
    expect(find.text('PHYS'), findsOneWidget);
    expect(find.text('DIFF'), findsOneWidget);
    expect(find.text('PEND'), findsNothing);
    expect(find.text('STATUS'), findsNothing);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('10'), findsOneWidget);
    expect(find.text('-2'), findsOneWidget);
    expect(
      tester.getSize(find.byType(StockWarehouseRow)).height,
      StockTableLayout.rowMinHeight,
    );
  });

  testWidgets('physical and diff show em dash when not counted', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) {
              return Scaffold(
                body: StockWarehouseRow(
                  ref: ref,
                  item: const {
                    'id': '1',
                    'name': 'Sugar',
                    'current_stock': 20,
                  },
                  onTap: () {},
                ),
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('20'), findsOneWidget);
    expect(find.text('—'), findsNWidgets(2));
  });

  testWidgets('inline truck cue shows pending qty and days', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) {
              return Scaffold(
                body: StockWarehouseRow(
                  ref: ref,
                  item: const {
                    'id': '1',
                    'name': 'Basmati Rice',
                    'current_stock': 10,
                    'pending_delivery_qty': 5,
                    'has_pending_order': true,
                    'pending_order_days': 3,
                    'stock_unit': 'bag',
                  },
                  onTap: () {},
                ),
              );
            },
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.local_shipping_rounded), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('3d'), findsOneWidget);
    expect(find.text('PEND'), findsNothing);
  });

  testWidgets('activity meta shows verifier not PO id', (tester) async {
    final meta = StockRowMetrics.lastActivityMetaLine(const {
      'physical_stock_counted_by': 'krishna',
      'physical_stock_counted_at': '2026-05-30T10:00:00Z',
    });
    expect(meta, contains('Verified'));
    expect(meta, contains('krishna'));
    expect(meta, isNot(contains('PO')));
    expect(meta, isNot(contains('PUR')));
  });
}
