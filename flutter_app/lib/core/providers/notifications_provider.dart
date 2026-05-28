import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../models/trade_purchase_models.dart';

import '../auth/session_notifier.dart';
import '../models/session.dart';
import 'server_notifications_provider.dart';
import 'staff_home_providers.dart';
import 'stock_providers.dart';
import 'trade_purchases_provider.dart';

enum NotificationType {
  priceAlert,
  profitLow,
  reminder,
  system,
  whatsapp,
  purchaseDue,
  purchaseOverdue,
  serverInApp,
}

/// UI filter tabs for the notifications center.
enum NotificationCategoryFilter {
  all,
  critical,
  warehouse,
  purchases,
  staff,
  system,
}

extension NotificationCategoryFilterX on NotificationCategoryFilter {
  String get wireValue => switch (this) {
        NotificationCategoryFilter.all => 'all',
        NotificationCategoryFilter.critical => 'critical',
        NotificationCategoryFilter.warehouse => 'warehouse',
        NotificationCategoryFilter.purchases => 'purchases',
        NotificationCategoryFilter.staff => 'staff',
        NotificationCategoryFilter.system => 'system',
      };

  static NotificationCategoryFilter? fromWire(String? v) {
    switch (v) {
      case 'all':
        return NotificationCategoryFilter.all;
      case 'critical':
        return NotificationCategoryFilter.critical;
      case 'warehouse':
        return NotificationCategoryFilter.warehouse;
      case 'purchases':
      case 'purchase':
        return NotificationCategoryFilter.purchases;
      case 'staff':
        return NotificationCategoryFilter.staff;
      case 'system':
        return NotificationCategoryFilter.system;
      default:
        return null;
    }
  }
}

bool notificationMatchesCategoryFilter(
  NotificationItem n,
  NotificationCategoryFilter filter,
) {
  if (filter == NotificationCategoryFilter.all) return true;
  final cat = notificationCategoryForItem(n);
  return cat == filter;
}

NotificationCategoryFilter notificationCategoryForItem(NotificationItem n) {
  final kind = n.serverKind ?? '';
  if (kind == 'stock_variance' ||
      kind == 'stock_mismatch' ||
      kind == 'export_failed' ||
      kind == 'sync_failed' ||
      kind == 'approval_required' ||
      n.type == NotificationType.purchaseOverdue) {
    return NotificationCategoryFilter.critical;
  }
  if (n.type == NotificationType.purchaseDue ||
      n.type == NotificationType.purchaseOverdue ||
      (n.actionRoute?.startsWith('/purchase') ?? false)) {
    return NotificationCategoryFilter.purchases;
  }
  if (n.id.startsWith('wh_pending_delivery') ||
      kind == 'staff_action' ||
      kind == 'stock_correction') {
    return NotificationCategoryFilter.staff;
  }
  if ((kind == 'low_stock' || kind == 'missing_barcode') &&
      (n.priority == 'high' || n.priority == 'critical')) {
    return NotificationCategoryFilter.critical;
  }
  if (n.type == NotificationType.priceAlert ||
      n.type == NotificationType.profitLow ||
      kind == 'low_stock' ||
      kind == 'supplier_delayed' ||
      kind == 'missing_barcode' ||
      kind == 'missing_code' ||
      kind == 'opening_stock_pending' ||
      n.id.startsWith('wh_')) {
    return NotificationCategoryFilter.warehouse;
  }
  if (n.type == NotificationType.system ||
      n.type == NotificationType.reminder ||
      n.type == NotificationType.whatsapp ||
      kind == 'delivery_received' ||
      kind == 'duplicate_item') {
    return NotificationCategoryFilter.system;
  }
  if (n.type == NotificationType.serverInApp) {
    if (kind == 'delivery_pending' || kind == 'payment_due') {
      return NotificationCategoryFilter.purchases;
    }
    return NotificationCategoryFilter.system;
  }
  return NotificationCategoryFilter.system;
}

