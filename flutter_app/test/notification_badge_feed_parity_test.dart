import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/core/models/session.dart';
import 'package:harisree_warehouse/core/providers/notifications_provider.dart';

void main() {
  test('category filter all includes purchase due items', () {
    final n = NotificationItem(
      id: 'pur_due_1',
      type: NotificationType.purchaseDue,
      title: 'Payment due',
      subtitle: 'Remaining 100',
      createdAt: DateTime(2026, 5, 27),
      isRead: false,
      actionRoute: '/purchase/detail/x',
    );
    expect(
      notificationMatchesCategoryFilter(n, NotificationCategoryFilter.all),
      isTrue,
    );
    expect(
      notificationMatchesCategoryFilter(n, NotificationCategoryFilter.purchases),
      isTrue,
    );
    expect(
      notificationMatchesCategoryFilter(n, NotificationCategoryFilter.warehouse),
      isFalse,
    );
  });

  test('stock variance maps to critical filter', () {
    final n = NotificationItem(
      id: 'srv_1',
      type: NotificationType.serverInApp,
      title: 'Mismatch',
      subtitle: 'Sugar',
      createdAt: DateTime(2026, 5, 27),
      serverKind: 'stock_variance',
    );
    expect(
      notificationMatchesCategoryFilter(n, NotificationCategoryFilter.critical),
      isTrue,
    );
  });

  test('high-priority low_stock maps to critical filter', () {
    final n = NotificationItem(
      id: 'srv_2',
      type: NotificationType.serverInApp,
      title: 'Low stock',
      subtitle: 'Sugar',
      createdAt: DateTime(2026, 5, 27),
      serverKind: 'low_stock',
      priority: 'high',
    );
    expect(
      notificationCategoryForItem(n),
      NotificationCategoryFilter.critical,
    );
  });

  test('non-priority low_stock stays under warehouse filter', () {
    final n = NotificationItem(
      id: 'srv_3',
      type: NotificationType.serverInApp,
      title: 'Low stock',
      subtitle: 'Rice',
      createdAt: DateTime(2026, 5, 27),
      serverKind: 'low_stock',
      priority: 'normal',
    );
    expect(
      notificationCategoryForItem(n),
      NotificationCategoryFilter.warehouse,
    );
  });

  test('staff role hides stock variance and purchase overdue', () {
    final staffSession = Session(
      accessToken: 't',
      refreshToken: 'r',
      businesses: [
        BusinessBrief(id: 'b1', name: 'Test', role: 'staff'),
      ],
    );
    final variance = NotificationItem(
      id: 'srv_v',
      type: NotificationType.serverInApp,
      title: 'Mismatch',
      subtitle: 'Item',
      createdAt: DateTime(2026, 5, 27),
      serverKind: 'stock_variance',
    );
    final overdue = NotificationItem(
      id: 'pur_overdue_1',
      type: NotificationType.purchaseOverdue,
      title: 'Overdue',
      subtitle: 'Bill',
      createdAt: DateTime(2026, 5, 27),
    );
    final lowStock = NotificationItem(
      id: 'wh_low_stock',
      type: NotificationType.serverInApp,
      title: 'Low stock',
      subtitle: '3 low',
      createdAt: DateTime(2026, 5, 27),
      serverKind: 'low_stock',
    );
    expect(notificationVisibleForRole(variance, staffSession), isFalse);
    expect(notificationVisibleForRole(overdue, staffSession), isFalse);
    expect(notificationVisibleForRole(lowStock, staffSession), isTrue);
  });
}
