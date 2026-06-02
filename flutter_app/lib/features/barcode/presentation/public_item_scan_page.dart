import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/json_coerce.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/utils/unit_utils.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../../../core/widgets/list_skeleton.dart';
import 'widgets/scan_item_stock_summary_card.dart';

/// Read-only stock view for QR label scans (no login required).
class PublicItemScanPage extends StatefulWidget {
  const PublicItemScanPage({super.key, required this.lookupKey});

  /// Public token, item code, or barcode from label URL `/item/:lookupKey`.
  final String lookupKey;

  @override
  State<PublicItemScanPage> createState() => _PublicItemScanPageState();
}

class _PublicItemScanPageState extends State<PublicItemScanPage> {
  late final Future<Map<String, dynamic>> _load;

  @override
  void initState() {
    super.initState();
    _load = _fetch();
  }

  Future<Map<String, dynamic>> _fetch() async {
    final dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.resolvedApiBaseUrl,
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 12),
      ),
    );
    final res = await dio.get<Map<String, dynamic>>(
      '/public/items/${Uri.encodeComponent(widget.lookupKey)}.json',
    );
    return Map<String, dynamic>.from(res.data ?? const {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HexaColors.brandBackground,
      appBar: AppBar(
        title: const Text('Item Lookup - Harisree'),
        backgroundColor: Colors.transparent,
        foregroundColor: HexaColors.brandPrimary,
        automaticallyImplyLeading: false,
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _load,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Padding(
              padding: EdgeInsets.all(20),
              child: ListSkeleton(rowCount: 5, rowHeight: 72),
            );
          }
          if (snap.hasError) {
            return FriendlyLoadError(
              message: _publicLoadMessage(snap.error),
              onRetry: () => setState(() => _load = _fetch()),
            );
          }
          final data = snap.data ?? const {};
          final name = data['name']?.toString() ?? 'Item';
          final category = data['category']?.toString() ?? 'Catalog item';
          final code = data['item_code']?.toString() ?? '—';
          final rack = data['rack_location']?.toString() ?? '—';
          final rawStatus = data['status']?.toString() ?? 'healthy';
          final statusLabel =
              rawStatus.replaceAll('_', ' ').toUpperCase();
          final isLow = rawStatus == 'low_stock';
          final isOut = rawStatus == 'out_of_stock';
          final statusColor = isOut
              ? const Color(0xFF6B7280)
              : isLow
                  ? const Color(0xFFD97706)
                  : const Color(0xFF059669);
          final system = coerceToDouble(data['current_stock']);
          final unit = data['unit']?.toString() ?? data['stock_unit']?.toString() ?? '';

          // Last purchase summary for the chip row
          final lpQty = coerceToDoubleNullable(data['last_purchase_qty']);
          final lpUnit =
              data['last_purchase_unit']?.toString().trim() ?? unit;
          final lpRate = coerceToDoubleNullable(data['last_purchase_rate']);
          final lpDateRaw = data['last_purchase_date']?.toString();
          final lpDate =
              lpDateRaw != null ? DateTime.tryParse(lpDateRaw) : null;
          final supplier =
              data['supplier_name']?.toString().trim() ?? '';

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              // ── Category + name ──────────────────────────────────────
              Text(
                category,
                style: HexaDsType.body(13, color: HexaDsColors.textMuted),
              ),
              const SizedBox(height: 4),
              Text(name, style: HexaDsType.heading(22)),
              const SizedBox(height: 16),

              // ── Current stock hero card ───────────────────────────────
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0x140E4F46),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0x330E4F46),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CURRENT STOCK',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0E4F46),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${formatQtyForDisplay(system)}'
                      '${unit.isNotEmpty ? ' ${unit.toUpperCase()}' : ''}',
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0E4F46),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.topRight,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                              color: statusColor.withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          statusLabel,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: statusColor,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // ── Last purchase chip row ────────────────────────────────
              if (lpQty != null && lpQty > 0) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFED7AA)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.receipt_long_outlined,
                          size: 18, color: Color(0xFFB45309)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            style: const TextStyle(
                                fontSize: 13, color: Color(0xFF92400E)),
                            children: [
                              const TextSpan(
                                  text: 'Last purchase  ',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w600)),
                              TextSpan(
                                text:
                                    '${formatStockQtyNumber(lpQty)} ${lpUnit.toUpperCase()}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15),
                              ),
                              if (lpRate != null && lpRate > 0)
                                TextSpan(
                                  text:
                                      '  ·  ₹${lpRate.toStringAsFixed(lpRate == lpRate.roundToDouble() ? 0 : 2)}',
                                ),
                              if (supplier.isNotEmpty)
                                TextSpan(text: '  ·  $supplier'),
                              if (lpDate != null)
                                TextSpan(
                                  text:
                                      '  ·  ${ScanItemStockSummaryCard.daysAgoLabel(lpDate)}',
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // ── Full summary card (system + physical + last purchase tiles) ──
              ScanItemStockSummaryCard(item: data, showTitle: false),
              const SizedBox(height: 16),

              // ── Meta ──────────────────────────────────────────────────
              Text('Item code: $code', style: HexaDsType.bodySm(context)),
              Text(
                'Barcode: ${data['barcode']?.toString() ?? '—'}',
                style: HexaDsType.bodySm(context),
              ),
              Text('Rack: $rack', style: HexaDsType.bodySm(context)),
              const SizedBox(height: 16),
              Text(
                'Read-only · open the Harisree app to update stock.',
                textAlign: TextAlign.center,
                style: HexaDsType.body(12, color: HexaDsColors.textMuted),
              ),
              const SizedBox(height: 8),
              Center(
                child: OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('Open App'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static String _publicLoadMessage(Object? error) {
    if (error is DioException) {
      final sc = error.response?.statusCode;
      if (sc == 404) return 'Item not found or link expired.';
      if (sc == 401 || sc == 403) {
        return 'This link is read-only. Try scanning the QR on the label again.';
      }
      if (sc != null && sc >= 500) {
        return 'Server is waking up. Pull to refresh in a moment.';
      }
    }
    return 'Could not load item. Check your connection and try again.';
  }
}