class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.createdAt,
    this.isRead = false,
    this.actionRoute,
    this.serverNotificationId,
    this.serverKind,
    this.priority,
    this.category,
  });

  final String id;
  final NotificationType type;
  final String title;
  final String subtitle;
  final DateTime createdAt;
  final bool isRead;
  final String? actionRoute;
  /// When set, row is persisted on the API (`PATCH …/notifications/{id}`).
  final String? serverNotificationId;
  /// API `kind` when [type] is [NotificationType.serverInApp].
  final String? serverKind;
  final String? priority;
  final String? category;
}

class NotificationsNotifier extends StateNotifier<List<NotificationItem>> {
  NotificationsNotifier() : super(_seed);

  static final _seed = <NotificationItem>[
    NotificationItem(
      id: 'welcome',
      type: NotificationType.system,
      title: 'Welcome to ${AppConfig.appName}',
      subtitle:
          'Alerts for price spikes, low margins, and reminders will appear here.',
      createdAt: DateTime.now().subtract(const Duration(minutes: 2)),
      actionRoute: '/home',
    ),
  ];

  int get unreadCount => state.where((e) => !e.isRead).length;

  void markRead(String id) {
    state = [
      for (final n in state)
        if (n.id == id)
          NotificationItem(
            id: n.id,
            type: n.type,
            title: n.title,
            subtitle: n.subtitle,
            createdAt: n.createdAt,
            isRead: true,
            actionRoute: n.actionRoute,
            serverNotificationId: n.serverNotificationId,
            serverKind: n.serverKind,
            priority: n.priority,
            category: n.category,
          )
        else
          n,
    ];
  }

  void dismiss(String id) {
    state = state.where((n) => n.id != id).toList();
  }

  void addPriceSpikeAlert({required String itemSample}) {
    final id = 'spike_${DateTime.now().millisecondsSinceEpoch}';
    state = [
      NotificationItem(
        id: id,
        type: NotificationType.priceAlert,
        title: 'Price spike',
        subtitle:
            '$itemSample — landing 15%+ above recent average. Verify before next buy.',
        createdAt: DateTime.now(),
        actionRoute: '/purchase',
      ),
      ...state,
    ];
  }
}

final notificationsProvider =
    StateNotifierProvider<NotificationsNotifier, List<NotificationItem>>((ref) {
  return NotificationsNotifier();
});

/// Client-dismissed synthetic warehouse alerts (`wh_*` ids).
final warehouseAlertReadIdsProvider = StateProvider<Set<String>>((ref) => {});

DateTime warehouseAlertStableCreatedAt(String alertId) {
  final day = DateTime.now();
  final base = DateTime(day.year, day.month, day.day);
  return base.add(Duration(minutes: alertId.hashCode.abs() % 720));
}

/// Role-based visibility for notification feed (see NOTIFICATIONS_SYSTEM_AUDIT.md).
bool notificationVisibleForRole(NotificationItem n, Session session) {
  final role = session.primaryBusiness.role.toLowerCase();
  if (role != 'staff') return true;

  if (n.id.startsWith('pur_')) return false;
  if (n.type == NotificationType.purchaseDue ||
      n.type == NotificationType.purchaseOverdue) {
    return false;
  }

  final kind = n.serverKind ?? '';
  if (kind == 'stock_variance' || kind == 'stock_mismatch') return false;
  if (kind == 'payment_due' ||
      kind == 'purchase_overdue' ||
      kind == 'approval_required') {
    return false;
  }
  if (n.actionRoute?.startsWith('/purchase') == true &&
      kind != 'delivery_pending' &&
      kind != 'delivery_received') {
    return false;
  }
  return true;
}

