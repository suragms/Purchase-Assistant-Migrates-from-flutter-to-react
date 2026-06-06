import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/provider_api_guard.dart';
import '../../../../core/navigation/surface_refresh_policy.dart';
import '../../../../core/platform/app_foreground_provider.dart';
import '../../../../core/providers/business_aggregates_invalidation.dart';
import '../../../../core/providers/business_write_revision.dart';
import '../../../../core/providers/realtime_events_provider.dart';
import '../../../../core/providers/staff_home_providers.dart';
import '../../../../core/providers/stock_providers.dart';
import '../../../../features/search/presentation/search_page.dart' show bustUnifiedSearchCache;
import '../../staff_shell_branch_provider.dart';

/// Keeps staff shell tabs fresh for remote changes without duplicating local write storms.
class StaffShellAutoRefreshListener extends ConsumerStatefulWidget {
  const StaffShellAutoRefreshListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<StaffShellAutoRefreshListener> createState() =>
      _StaffShellAutoRefreshListenerState();
}

class _StaffShellAutoRefreshListenerState
    extends ConsumerState<StaffShellAutoRefreshListener> {
  Timer? _periodic;
  final Map<int, DateTime> _lastTabRefresh = {};
  DateTime? _lastLightRefresh;
  int _lastRealtimeTick = 0;
  int _lastRemoteRevision = 0;
  DateTime? _lastRemoteRefresh;

  @override
  void initState() {
    super.initState();
    _periodic = Timer.periodic(const Duration(minutes: 3), (_) {
      _refreshCurrentBranch(reason: 'periodic');
    });
  }

  @override
  void dispose() {
    _periodic?.cancel();
    super.dispose();
  }

  void _refreshBranch(int branch, {required String reason}) {
    if (!mounted || providerSkipApi(ref)) return;
    final now = DateTime.now();
    final last = _lastTabRefresh[branch];
    if (last != null &&
        now.difference(last) < kShellTabReturnMinInterval &&
        reason != 'realtime' &&
        reason != 'remote') {
      return;
    }
    _lastTabRefresh[branch] = now;
    switch (branch) {
      case StaffShellBranch.home:
        invalidateStaffHomeSurfacesLight(ref);
      case StaffShellBranch.stock:
        ref.invalidate(stockListProvider);
        ref.invalidate(stockStatusCountsProvider);
      case StaffShellBranch.deliveries:
        invalidateStaffDeliverySurfacesLight(ref);
      case StaffShellBranch.tasks:
        ref.invalidate(staffTodayActivityProvider);
        ref.invalidate(staffTodaySummaryProvider);
      case StaffShellBranch.search:
        bustUnifiedSearchCache();
      case StaffShellBranch.scan:
        break;
    }
  }

  void _refreshCurrentBranch({required String reason}) {
    if (!mounted || providerSkipApi(ref)) return;
    final now = DateTime.now();
    if (_lastLightRefresh != null &&
        now.difference(_lastLightRefresh!) < const Duration(seconds: 25) &&
        reason != 'tab') {
      return;
    }
    _lastLightRefresh = now;
    _refreshBranch(ref.read(staffShellCurrentBranchProvider), reason: reason);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(staffShellCurrentBranchProvider, (prev, next) {
      if (prev == null || prev == next) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (shouldRefreshOnShellTabReturn(_lastTabRefresh[next])) {
          _refreshBranch(next, reason: 'tab');
        }
      });
    });

    ref.listen<DateTime?>(appLastForegroundAtProvider, (prev, next) {
      if (next == null || next == prev) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _refreshCurrentBranch(reason: 'foreground');
      });
    });

    ref.listen<AsyncValue<RealtimeInvalidationSignal>>(
      realtimeInvalidationProvider,
      (prev, next) {
        final signal = next.valueOrNull;
        if (signal == null || signal.tick == _lastRealtimeTick) return;
        if (!signal.delivery && !signal.warehouse && !signal.notifications) {
          return;
        }
        _lastRealtimeTick = signal.tick;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _refreshCurrentBranch(reason: 'realtime');
        });
      },
    );

    ref.listen<int>(remoteBusinessDataRevisionProvider, (prev, next) {
      if (prev == null || next <= prev) return;
      if (next <= _lastRemoteRevision) return;
      _lastRemoteRevision = next;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final now = DateTime.now();
        if (_lastRemoteRefresh != null &&
            now.difference(_lastRemoteRefresh!) < const Duration(seconds: 8)) {
          return;
        }
        _lastRemoteRefresh = now;
        _refreshBranch(
          ref.read(staffShellCurrentBranchProvider),
          reason: 'remote',
        );
      });
    });

    return widget.child;
  }
}
