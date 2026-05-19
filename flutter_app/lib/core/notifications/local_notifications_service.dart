import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:async';

import '../config/app_config.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Daily summary at 09:00 (Asia/Kolkata when available). No-op on web.
class LocalNotificationsService {
  LocalNotificationsService._();
  static final LocalNotificationsService instance =
      LocalNotificationsService._();

  static const _dailyId = 91001;
  static const _waReportId = 9001;
  static const int _maintId0 = 92101;
  static const int _maintId1 = 92102;
  static const int _maintId2 = 92103;
  static int _purchaseDueId(String purchaseId) =>
      purchaseId.hashCode & 0x3fffffff;

  static int _purchaseMissingDetailsId(String purchaseId) =>
      (purchaseId.hashCode ^ 0xa5b4c3d2) & 0x3fffffff;

  final FlutterLocalNotificationsPlugin _p = FlutterLocalNotificationsPlugin();
  bool _inited = false;

  static final StreamController<String> _payloads =
      StreamController<String>.broadcast();

  Stream<String> get payloadStream => _payloads.stream;

  Future<void> init() async {
    if (kIsWeb) return;
    if (_inited) return;
    await _p.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
        windows: WindowsInitializationSettings(
          appName: AppConfig.appName,
          appUserModelId: 'MyPurchases.PurchaseAssistant.App',
          guid: 'f47ac10b-58cc-4372-a567-0e02b2c3d479',
        ),
      ),
      onDidReceiveNotificationResponse: (r) {
        final p = r.payload;
        if (p != null && p.trim().isNotEmpty) {
          _payloads.add(p.trim());
        }
      },
    );

    // Cold start: if the app was launched by tapping a notification, surface payload.
    try {
      final details = await _p.getNotificationAppLaunchDetails();
      final resp = details?.notificationResponse;
      final p = resp?.payload;
      if (details?.didNotificationLaunchApp == true &&
          p != null &&
          p.trim().isNotEmpty) {
        Future<void>.delayed(const Duration(milliseconds: 300), () {
          _payloads.add(p.trim());
        });
      }
    } catch (_) {}

    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidImpl = _p.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidImpl?.requestNotificationsPermission();
    }
    _inited = true;
  }

  /// iOS: request alert/badge/sound (safe to call repeatedly; OS dedupes).
  Future<void> requestIosNotificationPermission() async {
    if (kIsWeb || !_inited) return;
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    final ios = _p.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    await ios?.requestPermissions(alert: true, badge: true, sound: true);
  }

  /// Returns whether the OS allows showing scheduled local notifications.
  /// Call before [scheduleWhatsAppReport] when enabling reminders.
  Future<bool> notificationPermissionGrantedForScheduling() async {
    if (kIsWeb || !_inited) return false;
    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _p.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final enabled = await android?.areNotificationsEnabled();
      if (enabled == true) return true;
      final req = await android?.requestNotificationsPermission();
      return req == true;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final ios = _p.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      final cur = await ios?.checkPermissions();
      final ok = cur != null &&
          (cur.isEnabled ||
              cur.isAlertEnabled ||
              cur.isProvisionalEnabled);
      if (ok) return true;
      final granted = await ios?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      if (granted != true) return false;
      final after = await ios?.checkPermissions();
      return after != null &&
          (after.isEnabled ||
              after.isAlertEnabled ||
              after.isProvisionalEnabled);
    }
    // Windows / other: plugin init succeeded; treat as schedulable.
    return true;
  }

  Future<void> setOptIn(bool enabled) async {
    if (kIsWeb || !_inited) return;
    await _p.cancel(id: _dailyId);
    if (!enabled) return;

    final next = _nextNineAm();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'my_purchases_daily',
        'Daily summary',
        channelDescription: 'Reminder to review purchases and margins.',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
      iOS: DarwinNotificationDetails(),
      windows: WindowsNotificationDetails(),
    );

    await _p.zonedSchedule(
      id: _dailyId,
      scheduledDate: next,
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      title: AppConfig.appName,
      body: 'Review purchases, margins, and alerts for today.',
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  /// Schedule or cancel WhatsApp report reminders.
  /// Type: daily | weekly | monthly. Payload is always 'whatsapp_report'.
  Future<void> scheduleWhatsAppReport({
    required bool enabled,
    required String type,
    required int hour,
    required int minute,
  }) async {
    if (kIsWeb || !_inited) return;
    await _p.cancel(id: _waReportId);
    if (!enabled) return;

    final when = _nextAt(hour: hour, minute: minute);
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'wa_reports',
        'WhatsApp Reports',
        channelDescription: 'Reminders to send purchase summary to WhatsApp.',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
      iOS: DarwinNotificationDetails(),
      windows: WindowsNotificationDetails(),
    );

    final t = type.trim().toLowerCase();
    final match = switch (t) {
      'daily' => DateTimeComponents.time,
      'monthly' => DateTimeComponents.dayOfMonthAndTime,
      _ => DateTimeComponents.dayOfWeekAndTime,
    };

    await _p.zonedSchedule(
      id: _waReportId,
      scheduledDate: when,
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      title: 'WhatsApp Report',
      body: 'Tap to open WhatsApp with today’s purchase report.',
      matchDateTimeComponents: match,
      payload: 'whatsapp_report',
    );
  }

  tz.TZDateTime _nextAt({required int hour, required int minute}) {
    final loc = tz.local;
    final now = tz.TZDateTime.now(loc);
    var scheduled = tz.TZDateTime(loc, now.year, now.month, now.day, hour, minute);
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  tz.TZDateTime _nextNineAm() {
    final loc = tz.local;
    final now = tz.TZDateTime.now(loc);
    var scheduled = tz.TZDateTime(loc, now.year, now.month, now.day, 9);
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  /// One shot at 09:00 on the **due** date (from API). No-op on web.
  /// Safe to call after every save — replaces any previous schedule for this purchase id.
  Future<void> scheduleTradePurchaseDueAtNineAmIfNeeded({
    required String purchaseId,
    String? dueDateIso,
    String? humanId,
  }) async {
    if (kIsWeb || !_inited) return;
    if (dueDateIso == null || dueDateIso.isEmpty) return;
    final p = _parseYmd(dueDateIso);
    if (p == null) return;
    final id = _purchaseDueId(purchaseId);
    await _p.cancel(id: id);
    final loc = tz.local;
    var when = tz.TZDateTime(loc, p.$1, p.$2, p.$3, 9, 0);
    final now = tz.TZDateTime.now(loc);
    // If 09:00 on the due date has already passed, still schedule a one-shot
    // reminder shortly (same-day saves after 9am were previously dropped).
    if (!when.isAfter(now)) {
      final dueEnd = tz.TZDateTime(loc, p.$1, p.$2, p.$3, 23, 59, 59);
      if (now.isAfter(dueEnd)) return;
      when = now.add(const Duration(seconds: 10));
    }
    final label = (humanId != null && humanId.isNotEmpty) ? humanId : purchaseId;
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'my_purchases_due',
        'Payment due',
        channelDescription: 'Reminders for purchase payment due dates.',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
      iOS: DarwinNotificationDetails(),
      windows: WindowsNotificationDetails(),
    );
    await _p.zonedSchedule(
      id: id,
      scheduledDate: when,
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      title: 'Payment may be due',
      body: 'If settled, mark paid in History. Ref: $label',
    );
  }

  /// One-shot ~24h after save when optional header fields are still missing.
  Future<void> schedulePurchaseMissingDetailsReminder({
    required String purchaseId,
    String? humanId,
  }) async {
    if (kIsWeb || !_inited || purchaseId.isEmpty) return;
    final id = _purchaseMissingDetailsId(purchaseId);
    await _p.cancel(id: id);
    final loc = tz.local;
    final when = tz.TZDateTime.now(loc).add(const Duration(hours: 24));
    final label =
        humanId != null && humanId.isNotEmpty ? humanId : purchaseId;
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'purchase_followup',
        'Purchase follow-up',
        channelDescription:
            'Reminders when purchase header details are incomplete.',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
      iOS: DarwinNotificationDetails(),
      windows: WindowsNotificationDetails(),
    );
    await _p.zonedSchedule(
      id: id,
      scheduledDate: when,
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      title: 'Update missing purchase details',
      body: 'Ref: $label — complete broker, freight, discount, or payment terms.',
    );
  }

  Future<void> cancelPurchaseMissingDetailsReminder(String purchaseId) async {
    if (kIsWeb || !_inited || purchaseId.isEmpty) return;
    await _p.cancel(id: _purchaseMissingDetailsId(purchaseId));
  }

  (int, int, int)? _parseYmd(String s) {
    if (s.length >= 10) {
      final t = s.substring(0, 10).split('-');
      if (t.length == 3) {
        final y = int.tryParse(t[0]);
        final m = int.tryParse(t[1]);
        final d = int.tryParse(t[2]);
        if (y != null && m != null && d != null) {
          return (y, m, d);
        }
      }
    }
    final p = DateTime.tryParse(s);
    if (p == null) return null;
    return (p.year, p.month, p.day);
  }

  /// Fixed ids for maintenance — always cancel all three before rescheduling.
  Future<void> cancelMaintenanceReminders() async {
    if (kIsWeb) return;
    await _p.cancel(id: _maintId0);
    await _p.cancel(id: _maintId1);
    await _p.cancel(id: _maintId2);
  }

  /// Up to 3 notifications, 24h apart: last day 09:00, +24h, +24h. If t0 is past,
  /// roll to [now+10s, +24h, +48h] so nothing stacks in the past.
  Future<void> scheduleMaintenanceRemindersIfNeeded({
    required bool enabled,
    required bool isPaid,
    required DateTime now,
  }) async {
    if (kIsWeb || !_inited) {
      if (!kIsWeb) {
        await cancelMaintenanceReminders();
      }
      return;
    }
    await cancelMaintenanceReminders();
    if (!enabled || isPaid) return;

    final loc = tz.local;
    final nowTz = tz.TZDateTime.from(now, loc);
    final y = nowTz.year;
    final m = nowTz.month;
    final lastD = DateTime(y, m + 1, 0).day;
    var t0 = tz.TZDateTime(loc, y, m, lastD, 9, 0);
    const spacing = Duration(hours: 24);
    const catchUpStart = Duration(seconds: 10);

    tz.TZDateTime t1;
    tz.TZDateTime t2;
    if (!t0.isAfter(nowTz)) {
      // First slot in the past: roll all three to future with 24h spacing.
      final s0 = nowTz.add(catchUpStart);
      t1 = s0.add(spacing);
      t2 = t1.add(spacing);
      await _zonedScheduleMaintenance(
        _maintId0,
        s0,
        'Monthly maintenance',
        '₹2500 due — last day of month. Pay via UPI from Home.',
      );
      await _zonedScheduleMaintenance(
        _maintId1,
        t1,
        'Maintenance reminder',
        '₹2500 still due this month. Open the app to pay or mark paid.',
      );
      await _zonedScheduleMaintenance(
        _maintId2,
        t2,
        'Final maintenance reminder',
        '₹2500 before month ends. Check Home to complete payment.',
      );
    } else {
      t1 = t0.add(spacing);
      t2 = t1.add(spacing);
      await _zonedScheduleMaintenance(
        _maintId0,
        t0,
        'Monthly maintenance',
        '₹2500 due — last day of month 9:00. Pay via UPI from Home.',
      );
      await _zonedScheduleMaintenance(
        _maintId1,
        t1,
        'Maintenance reminder',
        '₹2500 still due this month. Open the app to pay or mark paid.',
      );
      await _zonedScheduleMaintenance(
        _maintId2,
        t2,
        'Final maintenance reminder',
        '₹2500 before month ends. Check Home to complete payment.',
      );
    }
  }

  static const _maintDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'maintenance_payment',
      'Maintenance payment',
      channelDescription: 'Reminders for monthly app maintenance (₹2500).',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    ),
    iOS: DarwinNotificationDetails(),
    windows: WindowsNotificationDetails(),
  );

  Future<void> _zonedScheduleMaintenance(
    int id,
    tz.TZDateTime when,
    String title,
    String body,
  ) async {
    await _p.zonedSchedule(
      id: id,
      scheduledDate: when,
      notificationDetails: _maintDetails,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      title: title,
      body: body,
    );
  }

  static const _stockAlertId = 93001;
  static const _purchaseSavedId = 93002;
  static const _staffAuthId = 93003;
  static const _offlineSyncId = 93004;

  static const _immediateDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'stock_alerts',
      'Stock & alerts',
      channelDescription: 'Purchases, stock, staff, and sync alerts.',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
    windows: WindowsNotificationDetails(),
  );

  Future<void> _showImmediate({
    required int id,
    required String title,
    required String body,
    String payload = 'notifications',
  }) async {
    if (kIsWeb || !_inited) return;
    await _p.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: _immediateDetails,
      payload: payload,
    );
  }

  /// Shown right after a purchase is saved (not the due-date reminder).
  Future<void> showPurchaseSaved({
    required String humanId,
    String? totalFormatted,
  }) async {
    final body = totalFormatted != null && totalFormatted.isNotEmpty
        ? 'Purchase $humanId saved · $totalFormatted'
        : 'Purchase $humanId saved';
    await _showImmediate(
      id: _purchaseSavedId,
      title: AppConfig.appName,
      body: body,
      payload: 'purchase_history',
    );
  }

  Future<void> showStaffSignedIn({required String businessName}) async {
    await _showImmediate(
      id: _staffAuthId,
      title: 'Staff signed in',
      body: businessName,
      payload: 'staff_home',
    );
  }

  Future<void> showStaffSignedOut({required String businessName}) async {
    await _showImmediate(
      id: _staffAuthId,
      title: 'Staff signed out',
      body: businessName,
      payload: 'staff_home',
    );
  }

  Future<void> showLowStockItem({
    required String itemName,
    required String detail,
  }) async {
    await _showImmediate(
      id: _stockAlertId,
      title: 'Low stock',
      body: '$itemName — $detail',
      payload: 'stock',
    );
  }

  /// Owner alert when a staff member records a purchase (polled from activity log).
  Future<void> showStaffPurchase({
    required String staffName,
    String? amountFormatted,
  }) async {
    final body = amountFormatted != null && amountFormatted.isNotEmpty
        ? '$staffName added a purchase of $amountFormatted'
        : '$staffName added a purchase';
    await _showImmediate(
      id: _staffAuthId + 1,
      title: AppConfig.appName,
      body: body,
      payload: 'purchase_history',
    );
  }

  Future<void> showOfflineSyncSuccess({required int count}) async {
    if (count <= 0) return;
    final body = count == 1
        ? '1 purchase synced successfully'
        : '$count purchases synced successfully';
    await _showImmediate(
      id: _offlineSyncId,
      title: AppConfig.appName,
      body: body,
      payload: 'purchase_history',
    );
  }

  /// Immediate alert (e.g. new in-app notification while app is backgrounded).
  Future<void> showStockOrInAppAlert({
    required String title,
    required String body,
    String payload = 'notifications',
  }) async {
    await _showImmediate(id: _stockAlertId, title: title, body: body, payload: payload);
  }
}
