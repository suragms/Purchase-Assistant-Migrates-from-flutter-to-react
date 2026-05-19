import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/router/navigation_ext.dart';
import '../../../core/errors/user_facing_errors.dart';
import '../../../core/widgets/hexa_error_card.dart';

final businessUserDetailProvider =
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

class UserDetailPage extends ConsumerWidget {
  const UserDetailPage({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tt = Theme.of(context).textTheme;
    final async = ref.watch(businessUserDetailProvider(userId));

    return Scaffold(
      appBar: AppBar(
        title: Text('User',
            style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.popOrGo('/settings/users'),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => HexaErrorCard.fromError(
                error: e,
                title: 'Could not load user',
                onRetry: () =>
                    ref.invalidate(businessUserDetailProvider(userId)),
              ),
          data: (u) {
            if (u.isEmpty) {
              return const Center(child: Text('User not found.'));
            }
            final name = u['name']?.toString() ?? '—';
            final role = u['role']?.toString() ?? '';
            final phone = u['phone']?.toString() ?? '';
            final active = u['is_active'] == true;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(name, style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text('Role: $role'),
                Text('Phone: $phone'),
                Text('Active: $active'),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () async {
                    final session = ref.read(sessionProvider);
                    if (session == null) return;
                    try {
                      final out = await ref.read(hexaApiProvider).resetBusinessUserPassword(
                            businessId: session.primaryBusiness.id,
                            userId: userId,
                          );
                      final pwd = out['new_password']?.toString() ?? '';
                      if (!context.mounted) return;
                      await showDialog<void>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('New password'),
                          content: SelectableText(pwd),
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
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(userFacingError(e))),
                      );
                    }
                  },
                  icon: const Icon(Icons.vpn_key_outlined),
                  label: const Text('Reset password'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
