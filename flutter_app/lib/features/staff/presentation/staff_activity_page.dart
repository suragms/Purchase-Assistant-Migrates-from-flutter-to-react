import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/router/navigation_ext.dart';
import '../../../core/widgets/hexa_error_card.dart';
import '../../../core/widgets/list_skeleton.dart';

String _staffActivityLabel(String actionType) {
  switch (actionType.toUpperCase()) {
    case 'STAFF_LOGIN':
      return 'Signed in';
    case 'STAFF_LOGOUT':
      return 'Signed out';
    case 'PURCHASE_CREATE':
      return 'Purchase saved';
    case 'SCAN':
    case 'BARCODE_SCAN':
      return 'Barcode scan';
    default:
      return actionType.replaceAll('_', ' ');
  }
}

String _timeAgo(DateTime at) {
  final d = DateTime.now().difference(at);
  if (d.inSeconds < 60) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  if (d.inDays < 7) return '${d.inDays}d ago';
  return DateFormat.MMMd().format(at);
}

final _staffActivityPeriodProvider = StateProvider<String>((_) => 'today');

final staffActivityLogProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final session = ref.watch(sessionProvider);
  final period = ref.watch(_staffActivityPeriodProvider);
  if (session == null) return [];
  return ref.read(hexaApiProvider).listActivityLog(
        businessId: session.primaryBusiness.id,
        period: period,
      );
});

/// Staff: recent actions (scans, stock updates, etc.) from `/activity-log`.
class StaffActivityPage extends ConsumerWidget {
  const StaffActivityPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tt = Theme.of(context).textTheme;
    final period = ref.watch(_staffActivityPeriodProvider);
    final async = ref.watch(staffActivityLogProvider);
    final onSurf = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      appBar: AppBar(
        title: Text('My activity',
            style: tt.titleLarge?.copyWith(
                fontWeight: FontWeight.w800, color: onSurf)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.popOrGo('/staff/home'),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: HexaDsLayout.pageGutter,
          vertical: HexaDsLayout.sectionGap,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'today', label: Text('Today')),
                ButtonSegment(value: 'week', label: Text('Week')),
                ButtonSegment(value: 'month', label: Text('Month')),
              ],
              selected: {period},
              onSelectionChanged: (s) {
                ref.read(_staffActivityPeriodProvider.notifier).state =
                    s.first;
              },
            ),
            const SizedBox(height: 12),
            Expanded(
              child: async.when(
                loading: () => const ListSkeleton(rowCount: 10),
                error: (e, _) => HexaErrorCard.fromError(
                  error: e,
                  title: 'Could not load activity',
                  onRetry: () => ref.invalidate(staffActivityLogProvider),
                ),
                data: (rows) {
                  if (rows.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.history_rounded,
                            size: 48,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No activity in this period',
                            style: tt.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: onSurf,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Scans, stock updates, and purchases appear here.',
                            textAlign: TextAlign.center,
                            style: tt.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  final fmt = DateFormat.MMMd().add_Hm();
                  return ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final r = rows[i];
                      final actionRaw = r['action_type']?.toString() ?? '';
                      final action = _staffActivityLabel(actionRaw);
                      final item = r['item_name']?.toString();
                      DateTime when;
                      try {
                        when = DateTime.parse(
                            r['created_at']?.toString() ?? '');
                      } catch (_) {
                        when = DateTime.now();
                      }
                      final local = when.toLocal();
                      return ListTile(
                        leading: CircleAvatar(
                          radius: 18,
                          backgroundColor: HexaColors.brandPrimary
                              .withValues(alpha: 0.12),
                          child: Icon(
                            actionRaw.toUpperCase().contains('PURCHASE')
                                ? Icons.shopping_cart_outlined
                                : Icons.history_rounded,
                            size: 18,
                            color: HexaColors.brandPrimary,
                          ),
                        ),
                        title: Text(
                          action,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          item != null && item.isNotEmpty ? item : '',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              _timeAgo(local),
                              style: tt.labelSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              fmt.format(local),
                              style: tt.labelSmall?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
