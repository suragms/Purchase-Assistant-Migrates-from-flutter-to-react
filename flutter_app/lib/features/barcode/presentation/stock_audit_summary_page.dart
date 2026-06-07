import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/router/navigation_ext.dart';
import '../../../core/json_coerce.dart';

/// Post-audit summary (matched vs discrepant lines).
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
    final matched = <Map<String, dynamic>>[];
    final discrepant = <Map<String, dynamic>>[];
    for (final raw in lines) {
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      if (coerceToDouble(m['difference_qty']).abs() < 0.01) {
        matched.add(m);
      } else {
        discrepant.add(m);
      }
    }

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.popOrGo('/barcode/scan')),
        title: const Text('Audit summary'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Session complete',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 12),
                  _row('Items scanned', '${lines.length}'),
                  _row('Matching', '${matched.length}', color: const Color(0xFF2E7D32)),
                  _row(
                    'Discrepancies',
                    '${discrepant.length}',
                    color: discrepant.isEmpty
                        ? null
                        : const Color(0xFFC62828),
                  ),
                ],
              ),
            ),
          ),
          if (matched.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Matching',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.green.shade800,
              ),
            ),
            ...matched.take(20).map(_auditTile),
          ],
          if (discrepant.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Discrepant',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.red.shade800,
              ),
            ),
            ...discrepant.map(_auditTile),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => context.go('/barcode/scan'),
            child: const Text('Scan again'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => context.popOrGo('/barcode/scan'),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Widget _auditTile(Map<String, dynamic> m) {
    final name = m['item_name']?.toString() ?? 'Item';
    final system = coerceToDouble(m['system_qty'] ?? m['expected_qty']);
    final scanned = coerceToDouble(m['scanned_qty'] ?? m['counted_qty']);
    final diff = coerceToDouble(m['difference_qty']);
    return ListTile(
      dense: true,
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(
        'System: $system · Scanned: $scanned · Diff: $diff',
        style: const TextStyle(fontSize: 11),
      ),
    );
  }

  Widget _row(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 16,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
