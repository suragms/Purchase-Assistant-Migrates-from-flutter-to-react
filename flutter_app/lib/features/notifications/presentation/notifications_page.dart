import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/providers/notifications_provider.dart'
    show
        NotificationCategoryFilter,
        NotificationItem,
        dismissedPurchaseAlertIdsProvider,
        notificationMatchesCategoryFilter,
        notificationsProvider,
        warehouseAlertReadIdsProvider;
import '../../../core/providers/notification_center_provider.dart'
    show notificationCenterCoordinatorProvider, notificationFeedForUiProvider;
import '../../../core/providers/server_notifications_provider.dart';
import '../../../core/providers/stock_providers.dart';
import '../../../core/providers/business_aggregates_invalidation.dart';
import '../../../core/router/navigation_ext.dart';
import '../../../core/router/post_auth_route.dart' show sessionIsStaff;
import '../../../shared/widgets/hexa_empty_state.dart';
import '../../../core/errors/load_state_error.dart';
import '../../../core/design_system/hexa_responsive.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/theme/theme_context_ext.dart';
import 'widgets/notification_alert_card.dart';

class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({super.key});

  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> {
  NotificationCategoryFilter _filter = NotificationCategoryFilter.all;
  final _textSearch = TextEditingController();

  bool get _isStaff {
    final session = ref.read(sessionProvider);
    return session != null && sessionIsStaff(session);
  }

  List<NotificationCategoryFilter> get _visibleFilters {
    if (_isStaff) {
      return const [
        NotificationCategoryFilter.all,
        NotificationCategoryFilter.critical,
        NotificationCategoryFilter.warehouse,
        NotificationCategoryFilter.staff,
        NotificationCategoryFilter.system,
      ];
    }
    return NotificationCategoryFilter.values;
  }

  @override
  void dispose() {
    _textSearch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(notificationCenterCoordinatorProvider);
    final tt = Theme.of(context).textTheme;
    final serverAsync = ref.watch(appNotificationsListProvider);
    final items = ref.watch(notificationFeedForUiProvider);
    final filtered =
        items.where((n) => notificationMatchesCategoryFilter(n, _filter)).toList();
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
    final stockCountsAsync = ref.watch(stockStatusCountsProvider);
    final showEmptyState = visible.isEmpty &&
        !serverAsync.isLoading &&
        !stockCountsAsync.isLoading &&
        !(serverAsync.isLoading && items.isNotEmpty);

    final onSurf = Theme.of(context).colorScheme.onSurface;
    return Scaffold(
      backgroundColor: context.adaptiveScaffold,
      appBar: AppBar(
        backgroundColor: context.adaptiveAppBarBg,
        surfaceTintColor: Colors.transparent,
        title: Text('Notifications',
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
              onPressed: () => _markAllRead(),
              child: const Text('Mark all read'),
            ),
          IconButton(
            tooltip: 'Clear server notifications',
            icon: Icon(Icons.delete_sweep_outlined,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            onPressed: serverAsync.valueOrNull?.isEmpty == true
                ? null
                : () => _clearServerNotifications(),
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
              color: Theme.of(context)
                  .colorScheme
                  .errorContainer
                  .withValues(alpha: 0.35),
              child: ListTile(
                dense: true,
                leading: Icon(Icons.warning_amber_rounded,
                    color: Theme.of(context).colorScheme.error),
                title: const Text('Could not refresh server notifications'),
                subtitle: Text(
                  loadStateErrorSubtitle(serverAsync.error),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: () {
                    ref.invalidate(appNotificationsListProvider);
                  },
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
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final f in _visibleFilters)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _FilterChip(
                        label: switch (f) {
                          NotificationCategoryFilter.all => 'All',
                          NotificationCategoryFilter.critical => 'Critical',
                          NotificationCategoryFilter.warehouse => 'Warehouse',
                          NotificationCategoryFilter.purchases => 'Purchases',
                          NotificationCategoryFilter.staff => 'Staff',
                          NotificationCategoryFilter.system => 'System',
                        },
                        selected: _filter == f,
                        onTap: () => setState(() => _filter = f),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_filter != NotificationCategoryFilter.all || q.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Text(
                'Showing ${visible.length} of ${items.length} alerts',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(appNotificationsListProvider);
                ref.invalidate(stockStatusCountsProvider);
                await ref.read(appNotificationsListProvider.future);
              },
              child: showEmptyState
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: 280,
                          child: HexaEmptyState(
                            icon: Icons.notifications_none_outlined,
                            title: q.isNotEmpty
                                ? 'No matches'
                                : _emptyTitleForFilter(_filter),
                            subtitle: q.isNotEmpty
                                ? 'Try a different search or clear the search box.'
                                : filterEmptyButHasItems
                                    ? 'Switch to All or another tab — alerts are hidden by the current filter.'
                                    : _emptySubtitleForFilter(_filter),
                            action: Column(
                              children: [
                                if (filterEmptyButHasItems)
                                  FilledButton(
                                    onPressed: () => setState(
                                      () => _filter =
                                          NotificationCategoryFilter.all,
                                    ),
                                    child: const Text('Show all alerts'),
                                  ),
                                if (items.isEmpty)
                                  FilledButton.icon(
                                    onPressed: () => context.push(
                                      _isStaff
                                          ? '/staff/receive'
                                          : '/purchase/new',
                                    ),
                                    icon: const Icon(Icons.add_rounded, size: 18),
                                    label: Text(_isStaff
                                        ? 'Receive shipment'
                                        : 'New purchase'),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : _buildNotificationScrollBody(
                      context: context,
                      ref: ref,
                      visible: visible,
                      rel: rel,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _markAllRead() async {
    final session = ref.read(sessionProvider);
    final api = ref.read(hexaApiProvider);
    if (session != null) {
      try {
        await api.markAllAppNotificationsRead(
          businessId: session.primaryBusiness.id,
        );
      } catch (_) {}
    }
    final items = ref.read(notificationFeedForUiProvider);
    final whIds = <String>{
      for (final n in items)
        if (n.id.startsWith('wh_') && !n.isRead) n.id,
    };
    if (whIds.isNotEmpty) {
      ref.read(warehouseAlertReadIdsProvider.notifier).state = {
        ...ref.read(warehouseAlertReadIdsProvider),
        ...whIds,
      };
    }
    final purDismiss = <String>{
      for (final n in items)
        if (n.id.startsWith('pur_') && !n.isRead) n.id,
    };
    if (purDismiss.isNotEmpty) {
      ref.read(dismissedPurchaseAlertIdsProvider.notifier).state = {
        ...ref.read(dismissedPurchaseAlertIdsProvider),
        ...purDismiss,
      };
    }
    for (final n in items) {
      if (n.isRead) continue;
      if (n.serverNotificationId == null &&
          !n.id.startsWith('pur_') &&
          !n.id.startsWith('wh_')) {
        ref.read(notificationsProvider.notifier).markRead(n.id);
      }
    }
    ref.invalidate(appNotificationsListProvider);
    if (mounted) setState(() {});
  }

  Future<void> _clearServerNotifications() async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    final ok = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Clear server notifications?'),
            content: const Text(
              'Stock alerts generated from live warehouse data will still appear until the stock issue is fixed.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Clear'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    await ref.read(hexaApiProvider).clearAllAppNotifications(
          businessId: session.primaryBusiness.id,
        );
    ref.invalidate(appNotificationsListProvider);
    if (mounted) setState(() {});
  }

  Widget _buildNotificationScrollBody({
    required BuildContext context,
    required WidgetRef ref,
    required List<NotificationItem> visible,
    required DateFormat rel,
  }) {
    final tiles = _buildGroupedNotificationTiles(
      context: context,
      ref: ref,
      visible: visible,
      rel: rel,
    );
    if (!context.isDesktopLayout) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: tiles,
      );
    }
    final contentWidth = MediaQuery.sizeOf(context).width - 32;
    final tileWidth = (contentWidth - 12) / 2;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final w in tiles)
              w is _NotificationDateHeader
                  ? SizedBox(
                      width: contentWidth,
                      child: w,
                    )
                  : SizedBox(width: tileWidth, child: w),
          ],
        ),
      ],
    );
  }

  List<Widget> _buildGroupedNotificationTiles({
    required BuildContext context,
    required WidgetRef ref,
    required List<NotificationItem> visible,
    required DateFormat rel,
  }) {
    if (visible.isEmpty) return const [];

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final widgets = <Widget>[];

    void addSection(String label, List<NotificationItem> section) {
      if (section.isEmpty) return;
      widgets.add(_NotificationDateHeader(label: label));
      for (final n in section) {
        widgets.add(_notificationAlertCard(
          context: context,
          ref: ref,
          n: n,
          rel: rel,
        ));
      }
    }

    bool isToday(NotificationItem n) {
      final d =
          DateTime(n.createdAt.year, n.createdAt.month, n.createdAt.day);
      return d == today;
    }

    bool isYesterday(NotificationItem n) {
      final d =
          DateTime(n.createdAt.year, n.createdAt.month, n.createdAt.day);
      return d == yesterday;
    }

    addSection('Today', visible.where(isToday).toList());
    addSection('Yesterday', visible.where(isYesterday).toList());
    addSection(
      'Earlier',
      visible.where((n) => !isToday(n) && !isYesterday(n)).toList(),
    );
    if (widgets.isEmpty && visible.isNotEmpty) {
      for (final n in visible) {
        widgets.add(_notificationAlertCard(
          context: context,
          ref: ref,
          n: n,
          rel: rel,
        ));
      }
    }
    return widgets;
  }

  Widget _notificationAlertCard({
    required BuildContext context,
    required WidgetRef ref,
    required NotificationItem n,
    required DateFormat rel,
  }) {
    Future<void> handleTap() async {
      final sid = n.serverNotificationId;
      if (sid != null && sid.isNotEmpty) {
        final session = ref.read(sessionProvider);
        if (session != null) {
          try {
            await ref.read(hexaApiProvider).patchAppNotificationRead(
                  businessId: session.primaryBusiness.id,
                  notificationId: sid,
                );
            invalidateNotificationSurfaces(ref);
          } catch (_) {}
        }
      } else if (n.id.startsWith('wh_')) {
        ref.read(warehouseAlertReadIdsProvider.notifier).state = {
          ...ref.read(warehouseAlertReadIdsProvider),
          n.id,
        };
      } else if (n.id.startsWith('pur_')) {
        ref.read(dismissedPurchaseAlertIdsProvider.notifier).state = {
          ...ref.read(dismissedPurchaseAlertIdsProvider),
          n.id,
        };
      } else {
        ref.read(notificationsProvider.notifier).markRead(n.id);
      }
      final route = n.actionRoute;
      if (route != null && route.isNotEmpty && context.mounted) {
        navigateActionRoute(context, route);
      }
    }

    final time = NotificationAlertCard.relativeTime(n.createdAt, rel);
    final isReorder = n.serverKind == 'reorder_request';
    String? itemIdFromRoute;
    final route = n.actionRoute;
    if (route != null && route.contains('/catalog/item/')) {
      itemIdFromRoute = route.split('/catalog/item/').last.split('?').first;
    }

    return NotificationAlertCard(
      key: ValueKey(n.id),
      item: n,
      timeLabel: time,
      onTap: handleTap,
      onOrderNow: isReorder && itemIdFromRoute != null && itemIdFromRoute.isNotEmpty
          ? () {
              handleTap();
              if (context.mounted) {
                pushPurchaseNew(
                  context,
                  queryParameters: {'itemId': itemIdFromRoute!},
                );
              }
            }
          : isReorder
              ? () {
                  handleTap();
                  if (context.mounted) pushPurchaseNew(context);
                }
              : null,
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

String _emptyTitleForFilter(NotificationCategoryFilter filter) {
  return switch (filter) {
    NotificationCategoryFilter.all => 'No alerts yet',
    NotificationCategoryFilter.critical => 'No critical alerts',
    NotificationCategoryFilter.warehouse => 'No warehouse alerts',
    NotificationCategoryFilter.purchases => 'No purchase alerts',
    NotificationCategoryFilter.staff => 'No staff alerts',
    NotificationCategoryFilter.system => 'No system notifications',
  };
}

String _emptySubtitleForFilter(NotificationCategoryFilter filter) {
  return switch (filter) {
    NotificationCategoryFilter.all =>
      'Stock, purchase, and system activity will appear here.',
    NotificationCategoryFilter.critical =>
      'Critical shows urgent server alerts. Low/out stock stays under Warehouse.',
    NotificationCategoryFilter.warehouse =>
      'Low stock, barcodes, and opening stock alerts appear here.',
    NotificationCategoryFilter.purchases =>
      'Payment due, delivery pending, and invoice updates appear here.',
    NotificationCategoryFilter.staff =>
      'Deliveries, corrections, and warehouse requests appear here.',
    NotificationCategoryFilter.system =>
      'Exports, sync status, and general notices appear here.',
  };
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
