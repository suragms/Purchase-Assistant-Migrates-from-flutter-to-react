import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/auth/auth_error_messages.dart';
import '../../../../core/auth/dashboard_role.dart';
import '../../../../core/auth/session_notifier.dart';
import '../../../../core/design_system/hexa_operational_tokens.dart';
import '../../../../core/json_coerce.dart';
import '../../../../core/providers/item_detail_providers.dart';
import '../../../../core/providers/stock_providers.dart'
    show stockItemActivityProvider, stockItemAuditProvider;
import '../../../../core/theme/hexa_colors.dart';

String stockAdjustmentTypeLabel(String? raw) {
  final type = (raw ?? '').toLowerCase().trim();
  return switch (type) {
    'purchase' || 'delivery_receive' => 'DELIVERED',
    'quick_purchase' => 'PURCHASED',
    'verification' || 'physical_count' => 'VERIFICATION',
    'correction' => 'CORRECTION',
    'damaged' || 'damage' => 'DAMAGE',
    'opening_stock' || 'opening_stock_setup' => 'OPENING',
    'sale' => 'SALE',
    'undo' => 'UNDO',
    _ => type.isEmpty
        ? 'ADJUSTMENT'
        : type.toUpperCase().replaceAll('_', ' '),
  };
}

class ItemPhysicalVerificationCard extends ConsumerWidget {
  const ItemPhysicalVerificationCard({super.key, required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stock =
        ref.watch(itemDetailStockProvider(itemId)).valueOrNull ??
            const <String, dynamic>{};
    final audit = ref.watch(stockItemAuditProvider(itemId)).valueOrNull ?? const <Map<String, dynamic>>[];
    final session = ref.watch(sessionProvider);
    final canVerify = session != null && sessionHasOwnerDashboard(session);

    final countedAtRaw = stock['physical_stock_counted_at']?.toString();
    final countedAt =
        countedAtRaw != null ? DateTime.tryParse(countedAtRaw)?.toLocal() : null;
    final countedBy = stock['physical_stock_counted_by']?.toString();
    final diff = (stock['physical_stock_difference_qty'] as num?)?.toDouble() ?? 0;

    if (countedAt == null && audit.isEmpty) {
      return const SizedBox.shrink();
    }

    final df = DateFormat('dd MMM yyyy • h:mm a');
    final showVerify = canVerify && countedAt != null && diff.abs() > 0.001;
    final phys = coerceToDouble(stock['physical_stock_qty']);

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(HexaOp.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Verification log', style: HexaOp.cardTitle(context)),
                ),
                if (showVerify)
                  FilledButton(
                    onPressed: () => _verify(context, ref, phys),
                    child: const Text('Verify'),
                  ),
              ],
            ),
            if (countedAt != null) ...[
              const SizedBox(height: 8),
              _kv('Last counted', df.format(countedAt)),
              if (countedBy != null && countedBy.trim().isNotEmpty)
                _kv('Counted by', countedBy.trim()),
            ],
            if (audit.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('Recent adjustments', style: HexaOp.caption(context).copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              for (final a in audit.take(3)) ...[
                _auditRow(a),
                const SizedBox(height: 6),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              k,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF64748B)),
            ),
          ),
          Text(
            v,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: valueColor ?? HexaColors.textBody),
          ),
        ],
      ),
    );
  }

  Widget _auditRow(Map<String, dynamic> a) {
    final atRaw = a['updated_at']?.toString();
    final at = atRaw != null ? DateTime.tryParse(atRaw)?.toLocal() : null;
    final df = DateFormat('dd MMM • h:mm a');
    final who = a['updated_by_name']?.toString();
    final t = stockAdjustmentTypeLabel(a['adjustment_type']?.toString());
    final oldQ = _fmt(coerceToDouble(a['old_qty']));
    final newQ = _fmt(coerceToDouble(a['new_qty']));
    return Row(
      children: [
        Expanded(
          child: Text(
            [
              t,
              if (who != null && who.trim().isNotEmpty) who.trim(),
              if (at != null) df.format(at),
            ].join(' • '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
          ),
        ),
        Text(
          '$oldQ → $newQ',
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
        ),
      ],
    );
  }

  Future<void> _verify(BuildContext context, WidgetRef ref, double countedQty) async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      await ref.read(hexaApiProvider).verifyStockCount(
            businessId: session.primaryBusiness.id,
            itemId: itemId,
            countedQty: countedQty,
            reason: 'Physical count',
          );
      ref.invalidate(itemDetailBundleProvider(itemId));
      ref.invalidate(stockItemActivityProvider(itemId));
      ref.invalidate(stockItemAuditProvider(itemId));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Physical count verified')),
      );
    } on DioException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyApiError(e))),
      );
    }
  }
}

String _fmt(double n) {
  if (!n.isFinite) return '—';
  if (n.abs() < 0.001) return '0';
  final s = n.toStringAsFixed(n.abs() < 1 ? 2 : 0);
  return s.replaceAll(RegExp(r'\.0+$'), '').replaceAll(RegExp(r'(\.\d*[1-9])0+$'), r'$1');
}

