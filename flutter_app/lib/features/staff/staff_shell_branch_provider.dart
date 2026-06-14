import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Staff bottom-nav indices — must match [StatefulShellRoute] branch order in
/// [app_router.dart] and [StaffShellScreen].
abstract final class StaffShellBranch {
  static const int home = 0;
  static const int stock = 1;
  static const int scan = 2;
  static const int search = 3;
  static const int deliveries = 4;
  static const int tasks = 5;
}

final staffShellCurrentBranchProvider = StateProvider<int>(
  (ref) => StaffShellBranch.home,
);

/// Maps staff shell route to IndexedStack branch (deep links on web).
int? staffShellBranchIndexForPath(String path) {
  if (path.startsWith('/staff/home')) return StaffShellBranch.home;
  if (path.startsWith('/staff/stock')) return StaffShellBranch.stock;
  if (path.startsWith('/staff/scan')) return StaffShellBranch.scan;
  if (path.startsWith('/staff/search')) return StaffShellBranch.search;
  if (path.startsWith('/staff/deliveries')) return StaffShellBranch.deliveries;
  if (path.startsWith('/staff/tasks')) return StaffShellBranch.tasks;
  return null;
}

/// Whether [branch] is the active staff IndexedStack tab.
bool staffShellBranchIsVisible(dynamic ref, int branch) =>
    ref.watch(staffShellCurrentBranchProvider) == branch;
