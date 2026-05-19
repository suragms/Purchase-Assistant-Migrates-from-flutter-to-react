import 'dart:math' as math;

import 'package:barcode/barcode.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/models/trade_purchase_models.dart'
    show TradePurchase, TradePurchaseLine;
import '../../../core/router/navigation_ext.dart';
import '../../../core/units/dynamic_unit_label_engine.dart' as unit_lbl;
import '../../../core/utils/trade_purchase_rate_display.dart';
import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/router/post_auth_route.dart' show sessionIsStaff;
import '../../../core/catalog/item_trade_history.dart';
import '../../../core/providers/business_aggregates_invalidation.dart';
import '../../../core/providers/business_profile_provider.dart';
import '../../../core/providers/business_write_revision.dart';
import '../../../core/providers/catalog_providers.dart';
import '../../../core/providers/suppliers_list_provider.dart';
import '../../../core/providers/stock_providers.dart';
import '../../../core/services/reports_pdf.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../../../core/widgets/form_field_scroll.dart';
import '../../../core/widgets/list_skeleton.dart';
import '../../../shared/widgets/bag_default_unit_hint.dart';
import '../../../shared/widgets/trade_intel_cards.dart';
import '../../../shared/widgets/search_picker_sheet.dart';
import '../../../core/providers/trade_purchases_provider.dart';
import '../../stock/presentation/update_stock_sheet.dart';
import '../../stock/presentation/widgets/stock_today_feed.dart';

class CatalogItemDetailPage extends ConsumerStatefulWidget {
  const CatalogItemDetailPage({super.key, required this.itemId});

  final String itemId;

  @override
  ConsumerState<CatalogItemDetailPage> createState() =>
      _CatalogItemDetailPageState();
}

class _CatalogItemDetailPageState extends ConsumerState<CatalogItemDetailPage> {
  int _historyRangeDays = kDefaultItemHistoryRangeDays;
  static const int _kMaxHistoryRows = 200;
  final _histSearchCtrl = TextEditingController();
  bool _inlineEditing = false;
  late final TextEditingController _inlineNameCtrl = TextEditingController();