/// Single feed for bell badge + notifications page (avoids count/list mismatch).
final mergedNotificationFeedProvider =
    Provider.autoDispose<List<NotificationItem>>((ref) {
  final link = ref.keepAlive();
  final timer = Timer(const Duration(minutes: 2), link.close);
  ref.onDispose(timer.cancel);
  final manual = ref.watch(notificationsProvider);
  final dismissed = ref.watch(dismissedPurchaseAlertIdsProvider);
  final session = ref.watch(sessionProvider);
  final isStaff =
      session != null && session.primaryBusiness.role.toLowerCase() == 'staff';
  final serverRows = ref.watch(appNotificationsListProvider).maybeWhen(
        data: (rows) {
          final list = <NotificationItem>[];
          for (final e in rows) {
            final n = notificationItemFromServerRow(e);
            if (session == null || notificationVisibleForRole(n, session)) {
              list.add(n);
            }
          }
          return list;
        },
        orElse: () => const <NotificationItem>[],
      );
  final tradeAlerts = isStaff
      ? const <NotificationItem>[]
      : ref
          .watch(purchaseDueAlertItemsProvider)
          .where((n) => !dismissed.contains(n.id))
          .toList();
  final warehouse = ref.watch(warehouseAlertNotificationItemsProvider);
  final serverKinds =
      serverRows.map((e) => e.serverKind).whereType<String>().toSet();
  final byId = <String, NotificationItem>{};
  for (final n in [
    ...serverRows,
    ...warehouse.where((w) {
      if (w.id == 'wh_low_stock' && serverKinds.contains('low_stock')) {
        return false;
      }
      if (w.id == 'wh_missing_barcode' &&
          serverKinds.contains('missing_barcode')) {
        return false;
      }
      if (w.id == 'wh_missing_code' && serverKinds.contains('missing_code')) {
        return false;
      }
      if (w.id == 'wh_opening_stock' &&
          serverKinds.contains('opening_stock_pending')) {
        return false;
      }
      return true;
    }),
    ...tradeAlerts,
    ...manual,
  ]) {
    byId[n.id] = n;
  }
  final list = byId.values.toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return list;
});

/// Badge count — always derived from the merged feed (same source as the list).
final notificationsUnreadCountProvider = Provider<int>((ref) {
  return ref
      .watch(mergedNotificationFeedProvider)
      .where((e) => !e.isRead)
      .length;
});

/// Stock / delivery rows shown in Alerts (matches staff home attention cards).
final warehouseAlertNotificationItemsProvider =
    Provider.autoDispose<List<NotificationItem>>((ref) {
  final link = ref.keepAlive();
  final timer = Timer(const Duration(minutes: 2), link.close);
  ref.onDispose(timer.cancel);
  final session = ref.watch(sessionProvider);
  if (session == null) return const [];
  final isStaff =
      session.primaryBusiness.role.toLowerCase() == 'staff';
  final readIds = ref.watch(warehouseAlertReadIdsProvider);
  final out = <NotificationItem>[];
  final counts = ref.watch(stockStatusCountsProvider).valueOrNull;
  if (counts != null) {
    final low = (counts['low'] as num?)?.toInt() ?? 0;
    final outN = (counts['out'] as num?)?.toInt() ?? 0;
    final missingBc = (counts['missing_barcode'] as num?)?.toInt() ?? 0;
    final missingCode = (counts['missing_item_code'] as num?)?.toInt() ?? 0;
    if (low + outN > 0) {
      const id = 'wh_low_stock';
      out.add(NotificationItem(
        id: id,
        type: NotificationType.serverInApp,
        title: 'Low / out of stock',
        subtitle: '$low low · $outN out — open stock list to update',
        createdAt: warehouseAlertStableCreatedAt(id),
        isRead: readIds.contains(id),
        actionRoute: isStaff ? '/staff/low-stock' : '/stock/low-stock',
        serverKind: 'low_stock',
      ));
    }
    if (missingBc > 0) {
      const id = 'wh_missing_barcode';
      out.add(NotificationItem(
        id: id,
        type: NotificationType.serverInApp,
        title: 'Missing barcodes',
        subtitle: '$missingBc items need labels before bulk print',
        createdAt: warehouseAlertStableCreatedAt(id),
        isRead: readIds.contains(id),
        actionRoute: '/stock/missing-barcodes',
        serverKind: 'missing_barcode',
      ));
    }
    if (missingCode > 0) {
      const id = 'wh_missing_code';
      out.add(NotificationItem(
        id: id,
        type: NotificationType.serverInApp,
        title: 'Missing item codes',
        subtitle: '$missingCode catalog rows without item code',
        createdAt: warehouseAlertStableCreatedAt(id),
        isRead: readIds.contains(id),
        actionRoute: isStaff ? '/staff/stock' : '/stock',
        serverKind: 'missing_code',
      ));
    }
  }
  final opening = ref.watch(openingStockMissingProvider).valueOrNull;
  final openingN = (opening?['missing_count'] as num?)?.toInt() ?? 0;
  if (openingN > 0) {
    const id = 'wh_opening_stock';
    out.add(NotificationItem(
      id: id,
      type: NotificationType.serverInApp,
      title: 'Opening stock',
      subtitle: '$openingN items need initial stock setup',
      createdAt: warehouseAlertStableCreatedAt(id),
      isRead: readIds.contains(id),
      actionRoute: '/stock/opening-setup',
      serverKind: 'opening_stock_pending',
    ));
  }
  if (isStaff) {
    final pending = ref.watch(staffPendingDeliveriesProvider).valueOrNull ?? [];
    if (pending.isNotEmpty) {
      final first = pending.first.supplierName?.trim();
      final sub = first != null && first.isNotEmpty
          ? (pending.length == 1
              ? 'From $first — receive at warehouse'
              : 'From $first + ${pending.length - 1} more')
          : '${pending.length} trucks waiting';
      const id = 'wh_pending_delivery';
      out.add(NotificationItem(
        id: id,
        type: NotificationType.reminder,
        title: 'Pending deliveries',
        subtitle: sub,
        createdAt: pending.first.purchaseDate,
        isRead: readIds.contains(id),
        actionRoute: '/staff/receive',
      ));
    }
  }
  return out;
});

