import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/utils/line_display.dart';
import '../../core/utils/unit_utils.dart';
import '../../core/utils/phone_launch.dart';

double? tradeIntelToDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

String tradeIntelFormatInr(num? n, {int decimalDigits = 0}) {
  if (n == null) return '—';
  return NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: decimalDigits,
  ).format(n);
}

String tradeIntelFormatQty(num? n) {
  if (n == null) return '';
  final rounded = n.roundToDouble();
  if ((n - rounded).abs() < 0.001) return rounded.round().toString();
  return n.toStringAsFixed(2);
}

/// Calendar-day relative label for a purchase date (date-only, local).
String tradeIntelRelativeAgeLabel(DateTime purchaseDay) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final d = DateTime(purchaseDay.year, purchaseDay.month, purchaseDay.day);
  final days = today.difference(d).inDays;
  if (days == 0) return 'today';
  if (days == 1) return 'yesterday';
  return '$days days ago';
}

/// Parses `YYYY-MM-DD` prefix from API date strings; returns null if invalid.
String? tradeIntelRelativeAgeFromIsoDateString(String raw) {
  final t = raw.trim();
  if (t.length < 10) return null;
  final parsed = DateTime.tryParse(t.substring(0, 10));
  if (parsed == null) return null;
  return tradeIntelRelativeAgeLabel(parsed);
}

String tradeIntelFormatSearchBillDate(String raw) {
  final t = raw.trim();
  if (t.length < 10) return t;
  final parsed = DateTime.tryParse(t.substring(0, 10));
  if (parsed == null) {
    return t.length >= 10 ? t.substring(0, 10) : t;
  }
  return DateFormat('d MMM yyyy').format(parsed);
}

/// Qty + weight for catalog / ledger intel maps (bags · kg order via [formatLineQtyWeight]).
String tradeIntelQtySummaryLine(Map<String, dynamic> m) {
  final kg = tradeIntelToDouble(m['last_line_weight_kg']);
  final qty = tradeIntelToDouble(m['last_line_qty']);
  final unit = (m['last_line_unit'] ?? '').toString();
  final kpu = tradeIntelToDouble(m['kg_per_unit']);
  if (qty != null && qty > 1e-6 && unit.trim().isNotEmpty) {
    final uRaw = unit.trim().toLowerCase();
    final u = uRaw == 'sack' ? 'bag' : uRaw;
    if (u == 'bag') {
      // Intel gives last_line_weight_kg; fall back to qty*kpu if needed.
      final wk =
          (kg != null && kg > 1e-6) ? kg : ((kpu != null && kpu > 0) ? qty * kpu : 0.0);
      return formatPackagedQty(unit: 'bag', pieces: qty, kg: wk);
    }
    if (u == 'box') return formatPackagedQty(unit: 'box', pieces: qty);
    if (u == 'tin') return formatPackagedQty(unit: 'tin', pieces: qty);
    if (u == 'kg') return formatPackagedQty(unit: 'kg', pieces: qty);
    return formatLineQtyWeight(
      qty: qty,
      unit: unit,
      kgPerUnit: kpu,
      totalWeightKg: kg,
    );
  }
  if (kg != null && kg > 1e-6) {
    return formatPackagedQty(unit: 'kg', pieces: kg);
  }
  return '';
}

/// Volume from category trade-summary rows (`period_weight_kg`, `period_qty_bags`).
String tradeIntelPeriodVolumeLine(Map<String, dynamic> m) {
  final kg = tradeIntelToDouble(m['period_weight_kg']);
  final bags = tradeIntelToDouble(m['period_qty_bags']);
  final parts = <String>[];
  if (kg != null && kg > 1e-6) {
    parts.add('${tradeIntelFormatQty(kg)} KG');
  }
  if (bags != null && bags > 1e-6) {
    parts.add('${tradeIntelFormatQty(bags)} BAGS');
  }
  if (parts.isEmpty) return '';
  return 'Volume: ${parts.join(' • ')}';
}

/// Period line amount (confirmed trade) for category rows.
String tradeIntelPeriodAmountLine(
  Map<String, dynamic> m, {
  bool hideFinancials = false,
}) {
  if (hideFinancials) return '';
  final a = tradeIntelToDouble(m['period_line_total']);
  if (a == null || a <= 1e-6) return '';
  return 'Total amount: ${tradeIntelFormatInr(a)}';
}

