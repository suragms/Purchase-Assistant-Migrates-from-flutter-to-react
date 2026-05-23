import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/api_degraded_provider.dart';
import '../../../../core/providers/home_dashboard_provider.dart';

/// Shown when the user appears signed in but live API data is missing (often 401).
class HomeSessionDataBanner extends ConsumerWidget {
  const HomeSessionDataBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final degraded = ref.watch(apiDegradedProvider);
    final dashState = ref.watch(homeDashboardDataProvider);
    final dash = dashState.snapshot.data;
    final stale = dashState.snapshot.stale;

    final looksEmpty = dash.purchaseCount == 0 &&
        dash.totalPurchase <= 0 &&
        dash.totalBags <= 0 &&
        dash.totalKg <= 0;

    final authHint = degraded != null &&
        (degraded.toLowerCase().contains('session') ||
            degraded.toLowerCase().contains('sign in'));

    if (!looksEmpty && !authHint) return const SizedBox.shrink();
    if (looksEmpty && !authHint && !stale && !dashState.refreshing) {
      return const SizedBox.shrink();
    }

    final message = authHint
        ? degraded
        : stale
            ? 'Showing saved data — pull to refresh when online.'
            : 'Could not load live totals — check connection and retry.';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.lock_reset_rounded, size: 20, color: Color(0xFFE65100)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
              if (authHint)
                TextButton(
                  onPressed: () => context.push('/settings'),
                  child: const Text('Settings'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
