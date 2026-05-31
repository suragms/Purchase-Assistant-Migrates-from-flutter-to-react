import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/providers/business_users_provider.dart';
import '../../../core/router/post_auth_route.dart';
import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/errors/user_facing_errors.dart';
import '../../../core/router/navigation_ext.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../../../core/widgets/hexa_error_card.dart';

final businessUserProfileProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
  (ref, userId) async {
    final session = ref.watch(sessionProvider);
    if (session == null) return {};
    return ref.read(hexaApiProvider).getBusinessUser(
          businessId: session.primaryBusiness.id,
          userId: userId,
        );
  },
);

final userActivityFeedProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
  (ref, userId) async {
    final session = ref.watch(sessionProvider);
    if (session == null) return [];
    return ref.read(hexaApiProvider).listUserActivity(
          businessId: session.primaryBusiness.id,
          userId: userId,
          days: 30,
        );
  },
);

final userStockHistoryProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
  (ref, userId) async {
    final session = ref.watch(sessionProvider);
    if (session == null) return [];
    return ref.read(hexaApiProvider).listUserStockAdjustments(
          businessId: session.primaryBusiness.id,
          userId: userId,
        );
  },
);

final userPurchasesProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
  (ref, userId) async {
    final session = ref.watch(sessionProvider);
    if (session == null) return [];
    return ref.read(hexaApiProvider).listUserPurchases(
          businessId: session.primaryBusiness.id,
          userId: userId,
        );
  },
);

final userLedgerProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
  (ref, userId) async {
    final session = ref.watch(sessionProvider);
    if (session == null) return [];
    return ref.read(hexaApiProvider).listUserLedger(
          businessId: session.primaryBusiness.id,
          userId: userId,
        );
  },
);

final userPermissionsProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
  (ref, userId) async {
    final session = ref.watch(sessionProvider);
    if (session == null) return {};
    return ref.read(hexaApiProvider).getUserPermissions(
          businessId: session.primaryBusiness.id,
          userId: userId,
        );
  },
);

final userCreatedItemsProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
  (ref, userId) async {
    final session = ref.watch(sessionProvider);
    if (session == null) return [];
    return ref.read(hexaApiProvider).listUserCreatedItems(
          businessId: session.primaryBusiness.id,
          userId: userId,
        );
  },
);

final userLedgerGroupedProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
  (ref, userId) async {
    final session = ref.watch(sessionProvider);
    if (session == null) return {};
    return ref.read(hexaApiProvider).listUserLedgerGrouped(
          businessId: session.primaryBusiness.id,
          userId: userId,
        );
  },
);

/// Tabbed user profile for owners/managers.
class UserProfilePage extends ConsumerStatefulWidget {
  const UserProfilePage({super.key, required this.userId});

  final String userId;

