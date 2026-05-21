import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/errors/user_facing_errors.dart';
import '../../../core/widgets/hexa_error_card.dart';
import '../../../core/router/navigation_ext.dart';
import '../../../core/router/post_auth_route.dart' show sessionCanCreateUsers;
import '../../../core/theme/hexa_colors.dart';
import '../../../core/theme/theme_context_ext.dart';

final businessUsersListProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return [];
  return ref.read(hexaApiProvider).listBusinessUsers(
        businessId: session.primaryBusiness.id,
      );
});

enum _UserFilter { all, active, staff, managers, disabled, recent }

/// Owner / super_admin: list workspace users, create staff/manager, share credentials.
class UserManagementPage extends ConsumerStatefulWidget {
  const UserManagementPage({super.key});

  @override
  ConsumerState<UserManagementPage> createState() => _UserManagementPageState();
}

class _UserManagementPageState extends ConsumerState<UserManagementPage> {
  _UserFilter _filter = _UserFilter.all;

  List<Map<String, dynamic>> _filtered(List<Map<String, dynamic>> rows) {
    Iterable<Map<String, dynamic>> it = rows;
    switch (_filter) {
      case _UserFilter.active:
        it = it.where((u) => u['is_active'] == true);
        break;
      case _UserFilter.staff:
        it = it.where((u) => (u['role']?.toString() ?? '') == 'staff');
        break;
      case _UserFilter.managers:
        it = it.where((u) => (u['role']?.toString() ?? '') == 'manager');
        break;
      case _UserFilter.disabled:
        it = it.where((u) => u['is_active'] != true);
        break;
      case _UserFilter.recent:
        it = it.where((u) => _recentActive(u['last_active_at']?.toString()));
        break;
      case _UserFilter.all:
        break;
    }
    return it.toList();
  }

