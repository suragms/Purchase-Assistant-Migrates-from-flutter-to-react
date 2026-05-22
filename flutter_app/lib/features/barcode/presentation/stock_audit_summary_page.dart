import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/json_coerce.dart';

/// Post-audit summary (counts matched / mismatched).
class StockAuditSummaryPage extends ConsumerStatefulWidget {
  const StockAuditSummaryPage({super.key});

  @override
  ConsumerState<StockAuditSummaryPage> createState() =>
      _StockAuditSummaryPageState();
}

class _StockAuditSummaryPageState extends ConsumerState<StockAuditSummaryPage> {
  Map<String, dynamic>? _audit;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final session = ref.read(sessionProvider);
    final id = GoRouterState.of(context).uri.queryParameters['id'];
    if (session == null || id == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final audit = await ref.read(hexaApiProvider).getStockAudit(
            businessId: session.primaryBusiness.id,
            auditId: id,
          );
      setState(() {
        _audit = audit;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final items = _audit?['items'];
    final lines = items is List ? items : <dynamic>[];
    var matched = 0;
    var mismatch = 0;
    for (final raw in lines) {
      if (raw is! Map) continue;
      if (coerceToDouble(raw['difference_qty']).abs() < 0.01) {
        matched++;
      } else {
        mismatch++;
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Audit summary')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Audit complete',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 16),
            _row('Items checked', '${lines.length}'),
            _row('Matched', '$matched'),
            _row('Mismatched', '$mismatch'),
            const Spacer(),
            FilledButton(
              onPressed: () => context.go('/barcode/scan'),
              child: const Text('Back to scanner'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}
