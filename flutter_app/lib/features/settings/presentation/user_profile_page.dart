import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/session_notifier.dart';
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
      final user = out['login_username']?.toString();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('New password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (user != null) Text('Username: $user'),
              SelectableText(pwd),
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
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
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
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
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
    final name = user['name']?.toString() ?? '—';
    final role = user['role']?.toString() ?? '';
    final active = user['is_active'] == true;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return Card(
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
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
                            label: Text(active ? 'Active' : 'Disabled',
                                style: HexaDsType.body(12)),
                            backgroundColor: active
                                ? Colors.teal.withValues(alpha: 0.12)
                                : Colors.grey.withValues(alpha: 0.12),
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
            Text('Phone: ${user['phone'] ?? '—'}', style: HexaDsType.body(14)),
            Text('Username: ${user['username'] ?? '—'}', style: HexaDsType.body(14)),
            if (user['warehouse_name'] != null)
              Text('Warehouse: ${user['warehouse_name']}', style: HexaDsType.body(14)),
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
                  onPressed: () {
                    final u = user['username']?.toString() ?? '';
                    if (u.isNotEmpty) Clipboard.setData(ClipboardData(text: u));
                  },
                  icon: const Icon(Icons.copy_outlined, size: 18),
                  label: const Text('Copy username'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final session = ref.read(sessionProvider);
                    if (session == null) return;
                    final next = !(user['is_active'] == true);
                    try {
                      await ref.read(hexaApiProvider).patchBusinessUser(
                            businessId: session.primaryBusiness.id,
                            userId: userId,
                            isActive: next,
                          );
                      ref.invalidate(businessUserProfileProvider(userId));
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
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        _denseTile('7d activity', '${user['activity_count_7d'] ?? 0} events'),
        _denseTile('7d purchases', '${user['purchases_7d'] ?? 0}'),
        _denseTile('7d stock edits', '${user['stock_updates_7d'] ?? 0}'),
        _denseTile('Today scans', '${stats['scans'] ?? 0}'),
        _denseTile('Today stock updates', '${stats['stock_updates'] ?? 0}'),
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
    final o = details['old_qty'];
    final n = details['new_qty'];
    if (o != null && n != null) delta = '$o → $n';
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
    final async = ref.watch(userActivityFeedProvider(userId));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => FriendlyLoadError(
        onRetry: () => ref.invalidate(userActivityFeedProvider(userId)),
      ),
      data: (rows) {
        final items = rows
            .where((r) => r['action_type']?.toString() == 'ITEM_CREATE')
            .toList();
        if (items.isEmpty) {
          return const Center(child: Text('No items created yet.'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          itemBuilder: (_, i) => _activityRow(items[i]),
        );
      },
    );
  }
}

class _LedgerTab extends ConsumerWidget {
  const _LedgerTab({required this.userId});
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(userLedgerProvider(userId));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => FriendlyLoadError(
        onRetry: () => ref.invalidate(userLedgerProvider(userId)),
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return const Center(child: Text('No ledger entries.'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: rows.length,
          itemBuilder: (_, i) {
            final e = rows[i];
            final at = DateTime.tryParse(e['at']?.toString() ?? '');
            final time = at != null ? DateFormat('d MMM, HH:mm').format(at.toLocal()) : '';
            return _denseTile(
              '${e['kind']}: ${e['title']}',
              '${e['subtitle'] ?? ''} · $time',
            );
          },
        );
      },
    );
  }
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
                title: Text(k.replaceAll('_', ' '), style: HexaDsType.body(14)),
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
  return Card(
    margin: const EdgeInsets.only(bottom: 8),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    child: ListTile(
      dense: true,
      title: Text(title, style: HexaDsType.body(14, weight: FontWeight.w600)),
      subtitle: Text(subtitle, style: HexaDsType.body(12)),
    ),
  );
}
