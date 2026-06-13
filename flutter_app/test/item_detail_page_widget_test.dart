import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:harisree_warehouse/core/auth/session_notifier.dart';
import 'package:harisree_warehouse/core/models/session.dart';
import 'package:harisree_warehouse/core/providers/catalog_providers.dart';
import 'package:harisree_warehouse/core/providers/item_detail_providers.dart';
import 'package:harisree_warehouse/core/providers/prefs_provider.dart';
import 'package:harisree_warehouse/core/providers/stock_providers.dart';
import 'package:harisree_warehouse/features/catalog/presentation/item_detail_page.dart';

const _session = Session(
  accessToken: 'test',
  refreshToken: 'test',
  businesses: [
    BusinessBrief(id: 'biz-1', name: 'Test Biz', role: 'owner'),
  ],
);

const _itemId = '11111111-1111-1111-1111-111111111111';

final _bundle = ItemDetailBundle(
  catalogItem: {
    'id': _itemId,
    'name': 'SUGAR 50 KG',
    'item_code': 'ITM-0001',
    'category_name': 'Essentials',
    'type_name': 'SUGAR',
  },
  stockDetail: {
    'stock_unit': 'bag',
    'current_stock': 1200,
    'physical_stock_qty': 1200,
    'period_purchased_qty': 0,
    'reorder_level': 100,
    'needs_verification': false,
    'category_name': 'Essentials',
    'subcategory_name': 'SUGAR',
  },
  activity: {},
  tradePurchases: const [],
);

void main() {
  testWidgets('ItemDetailPage mobile overview renders without layout errors',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const ItemDetailPage(itemId: _itemId),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          sessionProvider.overrideWith(() => _FakeSessionNotifier()),
          catalogItemDetailProvider(_itemId).overrideWith(
            (ref) async => _bundle.catalogItem,
          ),
          stockItemDetailProvider(_itemId).overrideWith(
            (ref) async => _bundle.stockDetail,
          ),
          stockItemIntelligenceProvider(_itemId).overrideWith((ref) async => {}),
          stockItemAuditProvider(_itemId).overrideWith((ref) async => []),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('SUGAR 50 KG'), findsOneWidget);
    expect(find.textContaining('could not load', findRichText: true), findsNothing);
    expect(find.text('Stock summary'), findsOneWidget);
  });
}

class _FakeSessionNotifier extends SessionNotifier {
  @override
  Session? build() => _session;
}