/// Last purchase → last selling (confirmed [last_selling_rate] only — no catalog defaults).
String tradeIntelRatePairLine(
  Map<String, dynamic> m, {
  bool hideFinancials = false,
}) {
  if (hideFinancials) return '';
  var buy = tradeIntelToDouble(m['last_purchase_price']);
  if (buy == null || buy <= 0) {
    final lineTotal = tradeIntelToDouble(m['last_line_total']);
    final qty = tradeIntelToDouble(m['last_line_qty']);
    if (lineTotal != null &&
        lineTotal > 0 &&
        qty != null &&
        qty > 0) {
      buy = lineTotal / qty;
    }
  }
  final sell = tradeIntelToDouble(m['last_selling_rate']);
  if ((buy == null || buy <= 0) && (sell == null || sell <= 0)) {
    return '';
  }
  final b = buy != null && buy > 0 ? tradeIntelFormatInr(buy) : '₹0';
  final s = sell != null && sell > 0 ? tradeIntelFormatInr(sell) : '—';
  String suf(dynamic v) {
    final q = v?.toString().trim() ?? '';
    return q.isEmpty ? '' : '/$q';
  }

  final buyQ = m['purchase_rate_dim'];
  final sellQ = m['selling_rate_dim'];
  return 'Last: $b${suf(buyQ)} → $s${suf(sellQ)}';
}

/// Last-line bags / tins / est. bags from kg ÷ kg-per-bag (compact).
String tradeIntelLastPurchaseBagsLabel(Map<String, dynamic> m) {
  final qty = tradeIntelToDouble(m['last_line_qty']);
  final unit = (m['last_line_unit'] ?? '').toString().toLowerCase().trim();
  final kg = tradeIntelToDouble(m['last_line_weight_kg']);
  if (qty != null && qty > 1e-6) {
    if (unit == 'bag' || unit == 'sack') {
      final kgPer = tradeIntelToDouble(m['kg_per_unit']);
      final primary = stockDisplayPrimary(qty, unit);
      final sec = stockDisplaySecondary(qty, unit, kgPer, null);
      return sec == null ? primary : '$primary · $sec';
    }
    if (unit == 'box') return '${tradeIntelFormatQty(qty)} box';
    if (unit == 'tin') {
      final kgTin = tradeIntelToDouble(m['kg_per_unit']);
      final primary = stockDisplayPrimary(qty, 'tin');
      final sec = stockDisplaySecondary(qty, 'tin', null, kgTin);
      return sec == null ? primary : '$primary · $sec';
    }
    if (unit == 'kg') return '${tradeIntelFormatQty(qty)} kg';
  }
  if (kg != null && kg > 1e-6) {
    return '${tradeIntelFormatQty(kg)} kg';
  }
  return '';
}

/// Confirmed last-purchase facts only (no catalog guide / default rates).
String tradeIntelSearchCatalogSubtitle(
  Map<String, dynamic> m, {
  bool hideFinancials = false,
}) {
  final parts = <String>[];
  if (!hideFinancials) {
  final buy = tradeIntelToDouble(m['last_purchase_price']);
  final sell = tradeIntelToDouble(m['last_selling_rate']);
  if (buy != null && buy > 0) {
    if (sell != null && sell > 0) {
      parts.add(
          'Last buy ${tradeIntelFormatInr(buy)} · Last sell ${tradeIntelFormatInr(sell)}');
    } else {
      parts.add('Last buy ${tradeIntelFormatInr(buy)}');
    }
  } else if (sell != null && sell > 0) {
    parts.add('Last sell ${tradeIntelFormatInr(sell)}');
  }
  }
  final bags = tradeIntelLastPurchaseBagsLabel(m);
  if (bags.isNotEmpty) parts.add(bags);
  final hid = (m['last_purchase_human_id'] ?? '').toString().trim();
  if (hid.isNotEmpty) parts.add(hid);
  if (parts.isEmpty) return '';
  return parts.join(' · ');
}