/// PUR bills that need attention (unpaid with due date approaching or past).
final purchaseDueAlertItemsProvider =
    Provider<List<NotificationItem>>((ref) {
  final async = ref.watch(tradePurchasesForAlertsProvider);
  return async.maybeWhen(
    data: (rows) {
      final list = <TradePurchase>[];
      for (final row in rows) {
        try {
          list.add(TradePurchase.fromJson(Map<String, dynamic>.from(row)));
        } catch (_) {}
      }
      final out = <NotificationItem>[];
      final today0 = _day0(DateTime.now());
      for (final p in list) {
        if (!_needsPayment(p)) continue;
        final st = p.statusEnum;
        final eff = _effectiveDue(p);
        if (eff != null) {
          if (eff.isBefore(today0)) {
            out.add(NotificationItem(
              id: 'pur_overdue_${p.id}',
              type: NotificationType.purchaseOverdue,
              title: 'Overdue: ${p.humanId}',
              subtitle:
                  '${p.supplierName ?? "—"} · remaining ${_fmtMoney(p.remaining)} (due ${eff.year}-${eff.month.toString().padLeft(2, "0")}-${eff.day.toString().padLeft(2, "0")})',
              createdAt: p.dueDate ?? p.purchaseDate,
              isRead: false,
              actionRoute: '/purchase/detail/${p.id}',
            ));
            continue;
          }
          final days = eff.difference(today0).inDays;
          if (days >= 0 && days <= 5) {
            out.add(NotificationItem(
              id: 'pur_due_${p.id}',
              type: NotificationType.purchaseDue,
              title: 'Payment due: ${p.humanId}',
              subtitle:
                  'Due ${eff.year}-${eff.month.toString().padLeft(2, "0")}-${eff.day.toString().padLeft(2, "0")} · ${_fmtMoney(p.remaining)} left',
              createdAt: eff,
              isRead: false,
              actionRoute: '/purchase/detail/${p.id}',
            ));
            continue;
          }
        }
        if (st == PurchaseStatus.overdue) {
          out.add(NotificationItem(
            id: 'pur_overdue_${p.id}',
            type: NotificationType.purchaseOverdue,
            title: 'Overdue: ${p.humanId}',
            subtitle:
                '${p.supplierName ?? "—"} · remaining ${_fmtMoney(p.remaining)}',
            createdAt: p.dueDate ?? p.purchaseDate,
            isRead: false,
            actionRoute: '/purchase/detail/${p.id}',
          ));
        } else if (st == PurchaseStatus.dueSoon) {
          final due = p.dueDate;
          out.add(NotificationItem(
            id: 'pur_due_${p.id}',
            type: NotificationType.purchaseDue,
            title: 'Payment due: ${p.humanId}',
            subtitle: due != null
                ? 'Due ${due.year}-${due.month.toString().padLeft(2, "0")}-${due.day.toString().padLeft(2, "0")} · ${_fmtMoney(p.remaining)} left'
                : 'Remaining ${_fmtMoney(p.remaining)}',
            createdAt: due ?? p.purchaseDate,
            isRead: false,
            actionRoute: '/purchase/detail/${p.id}',
          ));
        }
      }
      out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return out;
    },
    orElse: () => const [],
  );
});

