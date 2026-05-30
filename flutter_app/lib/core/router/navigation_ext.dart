import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
