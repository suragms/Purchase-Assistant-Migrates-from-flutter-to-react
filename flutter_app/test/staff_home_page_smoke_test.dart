import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:harisree_warehouse/core/providers/staff_home_providers.dart';
import 'package:harisree_warehouse/features/staff/presentation/widgets/staff_home_dashboard_widgets.dart';

void main() {
  testWidgets('StaffHomeToolsGrid renders without nullable badge crash',
      (WidgetTester tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: StaffHomeToolsGrid(
              lowCount: 2,
              focus: StaffHomeFocus.all,
            ),
          ),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();

    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Stock'), findsOneWidget);
    expect(find.text('Low stock'), findsOneWidget);
    expect(find.text('Cash buy'), findsOneWidget);
  });
}