/// Rich fact line for unified-search catalog tiles (qty / bill id emphasized).
Widget tradeIntelCatalogSearchFactRichText(
  BuildContext context,
  Map<String, dynamic> m, {
  bool hideFinancials = false,
}) {
  final tt = Theme.of(context).textTheme;
  final cs = Theme.of(context).colorScheme;
  final base = tt.bodySmall?.copyWith(
    color: cs.onSurface,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );
  final qtyStyle = tt.bodySmall?.copyWith(
    color: cs.error,
    fontWeight: FontWeight.w800,
    height: 1.3,
  );
  final hidStyle = tt.bodySmall?.copyWith(
    color: cs.onSurfaceVariant,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );
  final spans = <InlineSpan>[];
  void addSep() {
    if (spans.isEmpty) return;
    spans.add(TextSpan(text: ' · ', style: base));
  }

  if (!hideFinancials) {
    final buy = tradeIntelToDouble(m['last_purchase_price']);
    final sell = tradeIntelToDouble(m['last_selling_rate']);
    if (buy != null && buy > 0) {
      if (sell != null && sell > 0) {
        spans.add(
          TextSpan(
            text:
                'Last buy ${tradeIntelFormatInr(buy)} · Last sell ${tradeIntelFormatInr(sell)}',
            style: base,
          ),
        );
      } else {
        spans.add(
          TextSpan(
            text: 'Last buy ${tradeIntelFormatInr(buy)}',
            style: base,
          ),
        );
      }
    } else if (sell != null && sell > 0) {
      spans.add(
        TextSpan(
          text: 'Last sell ${tradeIntelFormatInr(sell)}',
          style: base,
        ),
      );
    }
  }
  final bags = tradeIntelLastPurchaseBagsLabel(m);
  if (bags.isNotEmpty) {
    addSep();
    spans.add(TextSpan(text: bags, style: qtyStyle));
  }
  final hid = (m['last_purchase_human_id'] ?? '').toString().trim();
  if (hid.isNotEmpty) {
    addSep();
    spans.add(TextSpan(text: hid, style: hidStyle));
  }
  if (spans.isEmpty) return const SizedBox.shrink();
  return Text.rich(TextSpan(children: spans));
}

String tradeIntelSourceLine(Map<String, dynamic> m) {
  final sup = (m['last_supplier_name'] ?? '').toString().trim();
  final bro = (m['last_broker_name'] ?? '').toString().trim();
  if (sup.isEmpty && bro.isEmpty) return '';
  if (sup.isNotEmpty && bro.isNotEmpty) return 'From: $sup · $bro';
  if (sup.isNotEmpty) return 'From: $sup';
  return 'Broker: $bro';
}

Map<String, dynamic> tradeIntelMapFromCategorySummaryItem(Map<String, dynamic> row) {
  return {
    'last_purchase_price': row['last_purchase_price'],
    'last_selling_rate': row['last_selling_rate'],
    'last_supplier_name': row['last_supplier_name'],
    'last_broker_name': row['last_broker_name'],
    'last_trade_human_id': row['last_trade_human_id'],
  };
}

/// One catalog item row from [categoryTradeSummary] `items` list.
class TradeIntelCategoryItemTile extends StatelessWidget {
  const TradeIntelCategoryItemTile({
    super.key,
    required this.row,
    required this.onTap,
    this.showChevron = true,
  });

  final Map<String, dynamic> row;
  final VoidCallback? onTap;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final name = (row['name'] ?? 'Item').toString();
    final vol = tradeIntelPeriodVolumeLine(row);
    final spend = tradeIntelPeriodAmountLine(row);
    final rate = tradeIntelRatePairLine(tradeIntelMapFromCategorySummaryItem(row));
    final src = tradeIntelSourceLine(tradeIntelMapFromCategorySummaryItem(row));
    final billHid = (row['last_trade_human_id'] ?? '').toString().trim();

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.inventory_2_outlined, color: cs.primary, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: tt.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                  if (spend.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      spend,
                      style: tt.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                  ],
                  if (vol.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      vol,
                      style: tt.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (rate.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      rate,
                      style: tt.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (billHid.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Last bill $billHid',
                      style: tt.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (src.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      src,
                      style: tt.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (showChevron)
              const Icon(Icons.chevron_right_rounded, size: 22),
          ],
        ),
      ),
    );
  }
}

/// Compact card for global search catalog hits (2–3 lines, business-first).
class TradeIntelCatalogSearchTile extends StatelessWidget {
  const TradeIntelCatalogSearchTile({
    super.key,
    required this.item,
    required this.onTap,
    this.fuzzyNameMatch = false,
    this.hideFinancials = false,
  });

