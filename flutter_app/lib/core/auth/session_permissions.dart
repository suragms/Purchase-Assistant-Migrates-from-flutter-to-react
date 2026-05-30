import '../models/session.dart';

/// Mirrors backend [ROLE_DEFAULTS] in `app/services/permissions.py`.
const _allTrue = {
  'stock_edit': true,
  'purchase_create': true,
  'purchase_edit': true,
  'barcode_print': true,
  'reports_access': true,
  'export_access': true,
  'user_manage': true,
  'delete_access': true,
  'analytics_access': true,
};

Map<String, bool> effectivePermissionsForRole(String role) {
  final r = role.toLowerCase();
  if (r == 'owner' || r == 'admin' || r == 'super_admin') {
    return Map<String, bool>.from(_allTrue);
  }
  if (r == 'manager') {
    return {
      'stock_edit': true,
      'purchase_create': true,
      'purchase_edit': true,
      'reports_access': true,
      'barcode_print': true,
      'export_access': true,
      'user_manage': false,
      'delete_access': false,
      'analytics_access': true,
    };
  }
  return {
    'stock_edit': true,
    'purchase_create': true,
    'purchase_edit': false,
    'reports_access': false,
    'barcode_print': true,
    'export_access': false,
    'user_manage': false,
    'delete_access': false,
    'analytics_access': false,
  };
}

Map<String, bool> sessionPermissions(Session session) {
  if (session.isSuperAdmin) return Map<String, bool>.from(_allTrue);
  final fromApi = session.primaryBusiness.permissions;
  if (fromApi != null && fromApi.isNotEmpty) {
    final base = effectivePermissionsForRole(session.primaryBusiness.role);
    for (final e in fromApi.entries) {
      base[e.key] = e.value;
    }
    return base;
  }
  return effectivePermissionsForRole(session.primaryBusiness.role);
}

bool sessionCanStockEdit(Session session) =>
    sessionPermissions(session)['stock_edit'] == true;

bool sessionCanBarcodePrint(Session session) =>
    sessionPermissions(session)['barcode_print'] == true;

/// Scan/view allowed; assign barcode, create item, update stock blocked.
bool sessionIsStockReadOnly(Session session) => !sessionCanStockEdit(session);
