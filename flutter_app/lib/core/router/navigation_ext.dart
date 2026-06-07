import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/shell/shell_branch_provider.dart';
import 'shell_navigation.dart';

/// Close a modal/dialog. Do **not** use [GoRouter.pop] here — on web it can
/// throw or pop the route underneath instead of the overlay.
void popOverlay<T extends Object?>(BuildContext context, [T? result]) {
  try {
    Navigator.of(context, rootNavigator: true).pop<T>(result);
  } catch (_) {}
}

/// Pop an imperative [Navigator] page (e.g. [MaterialPageRoute]) or GoRouter
/// location; [fallbackGo] when the stack is empty (deep link / refresh).
void popImperativeOrGo(
  BuildContext context, {
  required String fallbackGo,
  Object? result,
}) {
  try {
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop(result);
      return;
    }
  } catch (_) {}
  try {
    if (context.canPop()) {
      if (result != null) {
        context.pop(result);
      } else {
        context.pop();
      }
      return;
    }
  } catch (_) {}
  try {
    context.go(fallbackGo);
  } catch (_) {}
}

/// Web and deep links may leave the stack empty; [pop] then does nothing
/// without a [GoRouter] history entry. Use [popOrGo] to always leave the
/// screen (notably the system back/leading button).
extension SafeGoRouterPop on BuildContext {
  void popOrGo(String location) {
    popImperativeOrGo(this, fallbackGo: location);
  }
}

/// Push a full-screen route above the shell after the current frame.
///
/// Avoids shell [goBranch] races on web when opening catalog / purchase overlays
/// from a tab whose branch differs from the route prefix (e.g. Purchase → catalog edit).
void pushOverlayRoute(
  BuildContext context,
  String location, {
  Map<String, String> queryParameters = const {},
}) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;
    if (queryParameters.isEmpty) {
      context.push(location);
      return;
    }
    final uri = Uri(path: location, queryParameters: queryParameters);
    context.push(uri.toString());
  });
}

/// Named overlay push — prefer for catalog create / item edit routes.
void pushOverlayNamed(
  BuildContext context,
  String name, {
  Map<String, String> pathParameters = const {},
  Map<String, String> queryParameters = const {},
}) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;
    context.pushNamed(
      name,
      pathParameters: pathParameters,
      queryParameters: queryParameters,
    );
  });
}

void pushCatalogQuickAdd(
  BuildContext context, {
  Map<String, String> queryParameters = const {},
}) {
  pushOverlayNamed(
    context,
    'catalog_quick_add',
    queryParameters: queryParameters,
  );
}

void pushCatalogItemEdit(BuildContext context, String itemId) {
  final id = itemId.trim();
  if (id.isEmpty) return;
  pushOverlayNamed(
    context,
    'item_edit',
    pathParameters: {'itemId': id},
  );
}

/// Opens the purchase entry wizard (`/purchase/new`), not purchase history.
void pushPurchaseNew(
  BuildContext context, {
  Map<String, String> queryParameters = const {},
}) {
  pushOverlayNamed(
    context,
    'purchase_new',
    queryParameters: queryParameters,
  );
}

void pushLowStockDashboard(BuildContext context) =>
    pushOverlayRoute(context, '/stock/low-stock');

void pushOpeningStockSetup(BuildContext context) =>
    pushOverlayRoute(context, '/stock/opening-setup');

void pushStockReorder(BuildContext context) =>
    pushOverlayRoute(context, '/stock/reorder');

void pushStockMissingBarcodes(BuildContext context) =>
    pushOverlayRoute(context, '/stock/missing-barcodes');

void pushBarcodeScan(
  BuildContext context, {
  Map<String, String> queryParameters = const {},
}) {
  pushOverlayNamed(
    context,
    'barcode_scan',
    queryParameters: queryParameters,
  );
}

void pushCatalogItem(
  BuildContext context,
  String itemId, {
  Map<String, String> queryParameters = const {},
}) {
  final id = itemId.trim();
  if (id.isEmpty) return;
  pushOverlayRoute(
    context,
    '/catalog/item/$id',
    queryParameters: queryParameters,
  );
}

/// Smart navigation for dashboard chips, alerts, and notification action routes.
///
/// Shell tab roots use [goShellTabFromContext]; overlays use [pushOverlayRoute]
/// so the shell never replaces `/stock/low-stock` with `/stock`.
void navigateActionRoute(BuildContext context, String route) {
  final raw = route.trim();
  if (raw.isEmpty) return;
  final uri = Uri.parse(raw.startsWith('/') ? raw : '/$raw');
  final path = uri.path;
  final location = uri.hasQuery ? '$path?${uri.query}' : path;

  if (path.startsWith('/staff/')) {
    pushOverlayRoute(context, location);
    return;
  }

  if (path == '/reports' || path.startsWith('/reports/')) {
    goShellTabFromContext(
      context,
      branch: ShellBranch.reports,
      location: location,
    );
    return;
  }
  if (path == '/purchase') {
    goShellTabFromContext(
      context,
      branch: ShellBranch.history,
      location: location,
    );
    return;
  }
  if (path == '/stock') {
    goShellTabFromContext(
      context,
      branch: ShellBranch.stock,
      location: location,
    );
    return;
  }
  if (path == '/home' || path.startsWith('/home/')) {
    goShellTabFromContext(
      context,
      branch: ShellBranch.home,
      location: location,
    );
    return;
  }
  if (path == '/search') {
    goShellTabFromContext(
      context,
      branch: ShellBranch.search,
      location: location,
    );
    return;
  }

  if (path == '/purchase/new') {
    pushPurchaseNew(context, queryParameters: uri.queryParameters);
    return;
  }
  if (path == '/catalog/quick-add') {
    pushCatalogQuickAdd(context, queryParameters: uri.queryParameters);
    return;
  }

  pushOverlayRoute(context, location);
}