  final Map<String, dynamic> item;
  final VoidCallback? onTap;
  /// When true, hide numeric last-buy/sell lines (approximate title match).
  final bool fuzzyNameMatch;
  /// Staff / privacy: hide purchase rates and amounts.
  final bool hideFinancials;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final name = (item['name'] ?? 'Item').toString();
    final srcLine = fuzzyNameMatch ? '' : tradeIntelSourceLine(item);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.inventory_2_outlined, color: cs.primary, size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: tt.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                  if (fuzzyNameMatch) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Approximate name match — open item to verify details.',
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                  ],
                  if (!fuzzyNameMatch &&
                      tradeIntelSearchCatalogSubtitle(
                        item,
                        hideFinancials: hideFinancials,
                      ).isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: tradeIntelCatalogSearchFactRichText(
                        context,
                        item,
                        hideFinancials: hideFinancials,
                      ),
                    ),
                  ],
                  if (!fuzzyNameMatch && item['last_purchase_date'] != null) ...[
                    const SizedBox(height: 2),
                    Builder(
                      builder: (ctx) {
                        final rawDate =
                            item['last_purchase_date']?.toString() ?? '';
                        final parsed = rawDate.length >= 10
                            ? DateTime.tryParse(rawDate.substring(0, 10))
                            : DateTime.tryParse(rawDate);
                        if (parsed == null) return const SizedBox.shrink();
                        final label = tradeIntelRelativeAgeLabel(parsed);
                        final delRaw = item['last_purchase_delivered'];
                        final delLabel = delRaw is bool
                            ? (delRaw ? 'Delivered' : 'Undelivered')
                            : null;
                        final ctxCs = Theme.of(ctx).colorScheme;
                        final ctxTt = Theme.of(ctx).textTheme;
                        final muted = ctxTt.bodySmall?.copyWith(
                          color: ctxCs.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        );
                        final ageStyle = ctxTt.bodySmall?.copyWith(
                          color: ctxCs.error,
                          fontWeight: FontWeight.w800,
                          height: 1.3,
                        );
                        final deliveredStyle = ctxTt.bodySmall?.copyWith(
                          color: ctxCs.primary,
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                        );
                        final undeliveredStyle = ctxTt.bodySmall?.copyWith(
                          color: ctxCs.error,
                          fontWeight: FontWeight.w800,
                          height: 1.3,
                        );
                        return Text.rich(
                          TextSpan(
                            style: muted,
                            children: [
                              TextSpan(
                                text: DateFormat('d MMM yyyy').format(parsed),
                              ),
                              TextSpan(text: ' · ', style: muted),
                              TextSpan(text: label, style: ageStyle),
                              if (delLabel != null) ...[
                                TextSpan(text: ' · ', style: muted),
                                TextSpan(
                                  text: delLabel,
                                  style: delRaw == true
                                      ? deliveredStyle
                                      : undeliveredStyle,
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                  if (srcLine.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      srcLine,
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.25,
                      ),
                    ),
                  ],
                  if (!fuzzyNameMatch)
                    _TradeIntelCatalogSearchPartyRow(item: item),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// Supplier / broker quick actions for unified search catalog tiles (call + profile).
class _TradeIntelCatalogSearchPartyRow extends StatelessWidget {
  const _TradeIntelCatalogSearchPartyRow({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final supName = (item['last_supplier_name'] ?? '').toString().trim();
    final broName = (item['last_broker_name'] ?? '').toString().trim();
    final supId = (item['last_supplier_id'] ?? '').toString().trim();
    final broId = (item['last_broker_id'] ?? '').toString().trim();
    final supPhone = (item['last_supplier_phone'] ?? '').toString().trim();
    final broPhone = (item['last_broker_phone'] ?? '').toString().trim();
    if (supName.isEmpty &&
        broName.isEmpty &&
        supPhone.isEmpty &&
        broPhone.isEmpty &&
        supId.isEmpty &&
        broId.isEmpty) {
      return const SizedBox.shrink();
    }

    Widget line({
      required String title,
      required String name,
      required String id,
      required String phone,
      required String routePrefix,
    }) {
      final hasName = name.isNotEmpty;
      final hasPhone = phone.isNotEmpty;
      final hasId = id.isNotEmpty;
      if (!hasName && !hasPhone && !hasId) return const SizedBox.shrink();
      final label = hasName ? name : (hasId ? title : '—');
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tt.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
            if (hasId)
              IconButton(
                tooltip: 'Open',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                    minWidth: 36, minHeight: 36),
                icon: Icon(Icons.open_in_new, size: 18, color: cs.primary),
                onPressed: () => context.push('$routePrefix$id'),
              ),
            if (hasPhone)
              IconButton(
                tooltip: 'Call',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                    minWidth: 36, minHeight: 36),
                icon: const Icon(Icons.call_outlined, size: 20),
                onPressed: () => dialPhone(phone),
              ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        line(
          title: 'Supplier',
          name: supName,
          id: supId,
          phone: supPhone,
          routePrefix: '/supplier/',
        ),
        line(
          title: 'Broker',
          name: broName,
          id: broId,
          phone: broPhone,
          routePrefix: '/broker/',
        ),
      ],
    );
  }
}
