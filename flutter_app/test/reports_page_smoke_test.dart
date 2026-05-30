import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:harisree_warehouse/core/auth/session_notifier.dart';
import 'package:harisree_warehouse/core/models/session.dart';
import 'package:harisree_warehouse/core/providers/analytics_breakdown_providers.dart';
import 'package:harisree_warehouse/core/providers/home_dashboard_provider.dart';
import 'package:harisree_warehouse/core/providers/home_owner_dashboard_providers.dart';
import 'package:harisree_warehouse/core/providers/operations_providers.dart';
import 'package:harisree_warehouse/core/providers/prefs_provider.dart';
import 'package:harisree_warehouse/core/providers/reports_bi_providers.dart';
import 'package:harisree_warehouse/core/providers/reports_provider.dart';
import 'package:harisree_warehouse/features/reports/presentation/reports_page.dart';
import 'package:harisree_warehouse/features/shell/shell_branch_provider.dart';

const _session = Session(
  accessToken: 'test',
  refreshToken: 'test',
  businesses: [
    BusinessBrief(id: 'biz-1', name: 'Test Biz', role: 'owner'),
  ],
);

void main() {
  testWidgets('ReportsPage overview tab renders without layout crash',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const ReportsPage(),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          sessionProvider.overrideWith(() => _FakeSessionNotifier()),
          shellCurrentBranchProvider.overrideWith((ref) => ShellBranch.reports),
          reportsPurchasesPayloadProvider.overrideWith(
            (ref) async => ReportsPurchasePayload.empty(),
          ),
          analyticsCategoriesTableProvider.overrideWith(
            (ref) async => const [],
          ),
          analyticsTypesTableProvider.overrideWith((ref) async => const []),
          analyticsSuppliersTableProvider.overrideWith((ref) async => const []),
          reportsPeriodComparisonProvider.overrideWith((ref) async => {}),
          operationalReportsProvider.overrideWith((ref) async => {}),
          stockVariancesTodayProvider.overrideWith((ref) async => const []),
          homeDashboardDataProvider.overrideWith(
            () => _EmptyHomeDashboardNotifier(),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Reports'), findsOneWidget);
    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('Could not load the app'), findsNothing);
    expect(find.text('Reports could not load'), findsNothing);
  });

  testWidgets('Reports survives provider error without crashing',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const ReportsPage(),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          sessionProvider.overrideWith(() => _FakeSessionNotifier()),
          shellCurrentBranchProvider.overrideWith((ref) => ShellBranch.reports),
          reportsPurchasesPayloadProvider.overrideWith(
            (ref) async => throw StateError('simulated fetch crash'),
          ),
          analyticsCategoriesTableProvider.overrideWith(
            (ref) async => const [],
          ),
          analyticsTypesTableProvider.overrideWith((ref) async => const []),
          analyticsSuppliersTableProvider.overrideWith((ref) async => const []),
          reportsPeriodComparisonProvider.overrideWith((ref) async => {}),
          operationalReportsProvider.overrideWith((ref) async => {}),
          stockVariancesTodayProvider.overrideWith((ref) async => const []),
          homeDashboardDataProvider.overrideWith(
            () => _EmptyHomeDashboardNotifier(),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Reports'), findsOneWidget);
    expect(find.text('Could not load the app'), findsNothing);
    expect(find.text('Reports could not load'), findsNothing);
  });
}

class _FakeSessionNotifier extends SessionNotifier {
  @override
  Session? build() => _session;
}

class _EmptyHomeDashboardNotifier extends HomeDashboardDataNotifier {
  @override
  HomeDashboardDashState build() {
    return const HomeDashboardDashState(
      snapshot: HomeDashboardPayload(data: HomeDashboardData.empty),
      refreshing: false,
    );
  }
}