String _fmtMoney(double n) {
  if (n == n.roundToDouble()) {
    return n.round().toString();
  }
  return n.toStringAsFixed(0);
}

DateTime _day0(DateTime d) => DateTime(d.year, d.month, d.day);

/// Server [dueDate] or `purchaseDate + paymentDays` (local calendar).
DateTime? _effectiveDue(TradePurchase p) {
  if (p.dueDate != null) {
    return _day0(p.dueDate!);
  }
  final n = p.paymentDays;
  if (n == null || n < 0) return null;
  final pd = p.purchaseDate;
  return _day0(pd).add(Duration(days: n));
}

bool _needsPayment(TradePurchase p) {
  if (p.remaining <= 0.01) return false;
  final st = p.statusEnum;
  if (st == PurchaseStatus.paid || st == PurchaseStatus.cancelled) {
    return false;
  }
  return true;
}

/// Client-dismissed purchase-driven alerts (IDs from [purchaseDueAlertItemsProvider]).
final dismissedPurchaseAlertIdsProvider =
    StateProvider<Set<String>>((ref) => {});

final purchaseActionAlertCountProvider = Provider<int>((ref) {
  final all = ref.watch(purchaseDueAlertItemsProvider);
  final dis = ref.watch(dismissedPurchaseAlertIdsProvider);
  return all.where((n) => !dis.contains(n.id)).length;
});

NotificationItem notificationItemFromServerRow(Map<String, dynamic> row) {
  final sid = row['id']?.toString() ?? '';
  final kind = row['kind']?.toString() ?? '';
  final readAt = row['read_at'];
  final isRead = readAt != null;
  DateTime created;
  try {
    created = DateTime.parse(row['created_at']?.toString() ?? '');
  } catch (_) {
    created = DateTime.now();
  }
  final title = row['title']?.toString() ?? 'Notice';
  final body = row['body']?.toString() ?? '';
  var route = row['action_route']?.toString();
  if (route == null || route.isEmpty) {
    if (kind == 'low_stock' || kind == 'stock_variance') {
      final payload = row['payload'];
      if (payload is Map) {
        final iid = payload['item_id']?.toString();
        if (iid != null && iid.isNotEmpty) {
          route = '/catalog/item/$iid';
        }
      }
    } else if (kind == 'delivery_pending' ||
        kind == 'delivery_received' ||
        kind == 'payment_due') {
      final pid = row['related_purchase_id']?.toString();
      if (pid != null && pid.isNotEmpty) {
        route = '/purchase/detail/$pid';
      }
    }
  }
  final actor = row['triggered_by_name']?.toString();
  final subtitle = actor != null && actor.isNotEmpty ? '$body\nBy: $actor' : body;
  return NotificationItem(
    id: 'srv_$sid',
    type: NotificationType.serverInApp,
    title: title,
    subtitle: subtitle.trim(),
    createdAt: created,
    isRead: isRead,
    actionRoute: route,
    serverNotificationId: sid.isEmpty ? null : sid,
    serverKind: kind.isEmpty ? null : kind,
    priority: row['priority']?.toString(),
    category: row['category']?.toString(),
  );
}
