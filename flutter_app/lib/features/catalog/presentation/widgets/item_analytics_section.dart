import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/hexa_operational_tokens.dart';
import '../../../../core/json_coerce.dart';
import '../../../../core/providers/item_detail_providers.dart';
import '../../../../core/providers/stock_providers.dart'
    show stockItemDetailProvider;
import '../../../../core/utils/unit_utils.dart';
import '../../../../core/widgets/friendly_load_error.dart';

class ItemAnalyticsSection extends ConsumerStatefulWidget {
  const ItemAnalyticsSection({
    super.key,
    required this.itemId,
    this.loadIntelligence = false,
  });

  final String itemId;
  final bool loadIntelligence;

  @override
  ConsumerState<ItemAnalyticsSection> createState() =>
      _ItemAnalyticsSectionState();
}

class _ItemAnalyticsSectionState extends ConsumerState<ItemAnalyticsSection> {
  bool _autoRetried = false;

  void _invalidateSection() {
    ref.invalidate(itemStockIntelligenceProvider(widget.itemId));
    ref.invalidate(stockItemDetailProvider(widget.itemId));
  }

  void _scheduleAutoRetryOnce() {
    if (_autoRetried) return;
    _autoRetried = true;
    unawaited(
      Future<void>.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          ref.invalidate(itemStockIntelligenceProvider(widget.itemId));
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stockAsync = ref.watch(itemDetailStockProvider(widget.itemId));
    final intelAsync = widget.loadIntelligence
        ? ref.watch(itemStockIntelligenceProvider(widget.itemId))
        : null;

    if (stockAsync.hasError && !stockAsync.hasValue) {
      _scheduleAutoRetryOnce();
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(HexaOp.cardPadding),
          child: FriendlyLoadError(
            message: 'Could not load analytics',
            onRetry: _invalidateSection,
          ),
        ),
      );
    }

    if (widget.loadIntelligence &&
        intelAsync != null &&
        intelAsync.hasError &&
        !intelAsync.hasValue) {
      _scheduleAutoRetryOnce();
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(HexaOp.cardPadding),
          child: FriendlyLoadError(
            message: 'Could not load movement intelligence',
            onRetry: _invalidateSection,
          ),
        ),
      );
    }

    if (stockAsync.isLoading && !stockAsync.hasValue) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final stock = stockAsync.valueOrNull ?? const <String, dynamic>{};
    final intel = widget.loadIntelligence
        ? intelAsync?.valueOrNull ?? const <String, dynamic>{}
        : const <String, dynamic>{};

    final unit =
        (stock['stock_unit'] ?? stock['unit'] ?? '').toString().trim().toUpperCase();
    final unitLabel = unit.isEmpty ? 'UNIT' : unit;

    final current = coerceToDouble(stock['current_stock']);
    final purchased = coerceToDouble(
      intel['period_purchased_qty'] ?? stock['period_purchased_qty'],
    );
    final usage = coerceToDouble(intel['period_usage_qty']);
    final needsVerify =
        intel['needs_verification'] == true || stock['needs_verification'] == true;
    final openingUnset = stock['opening_stock_set_at'] == null &&
        current == 0 &&
        purchased == 0;

    if (purchased == 0 && usage == 0 && !openingUnset) {
      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(HexaOp.cardPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Item analytics', style: HexaOp.cardTitle(context)),
              const SizedBox(height: 10),
              const Text(
                'No data yet — analytics will appear after first purchase.',
                style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    const assumedDays = 30.0;
    final daily = usage > 0 ? usage / assumedDays : 0.0;
    final daysRemaining = (daily > 0.0001) ? (current / daily) : null;

    String reorderHint() {
      if (openingUnset) {
        return 'Opening stock not set yet — reorder hints need movement history.';
      }
      if (daysRemaining == null) {
        return 'Not enough movement data to predict reorder.';
      }
      final d = daysRemaining.clamp(0, 9999);
      if (d <= 3) {
        return 'Reorder immediately (≈${d.toStringAsFixed(0)} days remaining).';
      }
      if (d <= 7) {
        return 'Reorder soon (≈${d.toStringAsFixed(0)} days remaining).';
      }
      if (d <= 15) {
        return 'Plan reorder (≈${d.toStringAsFixed(0)} days remaining).';
      }
      return 'Stock looks healthy (≈${d.toStringAsFixed(0)} days remaining).';
    }

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(HexaOp.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Item analytics', style: HexaOp.cardTitle(context)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 6,
              children: [
                _pill('Current ${formatStockQtyNumber(current)} $unitLabel'),
                if (openingUnset) _pill('Opening stock not set'),
                if (purchased > 0)
                  _pill('Purchased (period) ${formatStockQtyNumber(purchased)}'),
                if (usage > 0)
                  _pill('Moved/used (period) ${formatStockQtyNumber(usage)}'),
                if (daily > 0) _pill('Avg/day ${formatStockQtyNumber(daily)}'),
                if (needsVerify) _pill('Verification needed'),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: const Color(0xFF1565C0).withValues(alpha: 0.08),
                border: Border.all(
                  color: const Color(0xFF1565C0).withValues(alpha: 0.25),
                ),
              ),
              child: Text(
                reorderHint(),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Reorder hint uses the last 30 days movement as a baseline. It is advisory only.',
              style: HexaOp.caption(context),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _pill(String t) => Chip(
        label: Text(
          t,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
        ),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );
}
