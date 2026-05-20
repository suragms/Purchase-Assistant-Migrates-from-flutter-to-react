import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session_notifier.dart';
import '../providers/staff_home_providers.dart';
import '../router/post_auth_route.dart' show sessionIsStaff;
import '../utils/currency_utils.dart';

/// Posts staff actions to `/activity-log` (login, purchases, stock, etc.).
class StaffActivityLogger {
  static Future<void> log(
    dynamic ref, {
    required String actionType,
    String? itemId,
    String? itemName,
    Map<String, dynamic>? details,
  }) async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      await ref.read(hexaApiProvider).postActivityLog(
            businessId: session.primaryBusiness.id,
            actionType: actionType,
            itemId: itemId,
            itemName: itemName,
            details: details,
          );
      ref.invalidate(staffTodayActivityProvider);
    } catch (_) {}
  }

  static Future<void> logStaffLogin(dynamic ref) async {
    final session = ref.read(sessionProvider);
    if (session == null || !sessionIsStaff(session)) return;
    await log(ref, actionType: 'STAFF_LOGIN');
  }

  static Future<void> logStaffLogout(dynamic ref) async {
    final session = ref.read(sessionProvider);
    if (session == null || !sessionIsStaff(session)) return;
    await log(ref, actionType: 'STAFF_LOGOUT');
  }

  static Future<void> logPurchase(dynamic ref, Map<String, dynamic> saved) async {
    final session = ref.read(sessionProvider);
    if (session == null || !sessionIsStaff(session)) return;
    final hid = saved['human_id']?.toString();
    final amount = saved['total_amount'] ?? saved['net_amount'];
    String? totalFormatted;
    if (amount != null) {
      totalFormatted = formatRupee(decDouble(amount));
    }
    await log(
      ref,
      actionType: 'PURCHASE_CREATE',
      details: {
        if (hid != null && hid.isNotEmpty) 'human_id': hid,
        if (totalFormatted != null) 'total_formatted': totalFormatted,
        'purchase_id': saved['id']?.toString(),
      },
    );
  }
}
