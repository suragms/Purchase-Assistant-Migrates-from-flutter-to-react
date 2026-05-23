import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/router/navigation_ext.dart';

/// Owner-only OpenAI / assistant usage summary.
class AiUsagePage extends ConsumerStatefulWidget {
  const AiUsagePage({super.key});

  @override
  ConsumerState<AiUsagePage> createState() => _AiUsagePageState();
}

class _AiUsagePageState extends ConsumerState<AiUsagePage> {
  bool _loading = true;
  Map<String, dynamic> _data = const {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final session = ref.read(sessionProvider);
    if (session == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final res = await ref.read(hexaApiProvider).getAiUsage(
            businessId: session.primaryBusiness.id,
          );
      setState(() {
        _data = res;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final requests = (_data['requests_today'] as num?)?.toInt() ?? 0;
    final tokens = (_data['tokens_used'] as num?)?.toInt() ?? 0;
    final cost = (_data['estimated_cost_inr'] as num?)?.toDouble() ?? 0;

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.pop()),
        title: const Text(
          'AI Usage',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _statTile('Requests today', '$requests'),
                _statTile('Tokens used', '$tokens'),
                _statTile('Estimated cost', '₹${cost.toStringAsFixed(0)}'),
                const SizedBox(height: 16),
                Text(
                  'AI usage is billed monthly with your subscription.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
    );
  }

  Widget _statTile(String label, String value) {
    return Card(
      child: ListTile(
        title: Text(label, style: const TextStyle(fontSize: 13)),
        trailing: Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}
