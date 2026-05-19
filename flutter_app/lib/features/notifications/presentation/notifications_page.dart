import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/providers/notifications_provider.dart'
    show
        NotificationItem,
        NotificationType,
        cloudCostNotificationItemsProvider,
        dismissedPurchaseAlertIdsProvider,
        maintenanceNotificationItemsProvider,
        notificationItemFromServerRow,
        notificationsProvider,
        purchaseDueAlertItemsProvider;
import '../../../core/providers/server_notifications_provider.dart';
import '../../../core/router/navigation_ext.dart';
import '../../../core/errors/load_state_error.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/theme/theme_context_ext.dart';

class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({super.key});

  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> {
  String _filter = 'all'; // all | alerts | reminders | system
  final _textSearch = TextEditingController();

  @override
  void dispose() {
    _textSearch.dispose();
    super.dispose();
  }

  bool _matchesFilter(NotificationItem n) {
    switch (_filter) {
      case 'alerts':
        return n.type == NotificationType.priceAlert ||
            n.type == NotificationType.profitLow ||
            (n.type == NotificationType.serverInApp &&
                n.serverKind == 'low_stock');
      case 'reminders':
        return n.type == NotificationType.reminder ||
            n.type == NotificationType.purchaseDue ||
            n.type == NotificationType.purchaseOverdue ||
            n.type == NotificationType.cloudCost ||
            n.type == NotificationType.maintenance;
      case 'system':
        return n.type == NotificationType.system ||
            n.type == NotificationType.whatsapp ||
            (n.type == NotificationType.serverInApp &&
                n.serverKind != null &&
                n.serverKind != 'low_stock');
      default:
        return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final manual = ref.watch(notificationsProvider);
    final dismissed = ref.watch(dismissedPurchaseAlertIdsProvider);
    final serverAsync = ref.watch(appNotificationsListProvider);
    final serverRows = serverAsync.maybeWhen(
      data: (rows) =>
          rows.map((e) => notificationItemFromServerRow(e)).toList(),
      orElse: () => const <NotificationItem>[],
    );
    final tradeAlerts = ref
        .watch(purchaseDueAlertItemsProvider)
        .where((n) => !dismissed.contains(n.id))
        .toList();
    final cloudItems = ref.watch(cloudCostNotificationItemsProvider);
    final maintItems = ref.watch(maintenanceNotificationItemsProvider);
    final items = [...serverRows, ...cloudItems, ...maintItems, ...tradeAlerts, ...manual];
    final filtered = items.where(_matchesFilter).toList();
    final q = _textSearch.text.trim().toLowerCase();
    final visible = (q.isEmpty
            ? filtered
            : filtered
                .where((n) =>
                    '${n.title} ${n.subtitle}'.toLowerCase().contains(q))
                .toList())
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final rel = DateFormat.Hm();
    final hasUnread = visible.any((n) => !n.isRead);
    final filterEmptyButHasItems =
        items.isNotEmpty && filtered.isEmpty && q.isEmpty;

    final onSurf = Theme.of(context).colorScheme.onSurface;
    return Scaffold(
      backgroundColor: context.adaptiveScaffold,
      appBar: AppBar(
        backgroundColor: context.adaptiveAppBarBg,
        surfaceTintColor: Colors.transparent,
        title: Text('Alerts & Reminders',
            style: tt.titleLarge?.copyWith(
                fontWeight: FontWeight.w800, color: onSurf)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
          onPressed: () => context.popOrGo('/home'),
        ),
        actions: [
          if (hasUnread)
            TextButton(
              onPressed: () => _markAllVisibleRead(visible),
              child: const Text('Mark all read'),
            ),
          IconButton(
            tooltip: 'Notification settings',
            icon: Icon(Icons.tune_rounded,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            onPressed: () {
              showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                backgroundColor: context.adaptiveCard,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                builder: (ctx) => Padding(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    20,
                    20,
                    20 + MediaQuery.viewInsetsOf(ctx).bottom,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Preferences',
                          style: tt.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 12),
                      Text(
                        'Price alerts, profit drop, daily summary, and WhatsApp status toggles will be available in a future update.',
                        style: tt.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            height: 1.4),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (serverAsync.isLoading)
            const LinearProgressIndicator(minHeight: 2),
          if (serverAsync.hasError)
            Material(
              color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.35),
              child: ListTile(
                dense: true,
                leading: Icon(Icons.warning_amber_rounded,
                    color: Theme.of(context).colorScheme.error),
                title: const Text('Could not refresh server notifications'),
                subtitle: Text(
                  loadStateErrorSubtitle(serverAsync.error),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: TextField(
              controller: _textSearch,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search alerts…',
                isDense: true,
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _textSearch.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20),
                        onPressed: () {
                          _textSearch.clear();
                          setState(() {});
                        },
                      ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _FilterChip(
                    label: 'All',
                    selected: _filter == 'all',
                    onTap: () => setState(() => _filter = 'all')),
                _FilterChip(
                    label: 'Alerts',
                    selected: _filter == 'alerts',
                    onTap: () => setState(() => _filter = 'alerts')),
                _FilterChip(
                    label: 'Reminders',
                    selected: _filter == 'reminders',
                    onTap: () => setState(() => _filter = 'reminders')),
                _FilterChip(
                    label: 'System',
                    selected: _filter == 'system',
                    onTap: () => setState(() => _filter = 'system')),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(appNotificationsListProvider);
                ref.invalidate(appNotificationUnreadCountProvider);
                await ref.read(appNotificationsListProvider.future);
              },
              child: visible.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: MediaQuery.sizeOf(context).height * 0.45,
                        child: Center(
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 32),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                          Icon(
                            Icons.notifications_none_outlined,
                            size: 64,
                            color: Colors.grey.shade300,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            q.isNotEmpty
                                ? 'No matches'
                                : filterEmptyButHasItems
                                    ? 'Nothing in this tab'
                                    : 'No alerts yet',
                            textAlign: TextAlign.center,
                            style: tt.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              color: onSurf,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            q.isNotEmpty
                                ? 'Try a different search or clear the search box.'
                                : filterEmptyButHasItems
                                    ? 'Switch to All or another category — your notifications are only hidden by the current filter.'
                                    : 'Payment due alerts and reminders will appear here.',
                            textAlign: TextAlign.center,
                            style: tt.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              height: 1.35,
                            ),
                          ),
                          if (filterEmptyButHasItems) ...[
                            const SizedBox(height: 20),
                            FilledButton(
                              onPressed: () =>
                                  setState(() => _filter = 'all'),
                              child: const Text('Show all'),
                            ),
                          ],
                          if (items.isEmpty) ...[
                            const SizedBox(height: 20),
                            FilledButton.icon(
                              onPressed: () => context.push('/purchase/new'),
                              icon: const Icon(Icons.add_shopping_cart_rounded,
                                  size: 20),
                              label: const Text('Record a purchase'),
                            ),
                          ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    children: _buildGroupedNotificationTiles(
                      context: context,
                      ref: ref,
                      visible: visible,
                      rel: rel,
                      tt: tt,
                    ),
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _markAllVisibleRead(List<NotificationItem> visible) async {
    final session = ref.read(sessionProvider);
    final api = ref.read(hexaApiProvider);
    for (final n in visible) {
      if (n.isRead) continue;
      final sid = n.serverNotificationId;
      if (sid != null && sid.isNotEmpty && session != null) {
        try {
          await api.patchAppNotificationRead(
            businessId: session.primaryBusiness.id,
            notificationId: sid,
          );
        } catch (_) {}
      } else if (!n.id.startsWith('pur_')) {
        ref.read(notificationsProvider.notifier).markRead(n.id);
      }
    }
    ref.invalidate(appNotificationsListProvider);
    ref.invalidate(appNotificationUnreadCountProvider);
    if (mounted) setState(() {});
  }

  List<Widget> _buildGroupedNotificationTiles({
    required BuildContext context,
    required WidgetRef ref,
    required List<NotificationItem> visible,
    required DateFormat rel,
    required TextTheme tt,
  }) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    String? lastHeader;
    final widgets = <Widget>[];

    for (final n in visible) {
      final day = DateTime(
        n.createdAt.year,
        n.createdAt.month,
        n.createdAt.day,
      );
      final header = day == today
          ? 'Today'
          : day == yesterday
              ? 'Yesterday'
              : 'Earlier';
      if (header != lastHeader) {
        widgets.add(_NotificationDateHeader(label: header));
        lastHeader = header;
      }
      widgets.add(_notificationTile(
        context: context,
        ref: ref,
        n: n,
        rel: rel,
        tt: tt,
      ));
    }
    return widgets;
  }

  Widget _notificationTile({
    required BuildContext context,
    required WidgetRef ref,
    required NotificationItem n,
    required DateFormat rel,
    required TextTheme tt,
  }) {
    final onSurf = Theme.of(context).colorScheme.onSurface;
    final color = switch (n.type) {
                        NotificationType.priceAlert => HexaColors.warning,
                        NotificationType.profitLow => HexaColors.loss,
                        NotificationType.reminder => HexaColors.primaryMid,
                        NotificationType.whatsapp => const Color(0xFF25D366),
                        NotificationType.purchaseDue => const Color(0xFFF59E0B),
                        NotificationType.purchaseOverdue => HexaColors.loss,
                        NotificationType.cloudCost => const Color(0xFF17A8A7),
                        NotificationType.maintenance =>
                            const Color(0xFF6366F1),
                        NotificationType.serverInApp => n.serverKind == 'low_stock'
                            ? HexaColors.warning
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                        NotificationType.system => Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant,
    };
    final icon = switch (n.type) {
                        NotificationType.priceAlert =>
                          Icons.warning_amber_rounded,
                        NotificationType.profitLow =>
                          Icons.trending_down_rounded,
                        NotificationType.reminder => Icons.schedule_rounded,
                        NotificationType.whatsapp => Icons.chat_rounded,
                        NotificationType.purchaseDue => Icons.event_rounded,
                        NotificationType.purchaseOverdue =>
                            Icons.gavel_rounded,
                        NotificationType.cloudCost => Icons.cloud_outlined,
                        NotificationType.maintenance =>
                          Icons.build_circle_outlined,
                        NotificationType.serverInApp => n.serverKind == 'low_stock'
                            ? Icons.inventory_2_outlined
                            : Icons.notifications_active_outlined,
                        NotificationType.system => Icons.info_outline_rounded,
    };
    return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Material(
                          color: context.adaptiveCard,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () async {
                              final sid = n.serverNotificationId;
                              if (sid != null && sid.isNotEmpty) {
                                final session = ref.read(sessionProvider);
                                if (session != null) {
                                  try {
                                    await ref.read(hexaApiProvider).patchAppNotificationRead(
                                          businessId: session.primaryBusiness.id,
                                          notificationId: sid,
                                        );
                                    ref.invalidate(appNotificationsListProvider);
                                    ref.invalidate(appNotificationUnreadCountProvider);
                                  } catch (_) {}
                                }
                              } else if (!n.id.startsWith('pur_')) {
                                ref
                                    .read(notificationsProvider.notifier)
                                    .markRead(n.id);
                              }
                              final route = n.actionRoute;
                              if (route != null && route.isNotEmpty) {
                                if (context.mounted) context.push(route);
                              }
                            },
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Container(
                                    width: n.isRead ? 1 : 4,
                                    color: n.isRead
                                        ? Theme.of(context)
                                            .colorScheme
                                            .outlineVariant
                                        : color,
                                  ),
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.all(14),
                                      child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CircleAvatar(
                                    backgroundColor:
                                        color.withValues(alpha: 0.2),
                                    child: Icon(icon, color: color, size: 20),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(n.title,
                                            style: tt.titleSmall?.copyWith(
                                                fontWeight: FontWeight.w800,
                                                color: onSurf)),
                                        const SizedBox(height: 4),
                                        Text(n.subtitle,
                                            style: tt.bodySmall?.copyWith(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                                height: 1.35)),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(rel.format(n.createdAt),
                                          style: tt.labelSmall?.copyWith(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant)),
                                      IconButton(
                                        icon: const Icon(Icons.close_rounded,
                                            size: 18),
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                        onPressed: () async {
                                          final sid = n.serverNotificationId;
                                          if (sid != null && sid.isNotEmpty) {
                                            final session = ref.read(sessionProvider);
                                            if (session != null) {
                                              try {
                                                await ref
                                                    .read(hexaApiProvider)
                                                    .patchAppNotificationRead(
                                                      businessId:
                                                          session.primaryBusiness.id,
                                                      notificationId: sid,
                                                    );
                                                ref.invalidate(
                                                    appNotificationsListProvider);
                                                ref.invalidate(
                                                    appNotificationUnreadCountProvider);
                                              } catch (_) {}
                                            }
                                            return;
                                          }
                                          if (n.id.startsWith('pur_')) {
                                            final cur = ref.read(
                                                dismissedPurchaseAlertIdsProvider);
                                            ref
                                                    .read(
                                                        dismissedPurchaseAlertIdsProvider
                                                            .notifier)
                                                    .state =
                                                {...cur, n.id};
                                          } else {
                                            ref
                                                .read(
                                                    notificationsProvider
                                                        .notifier)
                                                .dismiss(n.id);
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
  }
}

class _NotificationDateHeader extends StatelessWidget {
  const _NotificationDateHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip(
      {required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: selected
            ? HexaColors.primaryMid
            : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Text(
              label,
              style: tt.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : cs.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
