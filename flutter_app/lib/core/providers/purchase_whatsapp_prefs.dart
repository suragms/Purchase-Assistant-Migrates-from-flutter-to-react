import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'prefs_provider.dart';

/// When true, Save & Share sends PDF + summary to accounts WhatsApp after save.
final autoSharePurchaseWhatsappProvider =
    NotifierProvider<AutoSharePurchaseWhatsappNotifier, bool>(
  AutoSharePurchaseWhatsappNotifier.new,
);

class AutoSharePurchaseWhatsappNotifier extends Notifier<bool> {
  static const _k = 'pref_auto_share_purchase_whatsapp';

  @override
  bool build() {
    final p = ref.watch(sharedPreferencesProvider);
    return p.getBool(_k) ?? true;
  }

  Future<void> setValue(bool v) async {
    await ref.read(sharedPreferencesProvider).setBool(_k, v);
    state = v;
  }
}
