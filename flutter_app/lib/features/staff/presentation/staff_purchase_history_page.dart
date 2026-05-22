import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/models/trade_purchase_models.dart';
import '../../../core/providers/trade_purchases_provider.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/utils/line_display.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../../../core/widgets/list_skeleton.dart';
import '../../../shared/widgets/operational_ui.dart';

/// Staff purchase list — search, period/status filters, qty and delivery only.
class StaffPurchaseHistoryPage extends ConsumerStatefulWidget {
  const StaffPurchaseHistoryPage({super.key});

  @override
  ConsumerState<StaffPurchaseHistoryPage> createState() =>
      _StaffPurchaseHistoryPageState();
}

class _StaffPurchaseHistoryPageState
    extends ConsumerState<StaffPurchaseHistoryPage> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  String _period = 'week';
  String? _statusFilter;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() => _query = _searchCtrl.text.trim().toLowerCase());
    });
  }

  DateTime get _from {
    final now = DateTime.now();
    if (_period == 'month') {
      return DateTime(now.year, now.month, 1);
    }
    final w = now.subtract(Duration(days: now.weekday - 1));
    return DateTime(w.year, w.month, w.day);
  }

  List<TradePurchase> _filter(List<TradePurchase> all) {
    return all.where((p) {
      final d = DateTime(
        p.purchaseDate.year,
        p.purchaseDate.month,
        p.purchaseDate.day,
      );
      if (d.isBefore(_from)) return false;
      if (_statusFilter == 'pending' && p.isDelivered) return false;
      if (_statusFilter == 'delivered' && !p.isDelivered) return false;
      if (_query.isEmpty) return true;
      final hay = [
        p.humanId,
        p.supplierName ?? '',
        for (final l in p.lines) l.itemName,
      ].join(' ').toLowerCase();
      return hay.contains(_query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final listAsync = ref.watch(tradePurchasesParsedProvider);

    return Scaffold(
      backgroundColor: HexaColors.brandBackground,
      appBar: AppBar(
        title: const Text('Purchase orders'),
        backgroundColor: Colors.transparent,
        foregroundColor: HexaColors.brandPrimary,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search supplier, order no., item…',
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => _searchCtrl.clear(),
                      ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFE0DDD8)),
                ),
              ),
            ),
          ),
          OperationalPillRow(
            labels: const ['This week', 'This month'],
            selected: _period == 'month' ? 'This month' : 'This week',
            height: 32,
            onSelected: (label) {
              setState(() => _period = label == 'This month' ? 'month' : 'week');
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in <String?>[null, 'pending', 'delivered'])
                  FilterChip(
                    label: Text(
                      s == null
                          ? 'All'
                          : s == 'pending'
                              ? 'Pending'
                              : 'Delivered',
                      style: const TextStyle(fontSize: 12),
                    ),
                    selected: _statusFilter == s,
                    onSelected: (_) => setState(() => _statusFilter = s),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ],
            ),
          ),
          Expanded(
            child: listAsync.when(
              loading: () => const ListSkeleton(rowCount: 8, rowHeight: 72),
              error: (_, __) => FriendlyLoadError(
                message: 'Could not load purchase history',
                onRetry: () => ref.invalidate(tradePurchasesListProvider),
              ),
              data: (rows) {
                final filtered = _filter(rows);
                if (filtered.isEmpty) {
                  return Center(
                    child: Text(
                      _query.isEmpty
                          ? 'No purchase orders in this period'
                          : 'No orders match your search',
                      style: HexaDsType.body(14, color: HexaDsColors.textMuted),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) {
                    final p = filtered[i];
                    return _StaffPurchaseRow(
                      purchase: p,
                      onTap: () => context.push(
                        '/staff/purchase-history/${p.id}',
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StaffPurchaseRow extends StatelessWidget {
  const _StaffPurchaseRow({required this.purchase, required this.onTap});

  final TradePurchase purchase;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sup = purchase.supplierName ?? 'Supplier';
    final initials = sup.isNotEmpty ? sup[0].toUpperCase() : '?';
    final date = purchase.purchaseDate;
    final ago = _relativeAge(date);
    final summary = purchase.lines
        .take(3)
        .map((l) {
          final q = formatLineQtyWeightFromTradeLine(l);
          return '${l.itemName} · $q';
        })
        .join(' · ');
    final statusLabel = purchase.isDelivered ? 'Delivered' : 'Pending';
    final statusColor =
        purchase.isDelivered ? const Color(0xFF0F766E) : const Color(0xFFD97706);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: const Color(0xFF0D9488).withValues(alpha: 0.15),
                child: Text(
                  initials,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0D9488),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${purchase.humanId} · $sup',
                      style: HexaDsType.bodyPrimary(context).copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${DateFormat('d MMM yyyy').format(date)}${ago != null ? ' · $ago' : ''}',
                      style: HexaDsType.bodySm(context),
                    ),
                    if (summary.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: HexaDsType.bodySm(context).copyWith(
                          fontWeight: FontWeight.w700,
                          color: HexaColors.brandPrimary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

String? _relativeAge(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final days = today.difference(day).inDays;
  if (days == 0) return 'today';
  if (days == 1) return 'yesterday';
  return '$days days ago';
}