  @override
  ConsumerState<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends ConsumerState<UserProfilePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 7, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _resetPassword() async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      final out = await ref.read(hexaApiProvider).resetBusinessUserPassword(
            businessId: session.primaryBusiness.id,
            userId: widget.userId,
          );
      final pwd = out['new_password']?.toString() ?? '';
      final email = out['login_email']?.toString() ?? '';
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('New password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (email.isNotEmpty) SelectableText('Email: $email'),
              SelectableText('Password: $pwd'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: pwd));
                Navigator.pop(ctx);
              },
              child: const Text('Copy & close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userFacingError(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(businessUserProfileProvider(widget.userId));
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: HexaColors.brandBackground,
      appBar: AppBar(
        title: Text('User profile', style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.popOrGo('/settings/users'),
        ),
      ),
      body: profileAsync.when(
        loading: () => const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(),
          ),
        ),
        error: (e, _) => HexaErrorCard.fromError(
          error: e,
          title: 'Could not load user',
          onRetry: () => ref.invalidate(businessUserProfileProvider(widget.userId)),
        ),
        data: (u) {
          if (u.isEmpty) {
            return const Center(child: Text('User not found.'));
          }
          return Column(
            children: [
              _HeaderCard(user: u, onReset: _resetPassword, userId: widget.userId),
              Material(
                color: HexaColors.brandBackground,
                child: TabBar(
                  controller: _tabs,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelStyle: HexaDsType.body(12, weight: FontWeight.w800),
                  unselectedLabelStyle: HexaDsType.body(12, weight: FontWeight.w600),
                  labelColor: HexaColors.brandPrimary,
                  unselectedLabelColor: HexaColors.textSecondary,
                  indicatorSize: TabBarIndicatorSize.label,
                  dividerColor: Colors.transparent,
                  tabs: const [
                    Tab(text: 'Overview'),
                    Tab(text: 'Activity'),
                    Tab(text: 'Stock'),
                    Tab(text: 'Purchases'),
                    Tab(text: 'Items'),
                    Tab(text: 'Ledger'),
                    Tab(text: 'Permissions'),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    _OverviewTab(user: u),
                    _FeedTab(
                      async: ref.watch(userActivityFeedProvider(widget.userId)),
                      onRetry: () => ref.invalidate(userActivityFeedProvider(widget.userId)),
                      empty: 'No activity in the last 30 days.',
                    ),
                    _StockTab(userId: widget.userId),
                    _PurchasesTab(userId: widget.userId),
                    _ItemsTab(userId: widget.userId),
                    _LedgerTab(userId: widget.userId),
                    _PermissionsTab(userId: widget.userId),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _HeaderCard extends ConsumerWidget {
  const _HeaderCard({
    required this.user,
    required this.onReset,
    required this.userId,
  });

  final Map<String, dynamic> user;
  final VoidCallback onReset;
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final canAdmin = session != null && sessionCanAdminUsers(session);
    final name = user['name']?.toString() ?? '—';
    final role = user['role']?.toString() ?? '';
    final blocked = user['is_blocked'] == true;
    final active = user['is_active'] == true && !blocked;
    final email = user['email']?.toString() ?? user['login_email']?.toString() ?? '';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final lastLogin = DateTime.tryParse(user['last_login_at']?.toString() ?? '');

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: HexaColors.brandPrimary.withValues(alpha: 0.15),
                  child: Text(initial, style: HexaDsType.heading(22)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: HexaDsType.heading(18)),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        children: [
                          Chip(
                            label: Text(role, style: HexaDsType.body(12)),
                            visualDensity: VisualDensity.compact,
                          ),
                          Chip(
                            label: Text(
                              blocked
                                  ? 'Blocked'
                                  : (active ? 'Active' : 'Inactive'),
                              style: HexaDsType.body(12),
                            ),
                            backgroundColor: blocked
                                ? Colors.red.withValues(alpha: 0.12)
                                : (active
                                    ? Colors.teal.withValues(alpha: 0.12)
                                    : Colors.grey.withValues(alpha: 0.12)),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (email.isNotEmpty)
              Text('Email: $email', style: HexaDsType.body(14)),
            Text('Phone: ${user['phone'] ?? '—'}', style: HexaDsType.body(14)),
            if (lastLogin != null)
              Text(
                'Last login: ${DateFormat.yMMMd().add_jm().format(lastLogin.toLocal())}',
                style: HexaDsType.body(14),
              ),
            if (user['warehouse_name'] != null)
              Text('Warehouse: ${user['warehouse_name']}', style: HexaDsType.body(14)),
            if (canAdmin) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: onReset,
                    icon: const Icon(Icons.vpn_key_outlined, size: 18),
                    label: const Text('Reset password'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      if (email.isEmpty) return;
                      await Clipboard.setData(ClipboardData(text: email));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Login email copied')),
                      );
                    },
                    icon: const Icon(Icons.copy_outlined, size: 18),
                    label: const Text('Copy email'),
                  ),
                  if (role != 'owner')
                    OutlinedButton.icon(
                      onPressed: () async {
                        final s = ref.read(sessionProvider);
                        if (s == null) return;
                        try {
                          await ref.read(hexaApiProvider).patchBusinessUser(
                                businessId: s.primaryBusiness.id,
                                userId: userId,
                                isBlocked: !blocked,
                              );
                          ref.invalidate(businessUserProfileProvider(userId));
                          invalidateUserManagementCaches(ref);
                        } catch (e) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(userFacingError(e))),
                          );
                        }
                      },
                      icon: const Icon(Icons.block_flipped, size: 18),
                      label: Text(blocked ? 'Unblock' : 'Block'),
                    ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final s = ref.read(sessionProvider);
                      if (s == null) return;
                      final next = !active;
                      try {
                        await ref.read(hexaApiProvider).patchBusinessUser(
                              businessId: s.primaryBusiness.id,
                              userId: userId,
                              isActive: next,
                            );
                        ref.invalidate(businessUserProfileProvider(userId));
                        invalidateUserManagementCaches(ref);
                      } catch (e) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(userFacingError(e))),
                        );
                      }
                    },
                    icon: Icon(active ? Icons.person_off_outlined : Icons.person_outline),
                    label: Text(active ? 'Deactivate' : 'Activate'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.user});
  final Map<String, dynamic> user;

  @override
  Widget build(BuildContext context) {
    final stats = user['today_stats'] is Map
        ? Map<String, dynamic>.from(user['today_stats'] as Map)
        : <String, dynamic>{};
    final totals = user['stats'] is Map
        ? Map<String, dynamic>.from(user['stats'] as Map)
        : <String, dynamic>{};
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
      children: [
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Column(
            children: [
              _denseTile('Total stock edits', '${totals['stock_edits_total'] ?? 0}'),
              const Divider(height: 1),
              _denseTile('Total purchases', '${totals['purchases_total'] ?? 0}'),
              const Divider(height: 1),
              _denseTile('Total scans', '${totals['scans_total'] ?? 0}'),
              const Divider(height: 1),
              _denseTile('Items created', '${totals['items_created_total'] ?? 0}'),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Column(
            children: [
              _denseTile('7d activity', '${user['activity_count_7d'] ?? 0} events'),
              const Divider(height: 1),
              _denseTile('7d purchases', '${user['purchases_7d'] ?? 0}'),
              const Divider(height: 1),
              _denseTile('7d stock edits', '${user['stock_updates_7d'] ?? 0}'),
              const Divider(height: 1),
              _denseTile('Today scans', '${stats['scans'] ?? 0}'),
              const Divider(height: 1),
              _denseTile('Today stock updates', '${stats['stock_updates'] ?? 0}'),
            ],
          ),
        ),
        if (user['notes'] != null && user['notes'].toString().isNotEmpty)
          _denseTile('Notes', user['notes'].toString()),
        if (user['created_at'] != null)
          _denseTile('Created', user['created_at'].toString()),
      ],
    );
  }
}

