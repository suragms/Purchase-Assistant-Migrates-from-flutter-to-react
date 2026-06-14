import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:harisree_warehouse/core/auth/session_notifier.dart';
import 'package:harisree_warehouse/core/models/session.dart';
import 'package:harisree_warehouse/core/providers/delivery_pipeline_provider.dart';
import 'package:harisree_warehouse/core/providers/home_dashboard_provider.dart';
import 'package:harisree_warehouse/core/providers/home_owner_dashboard_providers.dart';
import 'package:harisree_warehouse/core/providers/prefs_provider.dart';
import 'package:harisree_warehouse/core/providers/stock_providers.dart';
import 'package:harisree_warehouse/features/home/presentation/widgets/home_owner_dashboard_body.dart';
import 'package:harisree_warehouse/features/shell/shell_branch_provider.dart';

const _session = Session(
  accessToken: 'test',
  refreshToken: 'test',
  businesses: [
    BusinessBrief(id: 'biz-1', name: 'New Harisree', role: 'owner'),
  ],
);

void main() {
  testWidgets('HomeOwnerDashboardBody renders without section load error',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    const dash = HomeDashboardData(
      period: HomePeriod.month,
      totalPurchase: 125000,
      totalLanding: 125000,
      totalSelling: 130000,
      totalProfit: 5000,
      totalQtyAllLines: 100,
      totalKg: 500,
      totalBags: 20,
      totalBoxes: 0,
      totalTins: 0,
      purchaseCount: 12,
      categories: [],
      subcategories: [],
      itemSlices: [],
      pendingDeliveryCount: 2,
      supplierCount: 3,
      brokerCount: 1,
      receivedDeliveryCount: 5,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          sessionProvider.overrideWith(() => _FakeSessionNotifier()),
          shellCurrentBranchProvider.overrideWith((ref) => ShellBranch.home),
          homeDashboardDataProvider.overrideWith(() => _DashNotifier(dash)),
          deliveryPipelineProvider.overrideWith((ref) async => const {}),
          stockStatusCountsProvider.overrideWith((ref) async => const {
                'low': 5,
                'critical': 1,
                'out': 0,
              }),
          openingStockMissingProvider.overrideWith((ref) async => const {
                'missing_count': 0,
              }),
          homeInventorySummaryProvider.overrideWith(
            (ref) async => HomeInventorySummary.empty,
          ),
          homeRecentActivityFeedProvider.overrideWith((ref) async => const []),
        ],
        child: const MaterialApp(
          home: Scaffold(body: HomeOwnerDashboardBody()),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.textContaining('This section could not load'), findsNothing);
    expect(find.text('Purchases'), findsWidgets);
    expect(find.text('Pending delivery'), findsOneWidget);
    expect(find.text('Low stock'), findsOneWidget);
  });
}

class _FakeSessionNotifier extends SessionNotifier {
  @override
  Session? build() => _session;
}

class _DashNotifier extends HomeDashboardDataNotifier {
  _DashNotifier(this.data);

  final HomeDashboardData data;

  @override
  HomeDashboardDashState build() {
    return HomeDashboardDashState(
      snapshot: HomeDashboardPayload(data: data),
      refreshing: false,
    );
  }
}
