import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/json_coerce.dart';
import '../../../core/providers/staff_home_providers.dart';
import '../../../core/providers/stock_audit_providers.dart';
import '../../../core/theme/hexa_colors.dart';

/// Recent scans + server activity for warehouse accountability.
class BarcodeScanHistoryPage extends ConsumerWidget {
  const BarcodeScanHistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final recentAsync = ref.watch(staffRecentScansProvider);
    final kpis = ref.watch(stockAuditKpisProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Scan history')),
      body: session == null
          ? const Center(child: Text('Sign in required'))
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                kpis.when(
                  loading: () => const LinearProgressIndicator(minHeight: 2),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (k) {
                    final pending = coerceToInt(k['pending_approval_count']);
                    if (pending <= 0) return const SizedBox.shrink();
                    return Card(
                      child: ListTile(
                        leading: const Icon(
                          Icons.pending_actions,
                          color: HexaColors.brandPrimary,
                        ),
                        title: Text('$pending pending approval(s)'),
                        subtitle: const Text(
                          'Manager or owner must approve large variances',
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  'Recent on device',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 6),
                recentAsync.when(
                  loading: () => const LinearProgressIndicator(minHeight: 2),
                  error: (_, __) => const Text('Could not load recent scans'),
                  data: (recent) {
                    if (recent.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'No recent scans yet.',
                          style: TextStyle(fontSize: 13),
                        ),
                      );
                    }
                    return Column(
                      children: recent
                          .map(
                            (r) => ListTile(
                              dense: true,
                              title: Text(
                                r.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(r.code),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () {
                                if (r.id.isNotEmpty) {
                                  context.push('/stock/intelligence/${r.id}');
                                }
                              },
                            ),
                          )
                          .toList(),
                    );
                  },
                ),
              ],
            ),
    );
  }
}
