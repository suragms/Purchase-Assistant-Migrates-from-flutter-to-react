import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/shell/shell_branch_provider.dart';

/// Full-screen routes pushed above the shell — never call [goBranch] for these.
bool shellIsPushedModalPath(String path) {
  if (path.startsWith('/settings')) return true;
  if (path.startsWith('/notifications')) return true;
  if (path.startsWith('/barcode')) return true;
  if (path.startsWith('/catalog')) return true;
  if (path.startsWith('/purchase/')) return true;
  if (path.startsWith('/stock/')) return true;
  if (path.startsWith('/reports/')) return true;
  if (path.startsWith('/contacts')) return true;
  if (path.startsWith('/supplier')) return true;
  if (path.startsWith('/broker')) return true;
  if (path.startsWith('/operations/')) return true;
  if (path.startsWith('/admin')) return true;
  return false;
}

/// IndexedStack tab URLs only — not root pushes like `/catalog/item/:id/edit`.
bool shellIsPrimaryTabLocation(String path) {
  if (path == '/home' || path.startsWith('/home/')) return true;
  if (path == '/stock') return true;
  if (path == '/reports') return true;
  if (path == '/purchase') return true;
  if (path == '/search') return true;
  return false;
}

/// Maps a route path to the shell branch that should be active (stack pushes included).
int? shellBranchIndexForPath(String path) {
  final int? branch;
  if (path.startsWith('/settings')) {
    branch = null;
  } else if (path.startsWith('/notifications')) {
    branch = null;
  } else if (path.startsWith('/stock')) {
    branch = shellIsPrimaryTabLocation(path) ? ShellBranch.stock : null;
  } else if (path.startsWith('/catalog')) {
    // Catalog screens are root pushes — never auto-switch IndexedStack tab.
    branch = null;
  } else if (path.startsWith('/home')) {
    branch = ShellBranch.home;
  } else if (path.startsWith('/reports')) {
    branch = shellIsPrimaryTabLocation(path) ? ShellBranch.reports : null;
  } else if (path.startsWith('/purchase')) {
    branch = shellIsPrimaryTabLocation(path) ? ShellBranch.history : null;
  } else if (path.startsWith('/barcode')) {
    branch = null;
  } else if (path.startsWith('/search')) {
    branch = ShellBranch.search;
  } else {
    branch = null;
  }
  return branch;
}

/// Default shell location for each IndexedStack branch.
String shellLocationForBranch(int branch) => switch (branch) {
      ShellBranch.home => '/home',
      ShellBranch.stock => '/stock',
      ShellBranch.reports => '/reports',
      ShellBranch.history => '/purchase',
      ShellBranch.search => '/search',
      _ => '/home',
    };

void _applyShellTabSwitch(
  ProviderContainer container,
  BuildContext context, {
  required int branch,
  required String path,
}) {
  container.read(shellReturnBranchProvider.notifier).state =
      container.read(shellCurrentBranchProvider);
  try {
    final shell = StatefulNavigationShell.of(context);
    container.read(shellCurrentBranchProvider.notifier).state = branch;
    shell.goBranch(branch);
  } catch (_) {
    container.read(shellCurrentBranchProvider.notifier).state = branch;
  }
  context.go(path);
}

/// Records the current branch, then switches shell tab (use for Home cards → Reports/Stock).
void goShellTab(
  BuildContext context,
  WidgetRef ref, {
  required int branch,
  required String location,
}) {
  final path = location.startsWith('/') ? location : '/$location';
  _applyShellTabSwitch(
    ProviderScope.containerOf(context),
    context,
    branch: branch,
    path: path,
  );
}

/// Same as [goShellTab] for [StatelessWidget] callers without [WidgetRef].
void goShellTabFromContext(
  BuildContext context, {
  required int branch,
  required String location,
}) {
  final path = location.startsWith('/') ? location : '/$location';
  _applyShellTabSwitch(
    ProviderScope.containerOf(context),
    context,
    branch: branch,
    path: path,
  );
}

/// Pop or return to the branch recorded by [goShellTab].
void popShellTabOrGoHome(
  BuildContext context,
  WidgetRef ref, {
  required String homePath,
}) {
  final ret = ref.read(shellReturnBranchProvider);
  if (ret != null) {
    ref.read(shellReturnBranchProvider.notifier).state = null;
    goShellTab(context, ref, branch: ret, location: shellLocationForBranch(ret));
    return;
  }
  context.go(homePath);
}
