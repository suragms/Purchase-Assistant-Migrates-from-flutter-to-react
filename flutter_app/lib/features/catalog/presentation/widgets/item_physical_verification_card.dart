import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/auth/auth_error_messages.dart';
import '../../../../core/stock/stock_version_retry.dart';
import '../../../../core/auth/dashboard_role.dart';
import '../../../../core/auth/session_notifier.dart';
import '../../../../core/design_system/hexa_operational_tokens.dart';
import '../../../../core/json_coerce.dart';
import '../../../../core/providers/item_detail_providers.dart';
import '../../../../core/providers/stock_providers.dart'
    show
        applyStockItemDetailFromSave,
        stockItemAuditProvider,
        stockItemDetailProvider;
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

class ItemPhysicalVerificationCard extends ConsumerStatefulWidget {
  const ItemPhysicalVerificationCard({super.key, required this.itemId});

  final String itemId;

  @override
  ConsumerState<ItemPhysicalVerificationCard> createState() =>
      _ItemPhysicalVerificationCardState();
}

class _ItemPhysicalVerificationCardState
    extends ConsumerState<ItemPhysicalVerificationCard> {
  static const _maxRetries = 3;
  static const _retryDelay = Duration(milliseconds: 1500);

  int _retryCount = 0;
  Timer? _retryTimer;
  bool _retryScheduled = false;

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  void _scheduleAutoRetry() {
    if (_retryScheduled || _retryCount >= _maxRetries || !mounted) return;
    _retryScheduled = true;
    _retryTimer?.cancel();
    _retryTimer = Timer(_retryDelay, () {
      if (!mounted) return;
      _retryScheduled = false;
      _retryCount++;
      ref.invalidate(stockItemDetailProvider(widget.itemId));
    });
  }

  @override
  Widget build(BuildContext context) {
    final stockAsync = ref.watch(itemDetailStockProvider(widget.itemId));
    final stockRow = stockAsync.valueOrNull;
    final needsAudit = stockRow != null &&
        (stockRow['physical_stock_counted_at'] != null ||
            stockRow['needs_verification'] == true);
    final auditAsync = needsAudit
        ? ref.watch(stockItemAuditProvider(widget.itemId))
        : const AsyncValue<List<Map<String, dynamic>>>.data([]);

    stockAsync.whenOrNull(
      data: (_) {
        if (_retryCount > 0 || _retryScheduled) {
          _retryCount = 0;
          _retryScheduled = false;
          _retryTimer?.cancel();
        }
      },
    );

    return stockAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) {
        if (_retryCount < _maxRetries) {
          _scheduleAutoRetry();
          return const SizedBox.shrink();
        }
        return Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Could not load verification log',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    _retryCount = 0;
                    ref.invalidate(stockItemDetailProvider(widget.itemId));
                    ref.invalidate(stockItemAuditProvider(widget.itemId));
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        );
      },
      data: (stock) => auditAsync.when(
        loading: () => _buildCard(context, ref, stock, const []),
        error: (_, __) => _buildCard(context, ref, stock, const []),
        data: (audit) => _buildCard(context, ref, stock, audit),
      ),
    );
  }

  Widget _buildCard(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> stock,
    List<Map<String, dynamic>> audit,
  ) {
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
    final stock =
        ref.read(itemDetailStockProvider(widget.itemId)).valueOrNull ??
            const <String, dynamic>{};
    try {
      final saved = await ref.read(hexaApiProvider).verifyStockCountWithRetry(
            businessId: session.primaryBusiness.id,
            itemId: widget.itemId,
            countedQty: countedQty,
            reason: 'Physical count',
            initialStockVersion: stockVersionFromItem(stock),
          );
      applyStockItemDetailFromSave(ref, itemId: widget.itemId, saved: saved);
      ref.invalidate(stockItemAuditProvider(widget.itemId));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Physical count verified')),
      );
    } on StaleStockConflict {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(StaleStockConflict.userMessage)),
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
