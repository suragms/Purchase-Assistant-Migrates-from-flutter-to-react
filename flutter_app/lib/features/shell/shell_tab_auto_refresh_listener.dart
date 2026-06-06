import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/provider_api_guard.dart';
import '../../core/navigation/surface_refresh_policy.dart';
import '../../core/providers/business_aggregates_invalidation.dart';
import '../../core/providers/business_write_revision.dart';
import '../../core/providers/realtime_events_provider.dart';
import '../../core/providers/reports_provider.dart';
import '../../features/search/presentation/search_page.dart' show bustUnifiedSearchCache;
import 'shell_branch_provider.dart';

/// Refreshes the active owner shell tab after writes, tab switches, or stale data.
class ShellTabAutoRefreshListener extends ConsumerStatefulWidget {
  const ShellTabAutoRefreshListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ShellTabAutoRefreshListener> createState() =>
      _ShellTabAutoRefreshListenerState();
}

class _ShellTabAutoRefreshListenerState
    extends ConsumerState<ShellTabAutoRefreshListener> {
  final Map<int, DateTime> _lastTabRefresh = {};
  DateTime? _lastWriteRefresh;
  DateTime? _lastRemoteRefresh;
  int _lastRemoteRevision = 0;

  void _refreshBranch(int branch, {required String reason}) {
    if (!mounted || providerSkipApi(ref)) return;
    final now = DateTime.now();
    final last = _lastTabRefresh[branch];
    if (last != null &&
        now.difference(last) < kShellTabReturnMinInterval &&
        reason != 'write' &&
        reason != 'remote') {
      return;
    }
    _lastTabRefresh[branch] = now;
    switch (branch) {
      case ShellBranch.home:
        forceRefreshOwnerHomeDashboard(ref);
      case ShellBranch.stock:
        invalidateWarehouseSurfacesLight(ref);
      case ShellBranch.reports:
        markReportsPurchasesNeedsLiveFetch(ref);
        ref.invalidate(reportsPurchasesPayloadProvider);
      case ShellBranch.history:
        invalidatePurchaseListSurfacesLight(ref);
      case ShellBranch.search:
        bustUnifiedSearchCache();
    }
  }

  void _onRemoteRevision(int revision) {
    if (!mounted || providerSkipApi(ref)) return;
    if (revision <= _lastRemoteRevision) return;
    _lastRemoteRevision = revision;
    final now = DateTime.now();
    if (_lastRemoteRefresh != null &&
        now.difference(_lastRemoteRefresh!) < const Duration(seconds: 5)) {
      return;
    }
    _lastRemoteRefresh = now;
    _refreshBranch(ref.read(shellCurrentBranchProvider), reason: 'remote');
  }

  void _onWriteRevision() {
    if (!mounted || providerSkipApi(ref)) return;
    final branch = ref.read(shellCurrentBranchProvider);
    final now = DateTime.now();
    if (_lastWriteRefresh != null &&
        now.difference(_lastWriteRefresh!) < const Duration(seconds: 8)) {
      return;
    }
    _lastWriteRefresh = now;
    _refreshBranch(branch, reason: 'write');
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(shellCurrentBranchProvider, (prev, next) {
      if (prev == null || prev == next) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.invalidate(realtimeInvalidationProvider);
        if (shouldRefreshOnShellTabReturn(_lastTabRefresh[next])) {
          _refreshBranch(next, reason: 'tab');
        }
      });
    });

    ref.listen<int>(businessDataWriteRevisionProvider, (prev, next) {
      if (prev == null || next <= prev) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _onWriteRevision();
      });
    });

    ref.listen<int>(remoteBusinessDataRevisionProvider, (prev, next) {
      if (prev == null || next <= prev) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _onRemoteRevision(next);
      });
    });

    return widget.child;
  }
}
