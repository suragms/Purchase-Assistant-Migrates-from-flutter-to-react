import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/api/hexa_api.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/json_coerce.dart';
import '../../../core/providers/home_dashboard_provider.dart';
import '../../../core/providers/stock_providers.dart';
import '../../../core/widgets/hexa_error_card.dart';
import '../stock_period_utils.dart';
/// Owner view of stock audit events for the selected app period.
class StockMovementPage extends ConsumerStatefulWidget {
  const StockMovementPage({super.key});

  @override
  ConsumerState<StockMovementPage> createState() => _StockMovementPageState();
}

class _StockMovementPageState extends ConsumerState<StockMovementPage> {
  bool _loading = true;
  Object? _loadError;
  List<Map<String, dynamic>> _rows = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    final session = ref.read(sessionProvider);
    if (session == null) {
      if (!mounted) return;
      setState(() => _loading = false);
      return;
    }
    if (!mounted) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final rows = await ref.read(hexaApiProvider).listStockAuditRecent(
            businessId: session.primaryBusiness.id,
            limit: HexaApi.stockAuditRecentMaxLimit,
          );
      if (!mounted) return;
      final range = homePeriodRange(ref.read(stockPagePeriodProvider));
      final endInclusive = range.end.subtract(const Duration(days: 1));
      final from = DateTime(range.start.year, range.start.month, range.start.day);
      final to = DateTime(
        endInclusive.year,
        endInclusive.month,
        endInclusive.day,
        23,
        59,
        59,
      );
      final filtered = <Map<String, dynamic>>[];
      for (final raw in rows) {
        final at = DateTime.tryParse(
              raw['created_at']?.toString() ??
                  raw['audited_at']?.toString() ??
                  '',
            ) ??
            DateTime.tryParse(raw['on']?.toString() ?? '');
        if (at == null) continue;
        if (at.isBefore(from) || at.isAfter(to)) continue;
        filtered.add(Map<String, dynamic>.from(raw));
      }
      filtered.sort((a, b) {
        final ta = DateTime.tryParse(a['created_at']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final tb = DateTime.tryParse(b['created_at']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return tb.compareTo(ta);
      });
      if (!mounted) return;
      setState(() {
        _rows = filtered;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = e;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(stockPagePeriodProvider, (_, __) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    });
    final period = ref.watch(stockPagePeriodProvider);

    var totalIn = 0.0;
    var totalOut = 0.0;
    for (final r in _rows) {
      final d = coerceToDouble(r['qty_delta'] ?? r['delta']);
      if (d >= 0) {
        totalIn += d;
      } else {
        totalOut += d.abs();
      }
    }

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.pop()),
        title: const Text(
          'Stock Movement',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                for (final p in const [
                  HomePeriod.today,
                  HomePeriod.week,
                  HomePeriod.month,
                  HomePeriod.allTime,
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      label: Text(p.label),
                      selected: period == p,
                      onSelected: (_) {
                        applyStockPagePeriod(ref, p);
                        _load();
                      },
                    ),
                  ),
              ],
            ),
          ),
          if (!_loading && _rows.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'Total in: +${totalIn.round()} · Total out: -${totalOut.round()} · Net: ${(totalIn - totalOut).round()}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _loadError != null
                    ? HexaErrorCard.fromError(
                        error: _loadError!,
                        title: 'Could not load stock movement',
                        onRetry: _load,
                      )
                    : _rows.isEmpty
                    ? Center(
                        child: Text(
                          'No stock events for ${period.label.toLowerCase()}',
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                        itemCount: _rows.length,
                        itemBuilder: (context, i) {
                          final r = _rows[i];
                          final d =
                              coerceToDouble(r['qty_delta'] ?? r['delta']);
                          final name = r['item_name']?.toString() ?? 'Item';
                          final unit = r['unit']?.toString() ?? '';
                          final reason = r['reason']?.toString() ??
                              r['adjustment_type']?.toString() ??
                              '';
                          final at = DateTime.tryParse(
                                r['created_at']?.toString() ?? '',
                              ) ??
                              DateTime.now();
                          final color = d >= 0
                              ? const Color(0xFF2E7D32)
                              : const Color(0xFFC62828);
                          return ListTile(
                            leading: Icon(
                              d >= 0
                                  ? Icons.arrow_downward_rounded
                                  : Icons.arrow_upward_rounded,
                              color: color,
                            ),
                            title: Text(
                              name,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              reason,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '${d >= 0 ? '+' : ''}${d.toStringAsFixed(d == d.roundToDouble() ? 0 : 1)} $unit',
                                  style: TextStyle(
                                    color: color,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  DateFormat('d MMM · HH:mm').format(at),
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