class _FeedTab extends StatelessWidget {
  const _FeedTab({
    required this.async,
    required this.onRetry,
    required this.empty,
  });

  final AsyncValue<List<Map<String, dynamic>>> async;
  final VoidCallback onRetry;
  final String empty;

  @override
  Widget build(BuildContext context) {
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => FriendlyLoadError(
        onRetry: onRetry,
        message: userFacingError(e),
        subtitle: null,
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return Center(child: Text(empty, style: HexaDsType.body(14)));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: rows.length,
          itemBuilder: (_, i) => _activityRow(rows[i]),
        );
      },
    );
  }
}

Widget _activityRow(Map<String, dynamic> row) {
  final at = DateTime.tryParse(row['created_at']?.toString() ?? '');
  final time = at != null ? DateFormat('d MMM, HH:mm').format(at.toLocal()) : '';
  final action = row['action_type']?.toString() ?? '';
  final item = row['item_name']?.toString();
  final details = row['details'] is Map
      ? Map<String, dynamic>.from(row['details'] as Map)
      : null;
  String? delta;
  if (details != null) {
    final before = details['before'];
    final after = details['after'];
    if (before is Map && after is Map) {
      delta = '${before.toString()} → ${after.toString()}';
    } else {
      final o = details['old_qty'] ?? (before is Map ? before['qty'] : null);
      final n = details['new_qty'] ?? (after is Map ? after['qty'] : null);
      if (o != null && n != null) delta = '$o → $n';
    }
  }
  return Card(
    margin: const EdgeInsets.only(bottom: 8),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    child: ListTile(
      dense: true,
      title: Text(action, style: HexaDsType.body(14, weight: FontWeight.w600)),
      subtitle: Text(
        [if (item != null && item.isNotEmpty) item, if (delta != null) delta, time]
            .where((s) => s.isNotEmpty)
            .join(' · '),
        style: HexaDsType.body(12),
      ),
    ),
  );
}

class _StockTab extends ConsumerWidget {
  const _StockTab({required this.userId});
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(userStockHistoryProvider(userId));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => FriendlyLoadError(
        onRetry: () => ref.invalidate(userStockHistoryProvider(userId)),
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return const Center(child: Text('No stock adjustments yet.'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: rows.length,
          itemBuilder: (_, i) {
            final r = rows[i];
            return _denseTile(
              r['item_name']?.toString() ?? 'Item',
              '${r['old_qty']} → ${r['new_qty']} · ${r['adjustment_type']}',
            );
          },
        );
      },
    );
  }
}