  Future<void> _openCreateSheet() async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    final bid = session.primaryBusiness.id;
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final userCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    var role = 'staff';
    var active = true;
    var saving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 8,
            bottom: MediaQuery.viewInsetsOf(ctx).bottom + 20,
          ),
          child: StatefulBuilder(
            builder: (ctx, setModal) {
              Future<void> submit() async {
                if (saving) return;
                final name = nameCtrl.text.trim();
                final phone = phoneCtrl.text.trim();
                if (name.isEmpty || phone.length < 6) return;
                setModal(() => saving = true);
                try {
                  final body = await ref.read(hexaApiProvider).createBusinessUser(
                        businessId: bid,
                        fullName: name,
                        phone: phone,
                        role: role,
                        username: userCtrl.text.trim().isEmpty ? null : userCtrl.text.trim(),
                        notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
                        password: passCtrl.text.trim().isEmpty ? null : passCtrl.text.trim(),
                        isActive: active,
                      );
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  ref.invalidate(businessUsersListProvider);
                  if (!mounted) return;
                  final user = body['user'] is Map
                      ? Map<String, dynamic>.from(body['user'] as Map)
                      : <String, dynamic>{};
                  final gen = body['generated_password']?.toString();
                  final pwd = gen ??
                      (passCtrl.text.trim().isNotEmpty ? passCtrl.text.trim() : null);
                  if (pwd != null && pwd.isNotEmpty) {
                    await _showCredentialShareDialog(
                      context: context,
                      user: user,
                      password: pwd,
                      phone: phone,
                      loginUsername: body['login_username']?.toString(),
                      loginEmail: body['login_email']?.toString(),
                    );
                  } else if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('User created')),
                    );
                  }
                } on DioException catch (e) {
                  setModal(() => saving = false);
                  if (!ctx.mounted) return;
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text(userFacingError(e))),
                  );
                } catch (e) {
                  setModal(() => saving = false);
                  if (!ctx.mounted) return;
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text(userFacingError(e))),
                  );
                }
              }

              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Add user', style: HexaDsType.formSectionLabel),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Full name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Phone',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: userCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Username (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: notesCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Notes (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: role,
                      decoration: const InputDecoration(
                        labelText: 'Role',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'staff', child: Text('Staff')),
                        DropdownMenuItem(value: 'manager', child: Text('Manager')),
                      ],
                      onChanged: saving
                          ? null
                          : (v) => setModal(() => role = v ?? 'staff'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: passCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Password (optional)',
                        helperText: 'Leave empty to generate a readable password',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 4),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Active'),
                      value: active,
                      onChanged: saving ? null : (v) => setModal(() => active = v),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: saving ? null : () => unawaited(submit()),
                      child: saving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Create user'),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
    nameCtrl.dispose();
    phoneCtrl.dispose();
    userCtrl.dispose();
    notesCtrl.dispose();
    passCtrl.dispose();
  }

  Future<void> _showCredentialShareDialog({
    required BuildContext context,
    required Map<String, dynamic> user,
    required String password,
    required String phone,
    String? loginUsername,
    String? loginEmail,
  }) async {
    final name = user['name']?.toString() ?? 'User';
    final username = loginUsername ?? user['username']?.toString() ?? '';
    final email = loginEmail ?? user['email']?.toString() ?? '';
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    final lines = <String>[
      'Harisree workspace login',
      'Name: $name',
      if (username.isNotEmpty) 'Username: $username',
      'Phone: $phone',
      if (email.isNotEmpty) 'Login email: $email',
      'Password: $password',
      'Sign in with username or phone.',
    ];
    final msg = Uri.encodeComponent(lines.join('\n'));
    final wa = digits.length >= 10 ? Uri.parse('https://wa.me/$digits?text=$msg') : null;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Share credentials'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (username.isNotEmpty) Text('Username: $username'),
            SelectableText(
              'Password: $password',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: password));
              if (!ctx.mounted) return;
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text('Password copied')),
              );
            },
            child: const Text('Copy password'),
          ),
          if (wa != null)
            TextButton(
              onPressed: () async {
                if (await canLaunchUrl(wa)) {
                  await launchUrl(wa, mode: LaunchMode.externalApplication);
                }
              },
              child: const Text('WhatsApp'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  static String _filterLabel(_UserFilter f) => switch (f) {
        _UserFilter.all => 'All',
        _UserFilter.active => 'Active',
        _UserFilter.staff => 'Staff',
        _UserFilter.managers => 'Managers',
        _UserFilter.disabled => 'Disabled',
        _UserFilter.recent => 'Recent',
      };

  static bool _recentActive(String? iso) {
    final d = DateTime.tryParse(iso ?? '');
    if (d == null) return false;
    return DateTime.now().toUtc().difference(d.toUtc()) < const Duration(minutes: 5);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final session = ref.watch(sessionProvider);
    final canCreate =
        session != null && sessionCanCreateUsers(session);
    final async = ref.watch(businessUsersListProvider);

    return Scaffold(
      backgroundColor: context.adaptiveScaffold,
      appBar: AppBar(
        backgroundColor: context.adaptiveAppBarBg,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Users',
          style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.popOrGo('/settings'),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(businessUsersListProvider),
            icon: const Icon(Icons.refresh_rounded),
          ),
          if (canCreate)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.tonalIcon(
                onPressed: _openCreateSheet,
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),
                label: const Text('Add'),
              ),
            ),
        ],
      ),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: _openCreateSheet,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add user'),
            )
          : null,
      body: async.when(
        loading: () => ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: 8,
          itemBuilder: (_, __) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              color: context.adaptiveCard,
              child: const SizedBox(
                height: 72,
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
          ),
        ),
        error: (e, _) => HexaErrorCard.fromError(
              error: e,
              title: 'Could not load users',
              onRetry: () => ref.invalidate(businessUsersListProvider),
            ),
        data: (rows) {
          final filtered = _filtered(rows);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    for (final f in _UserFilter.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(_filterLabel(f)),
                          selected: _filter == f,
                          onSelected: (_) => setState(() => _filter = f),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text(
                          'No users in this filter.',
                          style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () async {
                          ref.invalidate(businessUsersListProvider);
                          await ref.read(businessUsersListProvider.future);
                        },
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (ctx, i) {
                            final u = filtered[i];
                            final name = u['name']?.toString() ?? '—';
                            final phone = u['phone']?.toString() ?? '';
                            final role = u['role']?.toString() ?? '';
                            final active = u['is_active'] == true;
                            final lastLogin = u['last_login_at']?.toString();
                            final lastActive = u['last_active_at']?.toString();
                            final online = active && _recentActive(lastActive);
                            Color roleColor = switch (role) {
                              'owner' => HexaColors.accentPurple,
                              'manager' => const Color(0xFF2563EB),
                              _ => cs.primary,
                            };
                            String? loginLabel;
                            final lp = DateTime.tryParse(lastLogin ?? '');
                            if (lp != null) {
                              loginLabel =
                                  'Last login · ${DateFormat.yMMMd().add_jm().format(lp.toLocal())}';
                            }
                            return Card(
                              color: context.adaptiveCard,
                              child: ListTile(
                                leading: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    CircleAvatar(
                                      backgroundColor: cs.primaryContainer,
                                      child: Text(
                                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                                        style: TextStyle(
                                          color: cs.onPrimaryContainer,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    if (online)
                                      Positioned(
                                        right: -1,
                                        bottom: -1,
                                        child: Container(
                                          width: 12,
                                          height: 12,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF22C55E),
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: context.adaptiveCard,
                                              width: 2,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                title: Text(
                                  name,
                                  style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (phone.isNotEmpty) Text(phone),
                                    if (loginLabel != null)
                                      Text(
                                        loginLabel,
                                        style: tt.labelSmall
                                            ?.copyWith(color: cs.onSurfaceVariant),
                                      ),
                                  ],
                                ),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: roleColor.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        role.toUpperCase(),
                                        style: tt.labelSmall?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          color: roleColor,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      active ? 'Active' : 'Inactive',
                                      style: tt.labelSmall?.copyWith(
                                        color: active
                                            ? const Color(0xFF15803D)
                                            : cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
