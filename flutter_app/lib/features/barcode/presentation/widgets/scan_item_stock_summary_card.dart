import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/json_coerce.dart';
import '../../../../core/theme/hexa_colors.dart';
import '../../../../core/utils/unit_utils.dart';

/// Post-scan summary: system + physical stock, last purchase, last system edit.
class ScanItemStockSummaryCard extends StatelessWidget {
  const ScanItemStockSummaryCard({
    super.key,
    required this.item,
    this.showTitle = true,
  });

  final Map<String, dynamic> item;
  final bool showTitle;

  static String daysAgoLabel(DateTime? at) {
    if (at == null) return '';
    final d = DateTime.now().difference(at.toLocal());
    if (d.inDays == 0) return 'today';
    if (d.inDays == 1) return '1 day ago';
    if (d.inDays < 14) return '${d.inDays} days ago';
    return DateFormat('d MMM yy').format(at.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final name = item['name']?.toString() ?? 'Item';
    final code = item['item_code']?.toString() ?? '—';
    final bc = item['barcode']?.toString() ?? '—';
    final unit = item['unit']?.toString() ??
        item['stock_unit']?.toString() ??
        item['default_unit']?.toString() ??
        '';

    final system = coerceToDouble(item['current_stock']);
    final physical = coerceToDoubleNullable(
      item['physical_stock_qty'] ?? item['physical_count_qty'],
    );

    final lpDate = _parseDate(item['last_purchase_date']);
    final lpQty = coerceToDoubleNullable(item['last_purchase_qty']);
    final lpUnit = item['last_purchase_unit']?.toString().trim() ?? unit;
    final supplier = item['supplier_name']?.toString().trim() ?? '';
    final lpRate = coerceToDoubleNullable(item['last_purchase_rate']);

    final physAt = _parseDate(
      item['physical_stock_counted_at'] ?? item['physical_counted_at'],
    );
    final physBy = item['physical_stock_counted_by']?.toString().trim() ?? '';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showTitle) ...[
            Text(
              name,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              '$code · $bc',
              style: const TextStyle(fontSize: 12, color: HexaColors.textBody),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Expanded(
                child: _StockTile(
                  label: 'System stock',
                  qty: system,
                  unit: unit,
                  accent: const Color(0xFF0E4F46),
                  subtitle: _lastUpdatedLine(item),
                  compact: true,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _StockTile(
                  label: 'Physical count',
                  qty: physical,
                  unit: unit,
                  accent: const Color(0xFF2563EB),
                  subtitle: physical != null
                      ? [
                          if (physAt != null) daysAgoLabel(physAt),
                          if (physBy.isNotEmpty) physBy,
                        ].where((s) => s.isNotEmpty).join(' · ')
                      : 'Not counted yet',
                  emptyHint: '—',
                  compact: true,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _StockTile(
                  label: 'Last purchase',
                  qty: lpQty != null && lpQty > 0 ? lpQty : null,
                  unit: lpUnit,
                  accent: const Color(0xFFB45309),
                  subtitle: _lastPurchaseSubtitle(lpDate, supplier, lpRate),
                  emptyHint: 'Never',
                  compact: true,
                ),
              ),
            ],
          ),
          if (supplier.isNotEmpty || (lpRate != null && lpRate > 0)) ...[
            const SizedBox(height: 6),
            Text(
              _lastPurchaseSubtitle(lpDate, supplier, lpRate),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: HexaColors.textBody),
            ),
          ],
        ],
      ),
    );
  }

  static DateTime? _parseDate(dynamic raw) {
    if (raw is String && raw.isNotEmpty) return DateTime.tryParse(raw);
    if (raw is DateTime) return raw;
    return null;
  }

  static String _lastPurchaseSubtitle(
    DateTime? lpDate,
    String supplier,
    double? lpRate,
  ) {
    final parts = <String>[];
    if (lpDate != null) {
      parts.add(
        '${DateFormat('d MMM yy').format(lpDate.toLocal())} (${daysAgoLabel(lpDate)})',
      );
    }
    if (supplier.isNotEmpty) {
      parts.add(
        supplier.length > 28 ? '${supplier.substring(0, 28)}…' : supplier,
      );
    }
    if (lpRate != null && lpRate > 0) {
      parts.add(
        '₹${lpRate.toStringAsFixed(lpRate == lpRate.roundToDouble() ? 0 : 2)}',
      );
    }
    return parts.isEmpty ? 'From last bill' : parts.join(' · ');
  }

  static String _lastUpdatedLine(Map<String, dynamic> item) {
    final by = item['last_stock_updated_by']?.toString().trim() ?? '';
    final at = _parseDate(item['last_stock_updated_at']);
    if (by.isEmpty && at == null) return 'Ledger';
    final when = at != null ? daysAgoLabel(at) : '';
    if (by.isNotEmpty && when.isNotEmpty) return '$when · $by';
    if (by.isNotEmpty) return by;
    return when;
  }
}

class _StockTile extends StatelessWidget {
  const _StockTile({
    required this.label,
    required this.qty,
    required this.unit,
    required this.accent,
    required this.subtitle,
    this.emptyHint = '—',
    this.compact = false,
  });

  final String label;
  final double? qty;
  final String unit;
  final Color accent;
  final String subtitle;
  final String emptyHint;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final unitUp = unit.isNotEmpty ? unit.toUpperCase() : '';
    final value = qty != null
        ? '${formatStockQtyNumber(qty!)}${unitUp.isNotEmpty ? ' $unitUp' : ''}'
        : emptyHint;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: accent,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: compact ? 15 : 18,
              fontWeight: FontWeight.w900,
              color: accent,
              height: 1.1,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }
}