  String _inr(num? n) {
    if (n == null) return '—';
    return NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    ).format(n);
  }

  Future<void> _notifyOwner(String itemId, String itemName) async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      await ref.read(hexaApiProvider).notifyOwnerStockItem(
            businessId: session.primaryBusiness.id,
            itemId: itemId,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Owner notified about $itemName')),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyApiError(e))),
      );
    }
  }

  Future<void> _addToReorderList(String itemId, String itemName) async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      await ref.read(hexaApiProvider).addItemToReorderList(
            businessId: session.primaryBusiness.id,
            itemId: itemId,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added $itemName to reorder list')),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyApiError(e))),
      );
    }
  }

  Future<void> _editItemDefaults(Map<String, dynamic> item) async {
    final nameCtrl =
        TextEditingController(text: item['name']?.toString() ?? '');
    final hsnCtrl =
        TextEditingController(text: item['hsn_code']?.toString() ?? '');
    final taxCtrl = TextEditingController(
        text: item['tax_percent'] != null ? item['tax_percent'].toString() : '');
    final kgCtrl = TextEditingController(
      text: item['default_kg_per_bag'] != null
          ? item['default_kg_per_bag'].toString()
          : '',
    );
    final ipbCtrl = TextEditingController(
      text: item['default_items_per_box'] != null
          ? item['default_items_per_box'].toString()
          : '',
    );
    final wptCtrl = TextEditingController(
      text: item['default_weight_per_tin'] != null
          ? item['default_weight_per_tin'].toString()
          : '',
    );
    final landCtrl = TextEditingController(
      text: item['default_landing_cost'] != null
          ? item['default_landing_cost'].toString()
          : '',
    );
    final sellCtrl = TextEditingController(
      text: item['default_selling_cost'] != null
          ? item['default_selling_cost'].toString()
          : '',
    );
    final sheetResult = await showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetCtx).bottom,
        ),
        child: _EditCatalogItemDefaultsSheet(
          pickerContext: context,
          nameCtrl: nameCtrl,
          hsnCtrl: hsnCtrl,
          taxCtrl: taxCtrl,
          kgCtrl: kgCtrl,
          ipbCtrl: ipbCtrl,
          wptCtrl: wptCtrl,
          landCtrl: landCtrl,
          sellCtrl: sellCtrl,
          initialUnit: item['default_unit']?.toString(),
        ),
      ),
    );
    try {
      if (sheetResult == null || sheetResult['ok'] != true) return;
      final unit = sheetResult['unit'] as String?;
      final session = ref.read(sessionProvider);
      if (session == null) return;
      final kgParsed =
          unit == 'bag' ? parseOptionalKgPerBag(kgCtrl.text) : null;
      final tax = double.tryParse(taxCtrl.text.trim());
      final ipb = double.tryParse(ipbCtrl.text.trim());
      final wpt = double.tryParse(wptCtrl.text.trim());
      final land = double.tryParse(landCtrl.text.trim());
      final sell = double.tryParse(sellCtrl.text.trim());
      await ref.read(hexaApiProvider).updateCatalogItem(
            businessId: session.primaryBusiness.id,
            itemId: widget.itemId,
            name: nameCtrl.text.trim().isEmpty
                ? null
                : nameCtrl.text.trim(),
            hsnCode: hsnCtrl.text.trim().isEmpty ? null : hsnCtrl.text.trim(),
            taxPercent: tax,
            defaultLandingCost: land,
            defaultSellingCost: sell,
            includeDefaultUnit: true,
            defaultUnit: unit,
            patchDefaultKgPerBag: unit == 'bag',
            defaultKgPerBag: kgParsed,
            patchDefaultItemsPerBox: unit == 'box',
            defaultItemsPerBox: ipb,
            patchDefaultWeightPerTin: unit == 'tin',
            defaultWeightPerTin: wpt,
          );
      ref.invalidate(catalogItemDetailProvider(widget.itemId));
      ref.invalidate(tradePurchasesCatalogIntelProvider);
      invalidatePurchaseWorkspace(ref);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Saved')));
      }
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyApiError(e))));
      }
    } finally {
      nameCtrl.dispose();
      hsnCtrl.dispose();
      taxCtrl.dispose();
      kgCtrl.dispose();
      ipbCtrl.dispose();
      wptCtrl.dispose();
      landCtrl.dispose();
      sellCtrl.dispose();
    }
  }

  Future<void> _refresh() async {
    ref.invalidate(catalogItemDetailProvider(widget.itemId));
    ref.invalidate(stockItemDetailProvider(widget.itemId));
    ref.invalidate(tradePurchasesCatalogIntelProvider);
    await ref.read(catalogItemDetailProvider(widget.itemId).future);
  }

  /// Merges latest trade line into [item] for last-purchase UI (qty, rates, date).
  static Map<String, dynamic> _itemWithLastTradeLine(
    Map<String, dynamic> item,
    List<TradePurchase>? purchases,
    String itemId,
  ) {
    final hero = Map<String, dynamic>.from(item);
    if (purchases == null || purchases.isEmpty) return hero;
    TradePurchaseLine? last;
    DateTime? lastAt;
    for (final p in purchases) {
      for (final ln in p.lines) {
        if ((ln.catalogItemId ?? '') != itemId) continue;
        if (lastAt == null || p.purchaseDate.isAfter(lastAt)) {
          lastAt = p.purchaseDate;
          last = ln;
        }
      }
    }
    if (last == null) return hero;
    final ln = last;
    if (lastAt != null) {
      hero['last_purchase_date'] =
          '${lastAt.year.toString().padLeft(4, '0')}-'
          '${lastAt.month.toString().padLeft(2, '0')}-'
          '${lastAt.day.toString().padLeft(2, '0')}';
    }
    hero['last_line_qty'] = ln.qty;
    hero['last_line_unit'] = ln.unit;
    final tw = ln.totalWeight;
    final wk = (tw != null && tw > 0)
        ? tw
        : (ln.kgPerUnit != null && ln.kgPerUnit! > 0)
            ? (ln.qty * ln.kgPerUnit!)
            : null;
    hero['last_line_weight_kg'] = wk;
    hero['kg_per_unit'] = ln.kgPerUnit ?? ln.defaultKgPerBag;
    if (ln.landingCostPerKg != null && ln.landingCostPerKg! > 0) {
      hero['last_purchase_price'] = ln.landingCostPerKg;
      hero['purchase_rate_dim'] = 'kg';
    } else {
      hero['last_purchase_price'] = ln.purchaseRate ?? ln.landingCost;
      hero['purchase_rate_dim'] =
          ln.unit.trim().isEmpty ? null : ln.unit.trim().toLowerCase();
    }
    return hero;
  }

  String _pdfMoney(num? n) {
    if (n == null) return '-';
    return _inr(n).replaceAll('₹', 'Rs. ');
  }

  String _pdfLandingCol(TradePurchaseLine ln) {
    final r = tradePurchaseLineDisplayPurchaseRate(ln);
    final suff = unit_lbl.purchaseRateSuffix(ln);
    return 'Rs. ${_fmtNum(r)}/$suff';
  }

  Future<void> _exportItemPdf(
    String itemName,
    List<ItemTradeHistoryRow> hist,
  ) async {
    if (hist.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No trade lines to export.')),
        );
      }
      return;
    }
    try {
      final biz = ref.read(invoiceBusinessProfileProvider);
      final df = DateFormat('dd MMM yyyy');
      final rows = <List<String>>[];
      var sum = 0.0;
      for (final r in hist) {
        final ln = r.line;
        sum += r.lineTotal;
        final broker = (r.brokerName ?? '').trim();
        rows.add([
          df.format(r.purchaseDate),
          r.supplierName,
          broker.isEmpty ? '-' : broker,
          '${_fmtNum(ln.qty)} ${ln.unit}',
          r.rateLabel().replaceAll('₹', 'Rs. '),
          _pdfLandingCol(ln),
          _pdfMoney(ln.sellingCost),
          _pdfMoney(r.lineTotal),
        ]);
      }
      final now = DateTime.now();
      final periodTo = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
      final periodFrom = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: _historyRangeDays));
      final totalLabel =
          'Total: Rs. ${NumberFormat('#,##,##0', 'en_IN').format(sum.round())} '
          '(${hist.length} lines)';
      await shareItemPurchaseTradeHistoryPdf(
        business: biz,
        itemName: itemName,
        rows: rows,
        periodFrom: periodFrom,
        periodTo: periodTo,
        periodDescription: 'Last $_historyRangeDays days (trade)',
        totalLineLabel: totalLabel,
      );
    } catch (e) {
      if (mounted) {
        final msg = e is DioException
            ? friendlyApiError(e)
            : 'Could not create PDF. Please try again.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF failed. $msg')),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _histSearchCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _histSearchCtrl.dispose();
    _inlineNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveInlineEdit(Map<String, dynamic> item) async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    final name = _inlineNameCtrl.text.trim();
    if (name.isEmpty) return;
    try {
      await ref.read(hexaApiProvider).updateCatalogItem(
            businessId: session.primaryBusiness.id,
            itemId: widget.itemId,
            name: name,
          );
      if (!mounted) return;
      ref.invalidate(catalogItemDetailProvider(widget.itemId));
      setState(() => _inlineEditing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Item updated')),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyApiError(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(businessDataWriteRevisionProvider, (prev, next) {
      if (prev != null && next > prev) {
        ref.invalidate(catalogItemDetailProvider(widget.itemId));
        ref.invalidate(stockItemDetailProvider(widget.itemId));
        ref.invalidate(catalogItemTradeSupplierPricesProvider(widget.itemId));
        ref.invalidate(tradePurchasesCatalogIntelProvider);
      }
    });

    final itemAsync = ref.watch(catalogItemDetailProvider(widget.itemId));
    final catsAsync = ref.watch(itemCategoriesListProvider);
    final purchasesAsync =
        ref.watch(tradePurchasesCatalogIntelParsedProvider);

    final itemCodeTitle = itemAsync.valueOrNull?['item_code']?.toString().trim();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            if (_inlineEditing) {
              setState(() => _inlineEditing = false);
            } else {
              context.popOrGo('/catalog');
            }
          },
        ),
        title: Text(
          _inlineEditing
              ? 'Editing item'
              : (itemAsync.valueOrNull?['name']?.toString().trim().isNotEmpty ==
                      true
                  ? itemAsync.valueOrNull!['name'].toString().trim()
                  : (itemCodeTitle?.isNotEmpty == true
                      ? itemCodeTitle!
                      : 'Item')),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (_inlineEditing) ...[
            TextButton(
              onPressed: () => setState(() => _inlineEditing = false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: itemAsync.valueOrNull == null
                  ? null
                  : () => _saveInlineEdit(itemAsync.valueOrNull!),
              child: const Text('Save'),
            ),
          ] else ...[
            TextButton(
              onPressed: itemAsync.valueOrNull == null
                  ? null
                  : () {
                      final it = itemAsync.valueOrNull!;
                      _inlineNameCtrl.text = it['name']?.toString() ?? '';
                      setState(() => _inlineEditing = true);
                    },
              child: const Text('Edit'),
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                final it = itemAsync.valueOrNull;
                if (it == null) return;
                switch (v) {
                  case 'ledger':
                    context.push('/catalog/item/${widget.itemId}/ledger');
                  case 'history':
                    context.push(
                      '/catalog/item/${widget.itemId}/purchase-history',
                    );
                  case 'defaults':
                    _editItemDefaults(it);
                }
              },
              itemBuilder: (ctx) => const [
                PopupMenuItem(
                  value: 'ledger',
                  child: Text('Ledger & statement'),
                ),
                PopupMenuItem(
                  value: 'history',
                  child: Text('Purchase history'),
                ),
                PopupMenuItem(
                  value: 'defaults',
                  child: Text('Edit defaults'),
                ),
              ],
            ),
          ],
        ],
      ),
      body: itemAsync.when(
        skipLoadingOnReload: true,
        skipLoadingOnRefresh: true,
        loading: () => const DetailSkeleton(),
        error: (_, __) => FriendlyLoadError(
          message: 'Could not load catalog item',
          onRetry: () =>
              ref.invalidate(catalogItemDetailProvider(widget.itemId)),
        ),
        data: (item) {
          final fromScan =
              GoRouterState.of(context).uri.queryParameters['source'] ==
                  'scan';
          final session = ref.watch(sessionProvider);
          final isStaff = session != null && sessionIsStaff(session);
          String? catName;
          if (catsAsync.hasValue) {
            final cid = item['category_id']?.toString();
            for (final c in catsAsync.value!) {
              if (c['id']?.toString() == cid) {
                catName = c['name']?.toString();
                break;
              }
            }
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              children: [
                if (fromScan)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Material(
                      color: HexaColors.brandPrimary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.qr_code_scanner_rounded,
                              color: HexaColors.brandPrimary,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Opened from barcode scan',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: HexaColors.brandPrimary,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                Builder(
                  builder: (context) {
                    final stockAsync =
                        ref.watch(stockItemDetailProvider(widget.itemId));
                    return stockAsync.when(
                      loading: () => _ItemWarehouseHeroHeader(
                        item: item,
                        categoryLabel: [
                          if (catName != null && catName.isNotEmpty) catName,
                          item['type_name']?.toString(),
                        ].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
                      ),
                      error: (_, __) => _ItemWarehouseHeroHeader(
                        item: item,
                        categoryLabel: [
                          if (catName != null && catName.isNotEmpty) catName,
                          item['type_name']?.toString(),
                        ].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
                      ),
                      data: (st) => _ItemWarehouseHeroHeader(
                        item: item,
                        stock: st.isEmpty ? null : st,
                        categoryLabel: [
                          if (catName != null && catName.isNotEmpty) catName,
                          item['type_name']?.toString(),
                        ].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
                      ),
                    );
                  },
                ),
                if (_inlineEditing) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _inlineNameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Item name',
                      border: OutlineInputBorder(),
                    ),
                    textCapitalization: TextCapitalization.words,
                    autofocus: true,
                  ),
                ],
                const SizedBox(height: 12),
                _CatalogItemBarcodeSection(
                  itemCode: item['item_code']?.toString(),
                  itemName: item['name']?.toString() ?? 'Item',
                  itemId: widget.itemId,
                ),
                const SizedBox(height: 12),
                _CatalogItemCatalogInfoSection(item: item),
                const SizedBox(height: 12),
                _CatalogItemStockSection(
                  itemId: widget.itemId,
                  item: item,
                ),
                const SizedBox(height: 12),
                Builder(
                  builder: (ctx) {
                    final enriched = _CatalogItemDetailPageState
                        ._itemWithLastTradeLine(
                      item,
                      purchasesAsync.valueOrNull,
                      widget.itemId,
                    );
                    return _CatalogItemLastPurchaseSection(
                      item: enriched,
                      inr: _inr,
                    );
                  },
                ),
                const SizedBox(height: 12),
                _CatalogItemSuppliersSection(
                  itemId: widget.itemId,
                  item: item,
                  purchases: purchasesAsync.valueOrNull,
                ),
                const SizedBox(height: 12),
                Builder(
                  builder: (context) {
                    final st =
                        ref.watch(stockItemDetailProvider(widget.itemId)).valueOrNull ??
                            const <String, dynamic>{};
                    final stockStatus =
                        st['stock_status']?.toString() ?? 'healthy';
                    final showNotifyOwner = isStaff &&
                        (stockStatus == 'low' || stockStatus == 'critical');
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _ItemQuickActionGrid(
                          onUpdateStock: () async {
                            final row = await ref.read(
                              stockItemDetailProvider(widget.itemId).future,
                            );
                            if (!context.mounted) return;
                            await showUpdateStockSheet(
                              context: context,
                              ref: ref,
                              itemId: widget.itemId,
                              itemName: item['name']?.toString() ?? 'Item',
                              stockRow: row.isEmpty ? null : row,
                            );
                          },
                          onHistory: () {
                            final name = item['name']?.toString() ?? 'Item';
                            final q = '?name=${Uri.encodeComponent(name)}';
                            context.push('/stock/${widget.itemId}/history$q');
                          },
                          onReorderList: () => _addToReorderList(
                            widget.itemId,
                            item['name']?.toString() ?? 'Item',
                          ),
                        ),
                        if (showNotifyOwner) ...[
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: () => _notifyOwner(
                              widget.itemId,
                              item['name']?.toString() ?? 'Item',
                            ),
                            icon: const Icon(Icons.notifications_active_outlined),
                            label: const Text('Notify owner'),
                          ),
                        ],
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                _RecentStockPurchasesSection(itemId: widget.itemId),
                const SizedBox(height: 12),
                _CatalogItemStockHistorySection(itemId: widget.itemId),
                const SizedBox(height: 12),
                purchasesAsync.when(
                  skipLoadingOnReload: true,
                  skipLoadingOnRefresh: true,
                  loading: () => const LinearProgressIndicator(),
                  error: (_, __) => FriendlyLoadError(
                    message: 'Could not load purchase history',
                    onRetry: () =>
                        ref.invalidate(tradePurchasesCatalogIntelProvider),
                  ),
                  data: (purchases) {
                    final itemName = item['name']?.toString() ?? 'Item';
                    final hist = itemTradeHistoryRows(
                      purchases,
                      widget.itemId,
                      catalogItemName: itemName,
                    );
                    final rangeHist =
                        itemTradeHistoryRowsInRange(hist, _historyRangeDays);
                    final baseRecent =
                        rangeHist.take(_kMaxHistoryRows).toList();
                    final q = _histSearchCtrl.text.trim().toLowerCase();
                    final recent = q.isEmpty
                        ? baseRecent
                        : baseRecent.where((r) {
                            if (r.humanId.toLowerCase().contains(q)) {
                              return true;
                            }
                            if (r.supplierName.toLowerCase().contains(q)) {
                              return true;
                            }
                            if (r.line.itemName.toLowerCase().contains(q)) {
                              return true;
                            }
                            return DateFormat('dd MMM yyyy')
                                .format(r.purchaseDate)
                                .toLowerCase()
                                .contains(q);
                          }).toList();

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (hist.isEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            'No purchases recorded for this item yet',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        _ItemSectionLabel(
                          label:
                              'Recent history · last $_historyRangeDays days (trade)',
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _histSearchCtrl,
                          decoration: InputDecoration(
                            hintText: 'Search invoice, supplier, item…',
                            filled: true,
                            isDense: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                            fillColor: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                                .withValues(alpha: 0.5),
                            prefixIcon: const Icon(Icons.search, size: 20),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            ChoiceChip(
                              label: const Text('30d'),
                              selected: _historyRangeDays == 30,
                              onSelected: (_) => setState(
                                () => _historyRangeDays = 30,
                              ),
                            ),
                            ChoiceChip(
                              label: const Text('90d'),
                              selected: _historyRangeDays == 90,
                              onSelected: (_) => setState(
                                () => _historyRangeDays = 90,
                              ),
                            ),
                            ChoiceChip(
                              label: const Text('365d'),
                              selected: _historyRangeDays == 365,
                              onSelected: (_) => setState(
                                () => _historyRangeDays = 365,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (recent.isEmpty)
                          Text(
                            hist.isEmpty
                                ? 'No lines in latest 200 purchases.'
                                : 'No purchases in this date range.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          )
                        else
                          _TradeHistoryLedgerTable(
                            rows: recent,
                            cs: Theme.of(context).colorScheme,
                            fmtDate: _fmtDate,
                            fmtNum: _fmtNum,
                            inr: _inr,
                          ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () =>
                              context.push('/catalog/item/${widget.itemId}/ledger'),
                          icon: const Icon(Icons.receipt_long_outlined),
                          label: const Text('View full statement & ledger'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () =>
                              _exportItemPdf(itemName, rangeHist),
                          icon: const Icon(Icons.picture_as_pdf_outlined),
                          label: const Text('Download PDF statement'),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),

                // ── DEFAULTS ──────────────────────────────────────────────
                const _ItemSectionLabel(label: 'Defaults'),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Builder(
                          builder: (context) {
                            final du = item['default_unit']?.toString();
                            final dkg = item['default_kg_per_bag'];
                            final line = (du == null || du.isEmpty)
                                ? 'No default unit'
                                : (du == 'bag' && dkg != null)
                                    ? 'Default: $du · $dkg kg/bag'
                                    : 'Default unit: $du';
                            return Text(
                              line,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                    fontSize: 12,
                                  ),
                            );
                          },
                        ),
                      ),
                      TextButton(
                        onPressed: () => _editItemDefaults(item),
                        child: const Text('Edit'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: itemAsync.hasValue && !_inlineEditing
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  height: 52,
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => context.push(
                      '/purchase/new?catalogItemId=${Uri.encodeComponent(widget.itemId)}',
                    ),
                    child: Text(
                      'Purchase this item →',
                      style: HexaDsType.body(15, color: Colors.white)
                          .copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ),
            )
          : null,
    );
  }

}

class _CatalogItemCatalogInfoSection extends StatelessWidget {
  const _CatalogItemCatalogInfoSection({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    String cell(dynamic v) {
      if (v == null) return '—';
      final s = v.toString().trim();
      return s.isEmpty ? '—' : s;
    }

    return _CatalogItemDetailPanel(
      title: 'Catalog info',
      rows: [
        ('HSN', cell(item['hsn_code'])),
        ('Tax %', cell(item['tax_percent'])),
        ('Item code', cell(item['item_code'])),
        ('Unit', cell(item['default_unit'])),
      ],
    );
  }
}

class _CatalogItemStockSection extends ConsumerWidget {
  const _CatalogItemStockSection({
    required this.itemId,
    required this.item,
  });

  final String itemId;
  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stockAsync = ref.watch(stockItemDetailProvider(itemId));
    return stockAsync.when(
      loading: () => const _CatalogItemDetailPanel(
        title: 'Stock',
        rows: [('Current', '…'), ('Low threshold', '…')],
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (st) {
        if (st.isEmpty) return const SizedBox.shrink();
        String qty(dynamic v) {
          if (v == null) return '—';
          if (v is num) {
            return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
          }
          return v.toString();
        }

        final unit =
            (st['unit'] ?? item['default_unit'] ?? '').toString().trim();
        final unitSuffix = unit.isNotEmpty ? ' $unit' : '';
        return _CatalogItemDetailPanel(
          title: 'Stock',
          rows: [
            ('Current', '${qty(st['current_stock'])}$unitSuffix'),
            ('Low threshold', '${qty(st['reorder_level'])}$unitSuffix'),
          ],
        );
      },
    );
  }
}

class _CatalogItemLastPurchaseSection extends StatelessWidget {
  const _CatalogItemLastPurchaseSection({
    required this.item,
    required this.inr,
  });

  final Map<String, dynamic> item;
  final String Function(num? n) inr;

  @override
  Widget build(BuildContext context) {
    final qty = tradeIntelQtySummaryLine(item);
    final rates = tradeIntelRatePairLine(item);
    final rawPd = item['last_purchase_date']?.toString() ?? '';
    DateTime? parsedPd;
    if (rawPd.length >= 10) {
      parsedPd = DateTime.tryParse(rawPd.substring(0, 10));
    }
    if (parsedPd == null && qty.isEmpty && rates.isEmpty) {
      return _CatalogItemDetailPanel(
        title: 'Last purchase',
        rows: const [('—', 'No purchases recorded yet')],
      );
    }

    final dateStr = parsedPd != null
        ? DateFormat('d MMM yyyy').format(parsedPd.toLocal())
        : '—';
    final detail = <String>[];
    if (qty.isNotEmpty) detail.add(qty);
    if (rates.isNotEmpty) detail.add(rates.replaceAll('₹', '').trim());

    return _CatalogItemDetailPanel(
      title: 'Last purchase',
      rows: [
        (
          dateStr,
          detail.isEmpty ? '—' : detail.join(' · '),
        ),
      ],
    );
  }
}

class _CatalogItemSuppliersSection extends ConsumerWidget {
  const _CatalogItemSuppliersSection({
    required this.itemId,
    required this.item,
    required this.purchases,
  });

  final String itemId;
  final Map<String, dynamic> item;
  final List<TradePurchase>? purchases;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suppliersAsync = ref.watch(suppliersListProvider);
    final defaultIds = (item['default_supplier_ids'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        <String>[];

    final lastBySupplier = <String, DateTime>{};
    final nameBySupplier = <String, String>{};
    final purchaseList = purchases;
    if (purchaseList != null) {
      for (final p in purchaseList) {
        final sid = p.supplierId?.trim();
        if (sid == null || sid.isEmpty) continue;
        for (final ln in p.lines) {
          if ((ln.catalogItemId ?? '') != itemId) continue;
          final cur = lastBySupplier[sid];
          if (cur == null || p.purchaseDate.isAfter(cur)) {
            lastBySupplier[sid] = p.purchaseDate;
            final sn = p.supplierName?.trim();
            if (sn != null && sn.isNotEmpty) nameBySupplier[sid] = sn;
          }
        }
      }
    }

    final orderedIds = <String>[
      ...defaultIds,
      for (final id in lastBySupplier.keys)
        if (!defaultIds.contains(id)) id,
    ];
    if (orderedIds.isEmpty) return const SizedBox.shrink();

    return suppliersAsync.when(
      loading: () => const LinearProgressIndicator(),
      error: (_, __) => const SizedBox.shrink(),
      data: (rows) {
        final byId = {
          for (final s in rows) s['id']?.toString(): s,
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _ItemSectionLabel(label: 'Suppliers'),
            const SizedBox(height: 8),
            for (final id in orderedIds.take(8))
              _SupplierAvatarRow(
                name: nameBySupplier[id] ??
                    byId[id]?['name']?.toString() ??
                    id,
                lastPurchase: lastBySupplier[id],
              ),
          ],
        );
      },
    );
  }
}

class _SupplierAvatarRow extends StatelessWidget {
  const _SupplierAvatarRow({required this.name, this.lastPurchase});

  final String name;
  final DateTime? lastPurchase;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    final lastLabel = lastPurchase != null
        ? 'Last: ${DateFormat('d MMM').format(lastPurchase!.toLocal())}'
        : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: HexaColors.primaryLight,
            child: Text(
              initial,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: HexaColors.brandPrimary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              style: HexaDsType.listTitle(context),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (lastLabel != null)
            Text(
              lastLabel,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}

class _CatalogItemDetailPanel extends StatelessWidget {
  const _CatalogItemDetailPanel({
    required this.title,
    required this.rows,
  });

  final String title;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Material(
      color: cs.surfaceContainerLowest.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 110,
                      child: Text(
                        r.$1,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        r.$2,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CatalogItemStockHistorySection extends ConsumerWidget {
  const _CatalogItemStockHistorySection({required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auditAsync = ref.watch(stockItemAuditProvider(itemId));
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return auditAsync.when(
      loading: () => const SizedBox(
        height: 48,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (rows) {
        if (rows.isEmpty) return const SizedBox.shrink();
        final preview = rows.take(10).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'Stock history',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    final name = ref.read(catalogItemDetailProvider(itemId)).valueOrNull?['name']?.toString();
                    final q = name != null && name.isNotEmpty ? '?name=${Uri.encodeComponent(name)}' : '';
                    context.push('/stock/$itemId/history$q');
                  },
                  child: const Text('View all'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ...preview.map((r) {
              final oldQ = (r['old_qty'] as num?)?.toDouble() ?? 0;
              final newQ = (r['new_qty'] as num?)?.toDouble() ?? 0;
              final diff = newQ - oldQ;
              final dot = diff > 0
                  ? const Color(0xFF2E7D32)
                  : diff < 0
                      ? cs.error
                      : cs.outline;
              final expected = r['expected_qty'];
              final found = r['found_qty'];
              final reason = r['reason']?.toString().trim();
              String? varianceLine;
              if (expected != null && found != null) {
                varianceLine =
                    'Variance: expected $expected · found $found';
              } else if (reason != null &&
                  reason.isNotEmpty &&
                  reason.toLowerCase().contains('variance')) {
                varianceLine = reason;
              }
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(top: 5),
                      decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${diff >= 0 ? '+' : ''}${diff == diff.roundToDouble() ? diff.toInt() : diff.toStringAsFixed(1)} '
                                  '(${oldQ.toStringAsFixed(0)} → ${newQ.toStringAsFixed(0)})',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              StockAdjustmentSourceBadge(
                                adjustmentType: r['adjustment_type']?.toString(),
                              ),
                            ],
                          ),
                          if (varianceLine != null)
                            Text(
                              varianceLine,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.error,
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        );
      },
    );
  }
}

class _CatalogItemBarcodeSection extends StatelessWidget {
  const _CatalogItemBarcodeSection({
    this.itemCode,
    required this.itemName,
    required this.itemId,
  });

  final String? itemCode;
  final String itemName;
  final String itemId;

  Future<void> _shareCode(BuildContext context, String code) async {
    await Share.share(
      'Harisree Agency — $itemName\nBarcode: $code',
      subject: itemName,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final code = itemCode?.trim() ?? '';
    if (code.isEmpty) {
      return Material(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Text(
            'No item code set — add a code in catalog to print a barcode label.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    final svg = Barcode.code128().toSvg(
      code,
      width: 280,
      height: 72,
      drawText: true,
      fontHeight: 13,
    );

    return Material(
      color: cs.surfaceContainerLowest.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Barcode',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Center(
                        child: SvgPicture.string(
                          svg,
                          width: 260,
                          height: 68,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        code,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                QrImageView(
                  data: code,
                  size: 80,
                  backgroundColor: Colors.white,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () => context.push(
                    '/barcode/print/${Uri.encodeComponent(itemId)}',
                  ),
                  icon: const Icon(Icons.print_rounded, size: 18),
                  label: const Text('Print label'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _shareCode(context, code),
                  icon: const Icon(Icons.share_outlined, size: 18),
                  label: const Text('Share barcode'),
                ),
                OutlinedButton.icon(
                  onPressed: () => context.push('/barcode/bulk-print'),
                  icon: const Icon(Icons.layers_outlined, size: 18),
                  label: const Text('Bulk print'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemQuickActionGrid extends StatelessWidget {
  const _ItemQuickActionGrid({
    required this.onUpdateStock,
    required this.onHistory,
    required this.onReorderList,
  });

  final VoidCallback onUpdateStock;
  final VoidCallback onHistory;
  final VoidCallback onReorderList;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.35,
      children: [
        OutlinedButton.icon(
          onPressed: onUpdateStock,
          icon: const Icon(Icons.inventory_2_outlined, size: 18),
          label: const Text('Stock'),
        ),
        OutlinedButton.icon(
          onPressed: onHistory,
          icon: const Icon(Icons.history_rounded, size: 18),
          label: const Text('History'),
        ),
        OutlinedButton.icon(
          onPressed: onReorderList,
          icon: const Icon(Icons.playlist_add_rounded, size: 18),
          label: const Text('Reorder'),
        ),
      ],
    );
  }
}

class _ItemWarehouseHeroHeader extends StatelessWidget {
  const _ItemWarehouseHeroHeader({
    required this.item,
    this.stock,
    this.categoryLabel = '',
  });

  final Map<String, dynamic> item;
  final Map<String, dynamic>? stock;
  final String categoryLabel;

  static String _fmtQty(dynamic v) {
    if (v == null) return '—';
    if (v is num) {
      return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
    }
    return '$v';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = item['name']?.toString() ?? 'Item';
    final st = stock?['stock_status']?.toString() ?? 'healthy';
    final statusLabel = switch (st) {
      'out' => 'Out',
      'critical' => 'Critical',
      'low' => 'Low',
      _ => 'OK',
    };
    final statusColor = switch (st) {
      'out' => cs.error,
      'critical' => const Color(0xFFC62828),
      'low' => const Color(0xFFE65100),
      _ => const Color(0xFF2E7D32),
    };
    final unit = (stock?['unit'] ?? item['default_unit'] ?? '').toString().trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: HexaColors.primaryLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: HexaColors.brandBorder),
              ),
              child: Icon(
                Icons.inventory_2_outlined,
                size: 32,
                color: HexaColors.brandPrimary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: HexaDsType.catalogItemHeroName),
                  if (categoryLabel.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      categoryLabel,
                      style: HexaDsType.body(13, color: HexaDsColors.textMuted),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Chip(
                    label: Text(
                      statusLabel,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        color: statusColor,
                      ),
                    ),
                    side: BorderSide(color: statusColor.withValues(alpha: 0.5)),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ],
        ),
        if (stock != null && stock!.isNotEmpty) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ItemStatBox(
                  label: 'On hand',
                  value: _fmtQty(stock!['current_stock']),
                  sub: unit.isNotEmpty ? unit : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ItemStatBox(
                  label: 'Reorder',
                  value: _fmtQty(stock!['reorder_level']),
                  sub: unit.isNotEmpty ? unit : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ItemStatBox(
                  label: 'Rack',
                  value: (stock!['rack_location']?.toString().trim().isNotEmpty ==
                          true)
                      ? stock!['rack_location'].toString()
                      : '—',
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ItemStatBox extends StatelessWidget {
  const _ItemStatBox({
    required this.label,
    required this.value,
    this.sub,
  });

  final String label;
  final String value;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          if (sub != null && sub!.isNotEmpty)
            Text(
              sub!,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}

class _RecentStockPurchasesSection extends ConsumerWidget {
  const _RecentStockPurchasesSection({required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final stockAsync = ref.watch(stockItemDetailProvider(itemId));

    return stockAsync.when(
      loading: () => const SizedBox(
        height: 48,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (st) {
        final raw = st['recent_purchases'];
        if (raw is! List || raw.isEmpty) return const SizedBox.shrink();
        final rows = [
          for (final e in raw.take(5))
            if (e is Map) Map<String, dynamic>.from(e),
        ];
        if (rows.isEmpty) return const SizedBox.shrink();

        return Material(
          color: theme.colorScheme.surfaceContainerLowest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Recent purchases',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                for (final r in rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _fmtPurchaseLine(r),
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  static String _fmtPurchaseLine(Map<String, dynamic> r) {
    final at = DateTime.tryParse(r['purchase_date']?.toString() ?? '');
    final date = at != null
        ? DateFormat('d MMM yyyy').format(at.toLocal())
        : '—';
    final qty = r['qty']?.toString() ?? '—';
    final unit = r['unit']?.toString() ?? '';
    final rate = r['rate']?.toString() ?? '—';
    final sup = r['supplier_name']?.toString() ?? '';
    return '$date · $qty $unit · ₹$rate · $sup';
  }
}


String _fmtDate(String raw) {
  final d = DateTime.tryParse(raw);
  if (d == null) return raw.split('T').first;
  return DateFormat('d MMM').format(d);
}

String _fmtNum(double n) =>
    n == n.roundToDouble() ? n.toInt().toString() : n.toStringAsFixed(2);

class _ItemSectionLabel extends StatelessWidget {
  const _ItemSectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: HexaDsType.formSectionLabel,
    );
  }
}

class _TradeHistoryLedgerTable extends StatelessWidget {
  const _TradeHistoryLedgerTable({
    required this.rows,
    required this.cs,
    required this.fmtDate,
    required this.fmtNum,
    required this.inr,
  });

  final List<ItemTradeHistoryRow> rows;
  final ColorScheme cs;
  final String Function(String raw) fmtDate;
  final String Function(double n) fmtNum;
  final String Function(num? n) inr;

  @override
  Widget build(BuildContext context) {
    final border = TableBorder.symmetric(
      inside: BorderSide(
        color: cs.outlineVariant.withValues(alpha: 0.4),
        width: 0.5,
      ),
    );
    TextStyle h() => HexaDsType.label(12, color: cs.onSurfaceVariant);
    return LayoutBuilder(
      builder: (context, c) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Material(
            color: cs.surfaceContainerLowest.withValues(alpha: 0.35),
            child: Scrollbar(
              thumbVisibility: false,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: math.max(c.maxWidth, 320),
                  ),
                  child: Table(
                    border: border,
                    columnWidths: const {
                      0: FixedColumnWidth(56),
                      1: FlexColumnWidth(2.0),
                      2: FlexColumnWidth(1.1),
                      3: FixedColumnWidth(80),
                      4: FixedColumnWidth(80),
                    },
                    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                    children: [
                      TableRow(
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                        ),
                        children: [
                          _thCell('Date', h(), padEnd: 4),
                          _thCell('Supplier', h()),
                          _thCell('Qty', h()),
                          _thCell('Rate', h(), align: TextAlign.end, padStart: 4),
                          _thCell('Total', h(), align: TextAlign.end, padStart: 4),
                        ],
                      ),
                      for (final r in rows)
                        TableRow(
                          children: [
                            _tdCell(
                              Text(
                                fmtDate(r.purchaseDate.toIso8601String()),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                            _tdCell(
                              Text(
                                r.supplierName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: HexaDsType.purchaseQtyUnit.copyWith(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            _tdCell(
                              Text(
                                '${fmtNum(r.line.qty)} ${r.line.unit}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: HexaDsType.purchaseQtyUnit
                                    .copyWith(fontSize: 12),
                              ),
                            ),
                            _tdCell(
                              Text(
                                r.rateLabel(),
                                textAlign: TextAlign.end,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            _tdCell(
                              Text(
                                inr(r.lineTotal),
                                textAlign: TextAlign.end,
                                style: HexaDsType.purchaseLineMoney
                                    .copyWith(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  static Widget _thCell(
    String t,
    TextStyle style, {
    TextAlign align = TextAlign.start,
    double padStart = 6,
    double padEnd = 6,
  }) {
    return Padding(
      padding: EdgeInsets.fromLTRB(padStart, 8, padEnd, 8),
      child: Text(t, textAlign: align, style: style),
    );
  }

  static Widget _tdCell(Widget child) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: child,
    );
  }
}

class _EditCatalogItemDefaultsSheet extends StatefulWidget {
  const _EditCatalogItemDefaultsSheet({
    required this.pickerContext,
    required this.nameCtrl,
    required this.hsnCtrl,
    required this.taxCtrl,
    required this.kgCtrl,
    required this.ipbCtrl,
    required this.wptCtrl,
    required this.landCtrl,
    required this.sellCtrl,
    required this.initialUnit,
  });

  final BuildContext pickerContext;
  final TextEditingController nameCtrl;
  final TextEditingController hsnCtrl;
  final TextEditingController taxCtrl;
  final TextEditingController kgCtrl;
  final TextEditingController ipbCtrl;
  final TextEditingController wptCtrl;
  final TextEditingController landCtrl;
  final TextEditingController sellCtrl;
  final String? initialUnit;

  @override
  State<_EditCatalogItemDefaultsSheet> createState() =>
      _EditCatalogItemDefaultsSheetState();
}

class _EditCatalogItemDefaultsSheetState
    extends State<_EditCatalogItemDefaultsSheet> {
  late String? _unit;
  late final FocusNode _nameFocus;
  late final FocusNode _hsnFocus;
  late final FocusNode _taxFocus;
  late final FocusNode _kgFocus;
  late final FocusNode _ipbFocus;
  late final FocusNode _wptFocus;
  late final FocusNode _landFocus;
  late final FocusNode _sellFocus;

  @override
  void initState() {
    super.initState();
    _unit = widget.initialUnit;
    _nameFocus = FocusNode();
    _hsnFocus = FocusNode();
    _taxFocus = FocusNode();
    _kgFocus = FocusNode();
    _ipbFocus = FocusNode();
    _wptFocus = FocusNode();
    _landFocus = FocusNode();
    _sellFocus = FocusNode();
    bindFocusNodeScrollIntoView(_nameFocus);
    bindFocusNodeScrollIntoView(_hsnFocus);
    bindFocusNodeScrollIntoView(_taxFocus);
    bindFocusNodeScrollIntoView(_kgFocus);
    bindFocusNodeScrollIntoView(_ipbFocus);
    bindFocusNodeScrollIntoView(_wptFocus);
    bindFocusNodeScrollIntoView(_landFocus);
    bindFocusNodeScrollIntoView(_sellFocus);
  }

  @override
  void dispose() {
    _nameFocus.dispose();
    _hsnFocus.dispose();
    _taxFocus.dispose();
    _kgFocus.dispose();
    _ipbFocus.dispose();
    _wptFocus.dispose();
    _landFocus.dispose();
    _sellFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sp =
        formFieldScrollPaddingForContext(context, reserveBelowField: 220);
    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollCtrl) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
              child: Row(
                children: [
                  Text(
                    'Edit item',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                children: [
                  TextField(
                    controller: widget.nameCtrl,
                    focusNode: _nameFocus,
                    scrollPadding: sp,
                    decoration: const InputDecoration(labelText: 'Name'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: widget.hsnCtrl,
                    focusNode: _hsnFocus,
                    scrollPadding: sp,
                    decoration: const InputDecoration(labelText: 'HSN code'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: widget.taxCtrl,
                    focusNode: _taxFocus,
                    scrollPadding: sp,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Tax %',
                      hintText: 'e.g. 5',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Default unit (optional)',
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  OutlinedButton(
                    onPressed: () async {
                      const none = '__unit_none__';
                      final id = await showSearchPickerSheet<String>(
                        context: widget.pickerContext,
                        title: 'Default unit',
                        rows: const [
                          SearchPickerRow(value: none, title: '— (unspecified)'),
                          SearchPickerRow(value: 'kg', title: 'kg'),
                          SearchPickerRow(value: 'bag', title: 'bag'),
                          SearchPickerRow(value: 'box', title: 'box'),
                          SearchPickerRow(value: 'piece', title: 'piece'),
                        ],
                        selectedValue: _unit ?? none,
                      );
                      if (!mounted) return;
                      if (id != null) {
                        setState(() => _unit = id == none ? null : id);
                      }
                    },
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _unit == null ? '— (unspecified)' : '$_unit',
                      ),
                    ),
                  ),
                  if (_unit == 'bag') ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: widget.kgCtrl,
                      focusNode: _kgFocus,
                      scrollPadding: sp,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Default kg per bag (optional)',
                        hintText: 'e.g. 50',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 8),
                    BagDefaultUnitHint(
                      kgAlreadySet: () {
                        final v = parseOptionalKgPerBag(widget.kgCtrl.text);
                        return v != null && v > 0;
                      }(),
                    ),
                  ],
                  if (_unit == 'box') ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: widget.ipbCtrl,
                      focusNode: _ipbFocus,
                      scrollPadding: sp,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Items per box',
                        hintText: 'How many pieces per box',
                      ),
                    ),
                  ],
                  if (_unit == 'tin') ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: widget.wptCtrl,
                      focusNode: _wptFocus,
                      scrollPadding: sp,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Liters / weight per tin',
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: widget.landCtrl,
                    focusNode: _landFocus,
                    scrollPadding: sp,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Default landing (₹)',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: widget.sellCtrl,
                    focusNode: _sellFocus,
                    scrollPadding: sp,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Default selling (₹)',
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: FilledButton(
                          onPressed: () => Navigator.pop(context, {
                            'ok': true,
                            'unit': _unit,
                          }),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                          ),
                          child: const Text(
                            'Save',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

