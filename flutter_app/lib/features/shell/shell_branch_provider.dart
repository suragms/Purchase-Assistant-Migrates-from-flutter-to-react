import 'package:flutter_riverpod/flutter_riverpod.dart';

/// IndexedStack branch indices — must match [StatefulShellRoute] order in
/// [app_router.dart] and the bottom bar in [ShellScreen].
abstract final class ShellBranch {
  static const int home = 0;
  static const int stock = 1;
  static const int reports = 2;
  static const int history = 3;
  /// Global search (replaces former Assistant tab — Assistant opens from toolbar).
  static const int search = 4;
}

/// Last-selected main shell tab. Providers defer heavy network work until the
/// matching branch is visible (see [reportsPurchasesPayloadProvider],
/// [tradePurchasesListProvider]).
final shellCurrentBranchProvider = StateProvider<int>(
  (ref) => ShellBranch.home,
);

/// Whether [branch] is the active IndexedStack tab (off-screen branches stay mounted).
bool shellBranchIsVisible(Ref ref, int branch) =>
    ref.watch(shellCurrentBranchProvider) == branch;
