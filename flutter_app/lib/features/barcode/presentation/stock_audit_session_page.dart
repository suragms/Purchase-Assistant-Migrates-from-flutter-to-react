import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/json_coerce.dart';
import '../../../core/providers/business_aggregates_invalidation.dart';
import '../../../core/providers/stock_audit_providers.dart';
import '../../../core/widgets/hexa_error_card.dart';

/// Active warehouse audit session — scanned lines and complete.
class StockAuditSessionPage extends ConsumerWidget {
  const StockAuditSessionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auditAsync = ref.watch(activeStockAuditProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock audit'),
        actions: [
          TextButton(
            onPressed: () => context.push('/barcode/scan'),
            child: const Text('Scan next'),
          ),
        ],
      ),
      body: auditAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: HexaErrorCard.fromError(
            error: e,
            onRetry: () => ref.invalidate(activeStockAuditProvider),
          ),
        ),
        data: (audit) {
          if (audit == null) {
            return Center(
              child: FilledButton(
                onPressed: () => _startSession(ref, context),
                child: const Text('Start audit session'),
              ),
            );
          }
          final items = audit['items'];
          final lines = items is List ? items : <dynamic>[];
          var matched = 0;
          var mismatch = 0;
          for (final raw in lines) {
            if (raw is! Map) continue;
            final diff = coerceToDouble(raw['difference_qty']);
            if (diff.abs() < 0.01) {
              matched++;
            } else {
              mismatch++;
            }
          }
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    _chip('Scanned', '${lines.length}'),
                    const SizedBox(width: 8),
                    _chip('Matched', '$matched', const Color(0xFF3B6D11)),
                    const SizedBox(width: 8),
                    _chip('Mismatch', '$mismatch', const Color(0xFFA32D2D)),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: lines.length,
                  itemBuilder: (_, i) {
                    final m = Map<String, dynamic>.from(lines[i] as Map);
                    final diff = coerceToDouble(m['difference_qty']);
                    return ListTile(
                      dense: true,
                      title: Text('Item ${m['item_id']?.toString().substring(0, 8) ?? ''}…'),
                      subtitle: Text(
                        'System ${m['system_qty']} → counted ${m['counted_qty']}',
                      ),
                      trailing: Text(
                        diff == 0 ? 'OK' : 'Δ $diff',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: diff == 0
                              ? const Color(0xFF3B6D11)
                              : const Color(0xFFA32D2D),
                        ),
                      ),
                    );
                  },
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: FilledButton(
                    onPressed: () => _endSession(ref, context, audit['id'].toString()),
                    child: const Text('End audit & review'),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _chip(String label, String value, [Color? fg]) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontWeight: FontWeight.w900, color: fg)),
            Text(label, style: const TextStyle(fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Future<void> _startSession(WidgetRef ref, BuildContext context) async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    await ref.read(hexaApiProvider).createStockAudit(
          businessId: session.primaryBusiness.id,
        );
    ref.invalidate(activeStockAuditProvider);
  }

  Future<void> _endSession(
    WidgetRef ref,
    BuildContext context,
    String auditId,
  ) async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    final bid = session.primaryBusiness.id;
    await ref.read(hexaApiProvider).completeStockAudit(
          businessId: bid,
          auditId: auditId,
        );
    invalidateWarehouseSurfaces(ref);
    ref.invalidate(activeStockAuditProvider);
    if (context.mounted) {
      context.pushReplacement('/barcode/audit-summary?id=$auditId');
    }
  }
}
