import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/provider_api_guard.dart';
import '../../core/navigation/surface_refresh_policy.dart';
import '../../core/providers/business_aggregates_invalidation.dart';
import '../../core/providers/business_write_revision.dart';
import '../../core/providers/delivery_pipeline_provider.dart';
import '../../core/providers/home_owner_dashboard_providers.dart';
import '../../core/providers/reports_provider.dart';
import '../../core/providers/stock_providers.dart';
import '../../features/search/presentation/search_page.dart' show bustUnifiedSearchCache;
import 'shell_branch_provider.dart';

/// Refreshes the active owner shell tab when stale or when remote users change data.
/// Local writes already call targeted invalidation helpers — do not duplicate here.
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
  DateTime? _lastRemoteRefresh;
  int _lastRemoteRevision = 0;

  void _refreshBranch(int branch, {required String reason}) {
    if (!mounted || providerSkipApi(ref)) return;
    final now = DateTime.now();
    final last = _lastTabRefresh[branch];
    if (last != null &&
        now.difference(last) < kShellTabReturnMinInterval &&
        reason != 'remote') {
      return;
    }
    switch (branch) {
      case ShellBranch.home:
        if (reason != 'remote' &&
            !shouldSoftRefreshHomeSurfaces(_lastTabRefresh[branch])) {
          return;
        }
      case ShellBranch.stock:
        final stockFetched = ref.read(stockListLastFetchedAtProvider);
        if (stockFetched != null &&
            now.difference(stockFetched) < kStockListCacheTtl) {
          if (reason != 'remote') return;
          if (ref.read(stockListRowPatchProvider).isNotEmpty) return;
        }
      case ShellBranch.reports:
        if (reason != 'remote' &&
            last != null &&
            now.difference(last) < const Duration(minutes: 3)) {
          return;
        }
      default:
        break;
    }
    _lastTabRefresh[branch] = now;
    switch (branch) {
      case ShellBranch.home:
        ref.invalidate(homeRecentActivityFeedProvider);
        ref.invalidate(homeInventorySummaryProvider);
        ref.invalidate(deliveryPipelineProvider);
        ref.invalidate(homeStockAttentionCountProvider);
      case ShellBranch.stock:
        ref.invalidate(stockListProvider);
        ref.invalidate(stockStatusCountsProvider);
        ref.invalidate(stockFilteredStatusCountsProvider);
        ref.invalidate(stockDeliveryIndicatorCountsProvider);
      case ShellBranch.reports:
        markReportsPurchasesNeedsLiveFetch(ref);
        if (ref.read(shellCurrentBranchProvider) == ShellBranch.reports) {
          ref.invalidate(reportsPurchasesPayloadProvider);
        }
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
        now.difference(_lastRemoteRefresh!) < const Duration(seconds: 8)) {
      return;
    }
    _lastRemoteRefresh = now;
    _refreshBranch(ref.read(shellCurrentBranchProvider), reason: 'remote');
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(shellCurrentBranchProvider, (prev, next) {
      if (prev == null || prev == next) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (shouldRefreshOnShellTabReturn(_lastTabRefresh[next])) {
          _refreshBranch(next, reason: 'tab');
        }
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