class _PurchasesTab extends ConsumerWidget {
  const _PurchasesTab({required this.userId});
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(userPurchasesProvider(userId));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => FriendlyLoadError(
        onRetry: () => ref.invalidate(userPurchasesProvider(userId)),
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return const Center(child: Text('No purchases recorded.'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: rows.length,
          itemBuilder: (_, i) {
            final p = rows[i];
            return _denseTile(
              p['human_id']?.toString() ?? p['id']?.toString() ?? 'Purchase',
              '${p['status'] ?? ''} · ${p['total_amount'] ?? ''}',
            );
          },
        );
      },
    );
  }
}

class _ItemsTab extends ConsumerWidget {
  const _ItemsTab({required this.userId});
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(userCreatedItemsProvider(userId));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => FriendlyLoadError(
        onRetry: () => ref.invalidate(userCreatedItemsProvider(userId)),
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return const Center(child: Text('No items created yet.'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: rows.length,
          itemBuilder: (_, i) {
            final it = rows[i];
            return _denseTile(
              it['name']?.toString() ?? 'Item',
              '${it['category'] ?? ''} · reorder ${it['reorder_level'] ?? '—'}',
            );
          },
        );
      },
    );
  }
}

class _LedgerTab extends ConsumerWidget {
  const _LedgerTab({required this.userId});
  final String userId;

  List<Map<String, dynamic>> _entries(dynamic raw) {
    if (raw is! List) return [];
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(userLedgerGroupedProvider(userId));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => FriendlyLoadError(
        onRetry: () => ref.invalidate(userLedgerGroupedProvider(userId)),
      ),
      data: (grouped) {
        final sections = <String, List<Map<String, dynamic>>>{
          'Today': _entries(grouped['today']),
          'Yesterday': _entries(grouped['yesterday']),
          'This week': _entries(grouped['this_week']),
        };
        final hasAny = sections.values.any((l) => l.isNotEmpty);
        if (!hasAny) {
          return const Center(child: Text('No ledger entries.'));
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final entry in sections.entries)
              if (entry.value.isNotEmpty) ...[
                Text(entry.key, style: HexaDsType.heading(16)),
                const SizedBox(height: 8),
                for (final e in entry.value)
                  _denseTile(
                    '${e['kind']}: ${e['title']}',
                    '${e['subtitle'] ?? ''}',
                  ),
                const SizedBox(height: 12),
              ],
          ],
        );
      },
    );
  }
}

String _permissionLabel(String key) {
  return key
      .split('_')
      .where((w) => w.isNotEmpty)
      .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

class _PermissionsTab extends ConsumerStatefulWidget {
  const _PermissionsTab({required this.userId});
  final String userId;

  @override
  ConsumerState<_PermissionsTab> createState() => _PermissionsTabState();
}

class _PermissionsTabState extends ConsumerState<_PermissionsTab> {
  Map<String, bool>? _draft;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(userPermissionsProvider(widget.userId));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => FriendlyLoadError(
        onRetry: () => ref.invalidate(userPermissionsProvider(widget.userId)),
      ),
      data: (body) {
        final perms = body['permissions'] is Map
            ? Map<String, dynamic>.from(body['permissions'] as Map)
            : <String, dynamic>{};
        _draft ??= perms.map((k, v) => MapEntry(k, v == true));
        final draft = _draft!;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ...draft.keys.map(
              (k) => SwitchListTile(
                title: Text(_permissionLabel(k), style: HexaDsType.body(14)),
                value: draft[k] ?? false,
                onChanged: (v) => setState(() => draft[k] = v),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                final session = ref.read(sessionProvider);
                if (session == null) return;
                try {
                  await ref.read(hexaApiProvider).patchUserPermissions(
                        businessId: session.primaryBusiness.id,
                        userId: widget.userId,
                        permissions: draft,
                      );
                  ref.invalidate(userPermissionsProvider(widget.userId));
                  invalidateUserManagementCaches(ref);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Permissions saved')),
                  );
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(userFacingError(e))),
                  );
                }
              },
              child: const Text('Save permissions'),
            ),
          ],
        );
      },
    );
  }
}

Widget _denseTile(String title, String subtitle) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 5,
          child: Text(
            title,
            style: HexaDsType.body(13, weight: FontWeight.w600),
          ),
        ),
        Expanded(
          flex: 4,
          child: Text(
            subtitle,
            textAlign: TextAlign.end,
            style: HexaDsType.body(13),
          ),
        ),
      ],
    ),
  );
}
