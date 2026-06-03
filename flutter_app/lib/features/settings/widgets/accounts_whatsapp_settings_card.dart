import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/providers/purchase_whatsapp_prefs.dart';
import '../../../core/services/whatsapp_phone_normalize.dart';
import '../../../core/theme/theme_context_ext.dart';
import 'accounts_whatsapp_field.dart';

/// Owner-only quick save for accounts staff WhatsApp on main Settings.
class AccountsWhatsappSettingsCard extends ConsumerStatefulWidget {
  const AccountsWhatsappSettingsCard({super.key});

  @override
  ConsumerState<AccountsWhatsappSettingsCard> createState() =>
      _AccountsWhatsappSettingsCardState();
}

class _AccountsWhatsappSettingsCardState
    extends ConsumerState<AccountsWhatsappSettingsCard> {
  late final TextEditingController _ctrl;
  bool _saving = false;
  bool _valid = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _load() {
    final n = ref.read(sessionProvider)?.primaryBusiness.accountsWhatsappNumber;
    if (n != null && n.isNotEmpty) {
      _ctrl.text = n;
      _valid = isValidAccountsWhatsappInput(n);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final session = ref.read(sessionProvider);
    if (session == null || session.primaryBusiness.role != 'owner') return;

    final t = _ctrl.text.trim();
    if (t.isNotEmpty && !isValidAccountsWhatsappInput(t)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enter a valid India or Gulf mobile (+91, +971, +968, +965, +974)',
          ),
        ),
      );
      return;
    }

    final storage = storageDigitsForAccountsWhatsappInput(t);

    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(hexaApiProvider).patchBusinessBranding(
            businessId: session.primaryBusiness.id,
            includeAccountsWhatsapp: true,
            accountsWhatsappNumber: storage ?? '',
          );
      await ref.read(sessionProvider.notifier).refreshBusinesses();
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Accounts WhatsApp saved')),
      );
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(friendlyApiError(e))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: context.adaptiveCard,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.chat_outlined, color: cs.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Accounts staff WhatsApp',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AccountsWhatsappField(
              controller: _ctrl,
              onValidityChanged: (v) {
                if (mounted) setState(() => _valid = v);
              },
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Auto share on Save & Share'),
              subtitle: const Text(
                'After saving a purchase, send PDF and summary to this WhatsApp number',
              ),
              value: ref.watch(autoSharePurchaseWhatsappProvider),
              onChanged: (v) =>
                  ref.read(autoSharePurchaseWhatsappProvider.notifier).setValue(v),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _saving || (_ctrl.text.trim().isNotEmpty && !_valid)
                  ? null
                  : _save,
              child: _saving
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save WhatsApp number'),
            ),
          ],
        ),
      ),
    );
  }
}
