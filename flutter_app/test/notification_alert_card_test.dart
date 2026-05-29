import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/core/providers/notifications_provider.dart';
import 'package:harisree_warehouse/features/notifications/presentation/widgets/notification_alert_card.dart';

void main() {
  testWidgets('NotificationAlertCard shows title and priority bar', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NotificationAlertCard(
            item: NotificationItem(
              id: '1',
              type: NotificationType.serverInApp,
              title: 'Low stock: Rice',
              subtitle: '5 bags left',
              createdAt: _t,
              priority: 'high',
              serverKind: 'low_stock',
            ),
            timeLabel: '5m ago',
          ),
        ),
      ),
    );
    expect(find.text('Low stock: Rice'), findsOneWidget);
    expect(find.text('5m ago'), findsOneWidget);
  });

  testWidgets('NotificationAlertCard renders with height inside ListView',
      (tester) async {
    final item = NotificationItem(
      id: 'wh_low_stock',
      type: NotificationType.serverInApp,
      title: 'Low / out of stock',
      subtitle: '3 low · 2 out',
      createdAt: _t,
      priority: 'high',
      serverKind: 'low_stock',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              NotificationAlertCard(
                item: item,
                timeLabel: '5m ago',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Low / out of stock'), findsOneWidget);
    final cardFinder = find.byType(NotificationAlertCard);
    expect(cardFinder, findsOneWidget);
    expect(tester.getSize(cardFinder).height, greaterThan(48));
  });
}

final _t = DateTime(2026, 5, 27, 12, 0);
