import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/catalog/item_trade_history.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/errors/user_facing_errors.dart';
import '../../../core/models/trade_purchase_models.dart';
import '../../../core/router/navigation_ext.dart';

String _inr(num n) => NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    ).format(n);

/// Purchases that include a line for this catalog item (paged).
class CatalogItemPurchaseHistoryPage extends ConsumerStatefulWidget {
  const CatalogItemPurchaseHistoryPage({super.key, required this.itemId});

  final String itemId;

  @override
  ConsumerState<CatalogItemPurchaseHistoryPage> createState() =>
      _CatalogItemPurchaseHistoryPageState();
}

class _CatalogItemPurchaseHistoryPageState
    extends ConsumerState<CatalogItemPurchaseHistoryPage> {
  static const _page = 20;
  var _offset = 0;
  var _loading = true;
  var _loadingMore = false;
  String? _error;
  final _purchases = <TradePurchase>[];
  var _exhausted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(reset: true));
  }

  Future<void> _load({required bool reset}) async {
    final session = ref.read(sessionProvider);
    if (session == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _offset = 0;
        _purchases.clear();
        _exhausted = false;
      });
    } else {
      if (_exhausted || _loadingMore) return;
      setState(() {
        _loadingMore = true;
        _error = null;
      });
    }
    final off = reset ? 0 : _offset;
    try {
      final raw = await ref.read(hexaApiProvider).listTradePurchases(
            businessId: session.primaryBusiness.id,
            limit: _page,
            offset: off,
            status: 'all',
            catalogItemId: widget.itemId,
          );
      if (!mounted) return;
      final next = <TradePurchase>[];
      for (final e in raw) {
        try {
          next.add(TradePurchase.fromJson(Map<String, dynamic>.from(e as Map)));
        } catch (_) {}
      }
      setState(() {
        if (reset) {
          _purchases
            ..clear()
            ..addAll(next);
        } else {
          _purchases.addAll(next);
        }
        _offset = off + next.length;
        _exhausted = next.length < _page;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e, st) {
      logSilencedApiError(e, st);
      if (!mounted) return;
      setState(() {
        _error = userFacingError(e);
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  Future<void> _exportCsv() async {
    if (_purchases.isEmpty) return;
    final buf = StringBuffer('human_id,purchase_date,total_inr,line_summary\n');
    final want = widget.itemId.toLowerCase();
    for (final p in _purchases) {
      TradePurchaseLine? line;
      for (final l in p.lines) {
        if ((l.catalogItemId ?? '').toString().toLowerCase() == want) {
          line = l;
          break;
        }
      }
      final sub = line != null
          ? '${line.itemName} ${line.qty} ${line.unit}'
          : p.itemsSummary;
      final safe = sub.replaceAll('\n', ' ').replaceAll(',', ';');
      buf.write(
          '${p.humanId},${DateFormat('yyyy-MM-dd').format(p.purchaseDate)},${p.totalAmount.round()},$safe\n');
    }
    await Share.share(
      buf.toString(),
      subject: 'Purchase history · item ${widget.itemId}',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Purchase history (item)'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.popOrGo('/catalog'),
        ),
        actions: [
          IconButton(
            tooltip: 'Export CSV',
            onPressed: _purchases.isEmpty ? null : _exportCsv,
            icon: const Icon(Icons.ios_share_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : _purchases.isEmpty
                  ? Center(
                      child: Text(
                        'No purchases for this item yet',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () => _load(reset: true),
                      child: Builder(
                        builder: (context) {
                          final rows = itemTradeHistoryRows(
                            _purchases,
                            widget.itemId,
                          );
                          final totalsLine =
                              itemTradeHistoryTotalsLine(rows);
                          return ListView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
                            itemCount: _purchases.length +
                                (totalsLine.isNotEmpty ? 1 : 0) +
                                (_exhausted ? 0 : 1),
                            itemBuilder: (context, i) {
                              if (totalsLine.isNotEmpty && i == 0) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF0FDF4),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: const Color(0xFFBBF7D0),
                                      ),
                                    ),
                                    child: Text(
                                      '${rows.length} purchase(s) · Total $totalsLine',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF166534),
                                      ),
                                    ),
                                  ),
                                );
                              }
                              final pi = totalsLine.isNotEmpty ? i - 1 : i;
                              if (pi == _purchases.length) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Center(
                                child: _loadingMore
                                    ? const CircularProgressIndicator()
                                    : TextButton(
                                        onPressed: () => _load(reset: false),
                                        child: const Text('Load more'),
                                      ),
                              ),
                            );
                          }
                          final p = _purchases[pi];
                          TradePurchaseLine? line;
                          final want = widget.itemId.toLowerCase();
                          for (final l in p.lines) {
                            if ((l.catalogItemId ?? '')
                                    .toString()
                                    .toLowerCase() ==
                                want) {
                              line = l;
                              break;
                            }
                          }
                          final sub = line != null
                              ? '${line.itemName} · ${line.qty} ${line.unit}'
                              : p.itemsSummary;
                          return ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 2),
                            title: Text(
                              p.humanId,
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            subtitle: Text(
                              '${DateFormat.yMMMd().format(p.purchaseDate)} · $sub',
                              maxLines: 2,
                            ),
                            trailing: Text(
                              _inr(p.totalAmount.round()),
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            onTap: () => context.push(
                              '/purchase/detail/${p.id}',
                              extra: p,
                            ),
                          );
                            },
                          );
                        },
                      ),
                    ),
    );
  }
}
