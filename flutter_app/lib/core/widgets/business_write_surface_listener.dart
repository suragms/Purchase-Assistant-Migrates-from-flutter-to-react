import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/business_write_event.dart';
import '../providers/business_write_revision.dart';
import '../providers/deferred_invalidation.dart' show deferVoid;

/// Listens for business writes and runs [onRefresh] (post-frame, throttled).
class BusinessWriteSurfaceListener extends ConsumerStatefulWidget {
  const BusinessWriteSurfaceListener({
    super.key,
    required this.child,
    required this.onRefresh,
    this.listenGlobalWrites = true,
    this.itemId,
    this.minRefreshGap = const Duration(seconds: 8),
  });

  final Widget child;
  final void Function(WidgetRef ref, BusinessWriteEvent event) onRefresh;
  final bool listenGlobalWrites;
  final String? itemId;
  final Duration minRefreshGap;

  @override
  ConsumerState<BusinessWriteSurfaceListener> createState() =>
      _BusinessWriteSurfaceListenerState();
}

class _BusinessWriteSurfaceListenerState
    extends ConsumerState<BusinessWriteSurfaceListener> {
  DateTime? _lastRefresh;

  bool _shouldReact(BusinessWriteEvent event) {
    final itemId = widget.itemId;
    if (itemId != null && itemId.isNotEmpty) {
      return event.affectsItem(itemId) || (widget.listenGlobalWrites && event.isGlobal);
    }
    if (!widget.listenGlobalWrites && !event.isGlobal) {
      return event.kind == 'purchase' ||
          event.kind == 'stock' ||
          event.kind == 'stock_patch' ||
          event.kind == 'aggregate';
    }
    return true;
  }

  void _maybeRefresh(BusinessWriteEvent event) {
    final now = DateTime.now();
    if (_lastRefresh != null &&
        now.difference(_lastRefresh!) < widget.minRefreshGap) {
      return;
    }
    _lastRefresh = now;
    deferVoid(() => widget.onRefresh(ref, event));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<BusinessWriteEvent>(businessWriteEventProvider, (prev, next) {
      if (next.revision <= (prev?.revision ?? -1)) return;
      if (!_shouldReact(next)) return;
      _maybeRefresh(next);
    });

    ref.listen<int>(businessDataWriteRevisionProvider, (prev, next) {
      if (prev == null || next <= prev) return;
      _maybeRefresh(BusinessWriteEvent(revision: next, kind: 'aggregate'));
    });

    return widget.child;
  }
}
