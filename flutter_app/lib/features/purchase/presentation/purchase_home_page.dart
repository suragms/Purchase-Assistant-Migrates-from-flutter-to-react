import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/router/post_auth_route.dart';
import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/design_system/hexa_responsive.dart';
import '../../../core/design_system/hexa_web_page_frame.dart';
import '../../../core/search/catalog_fuzzy.dart';
import '../../../core/models/trade_purchase_models.dart';
import 'widgets/purchase_delivery_badge.dart';
import '../../../core/purchase/delivery_aging.dart';
import '../../../core/providers/analytics_kpi_provider.dart'
    show analyticsDateRangeProvider;
import '../../../core/utils/line_display.dart';
import '../../../core/utils/snack.dart';
import '../../../core/providers/business_profile_provider.dart';
import '../../../core/providers/business_aggregates_invalidation.dart'
    show
        catalogItemIdsFromPurchase,
        invalidateAfterPurchaseDelete,
        invalidatePurchaseListSurfacesLight,
        invalidatePurchaseMetadataLight;
import '../../../core/providers/catalog_providers.dart';
import '../../../core/purchase/purchase_stock_commit_flow.dart';
import '../../../core/providers/trade_purchases_provider.dart';
import '../../shell/shell_branch_provider.dart';
import '../providers/trade_purchase_detail_provider.dart';
import '../state/purchase_local_wip_draft_provider.dart';
import '../../../core/services/purchase_pdf.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/widgets/friendly_load_error.dart'
    show FriendlyLoadError, kFriendlyLoadNetworkSubtitle;
import '../../../core/widgets/list_skeleton.dart';
import '../../../core/widgets/focused_search_chrome.dart';
import '../../../shared/widgets/fullscreen_date_range_picker.dart';
import '../../../shared/widgets/hexa_empty_state.dart';
import '../../../shared/widgets/operational_ui.dart';
import 'widgets/purchase_desktop_detail_pane.dart';
import 'widgets/purchase_history_grouping.dart';

enum _HistPeriodPreset { today, week, month, year, allTime, custom }

Widget _purchaseHistoryCenteredEmptyScroll({required Widget child}) {
  return LayoutBuilder(
    builder: (context, constraints) {
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(child: child),
        ),
      );
    },
  );
}

bool _purchaseHistSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

Widget _historyMetaChip({
  required String label,
  required Color bg,
  required Color border,
  required Color fg,
  IconData? icon,
  double fontSize = 9.5,
}) {
  return Container(
    padding:
        EdgeInsets.symmetric(horizontal: icon == null ? 6 : 7, vertical: 3),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: border, width: 1),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: fontSize + 2.5, color: fg),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w900,
              height: 1.05,
              color: fg,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Payment / delivery context chip per row. Payment “Due in …” only after **delivered**;
/// before delivery, show **days over** if past due, else **Undelivered · Xd** (days since purchase).
Widget? _purchaseHistoryDaysChip(TradePurchase p) {
  if (p.remaining <= 1e-6) {
    return null;
  }
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final due = p.dueDate;

  if (!p.isDelivered) {
    if (due != null) {
      final dueDay = DateTime(due.year, due.month, due.day);
      final diff = dueDay.difference(today).inDays;
      if (diff < 0 || p.statusEnum == PurchaseStatus.overdue) {
        final over = diff < 0 ? -diff : 0;
        final label = over > 0 ? '${over}d over' : 'Overdue';
        return _historyMetaChip(
          label: label,
          bg: Colors.red.shade50,
          border: Colors.red.shade200,
          fg: Colors.red.shade900,
          icon: Icons.timer_off_rounded,
        );
      }
    } else {
      if (p.statusEnum == PurchaseStatus.overdue) {
        return _historyMetaChip(
          label: 'Overdue',
          bg: Colors.red.shade50,
          border: Colors.red.shade200,
          fg: Colors.red.shade900,
        );
      }
      if (p.statusEnum == PurchaseStatus.dueSoon) {
        return _historyMetaChip(
          label: 'Due soon',
          bg: const Color(0xFFFFF7ED),
          border: const Color(0xFFFDBA74),
          fg: const Color(0xFF9A3412),
        );
      }
    }
    final pur = DateTime(
      p.purchaseDate.year,
      p.purchaseDate.month,
      p.purchaseDate.day,
    );
    final wait = today.difference(pur).inDays;
    final band = undeliveredAgingBandFromDays(wait < 0 ? 0 : wait);
    final col = undeliveredAgingColors(band);
    final label = undeliveredAgingChipLabel(wait < 0 ? 0 : wait, band);
    return _historyMetaChip(
      label: label.toUpperCase(),
      bg: col.bg,
      border: col.border,
      fg: col.fg,
      icon: undeliveredAgingIcon(band),
      fontSize: band == UndeliveredAgingBand.critical ? 10.5 : 9.5,
    );
  }

  if (due == null) {
    if (p.statusEnum == PurchaseStatus.overdue) {
      return _historyMetaChip(
        label: 'Overdue',
        bg: Colors.red.shade50,
        border: Colors.red.shade200,
        fg: Colors.red.shade900,
      );
    }
    if (p.statusEnum == PurchaseStatus.dueSoon) {
      return _historyMetaChip(
        label: 'Due soon',
        bg: const Color(0xFFFFF7ED),
        border: const Color(0xFFFDBA74),
        fg: const Color(0xFF9A3412),
      );
    }
    return null;
  }
  final dueDay = DateTime(due.year, due.month, due.day);
  final diff = dueDay.difference(today).inDays;
  final overdue = diff < 0 || p.statusEnum == PurchaseStatus.overdue;
  final String label;
  if (overdue) {
    label = diff < 0 ? '${-diff}d overdue' : 'Due today';
  } else if (diff == 0) {
    label = 'Due today';
  } else {
    label = 'Due in ${diff}d';
  }
  return _historyMetaChip(
    label: label,
    bg: overdue ? Colors.red.shade50 : const Color(0xFFFFF7ED),
    border: overdue ? Colors.red.shade200 : const Color(0xFFFDBA74),
    fg: overdue ? Colors.red.shade900 : const Color(0xFF9A3412),
  );
}

_HistPeriodPreset _purchaseHistInferPreset(({DateTime from, DateTime to}) r) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final from = DateTime(r.from.year, r.from.month, r.from.day);
  final to = DateTime(r.to.year, r.to.month, r.to.day);
  if (_purchaseHistSameDay(from, today) && _purchaseHistSameDay(to, today)) {
    return _HistPeriodPreset.today;
  }
  if (_purchaseHistSameDay(from, today.subtract(const Duration(days: 6))) &&
      _purchaseHistSameDay(to, today)) {
    return _HistPeriodPreset.week;
  }
  if (_purchaseHistSameDay(from, today.subtract(const Duration(days: 29))) &&
      _purchaseHistSameDay(to, today)) {
    return _HistPeriodPreset.month;
  }
  if (_purchaseHistSameDay(from, DateTime(today.year, 1, 1)) &&
      _purchaseHistSameDay(to, today)) {
    return _HistPeriodPreset.year;
  }
  if (_purchaseHistSameDay(from, DateTime(2020, 1, 1)) &&
      _purchaseHistSameDay(to, today)) {
    return _HistPeriodPreset.allTime;
  }
  return _HistPeriodPreset.custom;
}

String _inr(num n) =>
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
        .format(n);

String _compactInrLakh(num n) {
  if (n >= 1e7) return '₹${(n / 1e7).toStringAsFixed(1)}Cr';
  if (n >= 1e5) return '₹${(n / 1e5).toStringAsFixed(1)}L';
  if (n >= 1e3) return '₹${(n / 1e3).toStringAsFixed(1)}k';
  return _inr(n);
}

/// [GoRouterState] `filter=` values that map to primary chips (`all` canonical).
const _routePrimaryPurchaseFilters = {
  'all',
  'draft',
  'due',
  'paid',
  'due_soon',
  'pending_delivery',
  'received',
  'delivery_stuck',
  'delivery_dispatched',
  'delivery_arrived',
  'delivery_commit',
};

/// Maps API `delivery_status` query values to history `filter=` chips.
String? _purchaseFilterFromDeliveryStatus(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  switch (raw.trim().toLowerCase()) {
    case 'dispatched':
    case 'in_transit':
      return 'delivery_dispatched';
    case 'arrived':
    case 'staff_verifying':
      return 'delivery_arrived';
    case 'staff_verified':
    case 'partial':
      return 'delivery_commit';
    case 'stock_committed':
      return 'received';
    case 'pending':
      return 'pending_delivery';
    default:
      return null;
  }
}

/// Human-readable purchase bill date (Today / Yesterday / d MMM yyyy).
String formatPurchaseHumanDate(DateTime date) {
  final local = DateTime(date.year, date.month, date.day);
  final today = DateTime.now();
  final todayDate = DateTime(today.year, today.month, today.day);
  final diff = todayDate.difference(local).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return DateFormat('d MMM yyyy').format(date);
}

String _purchaseSearchHaystack(TradePurchase p) {
  final df = DateFormat('dd MMM yyyy');
  final b = StringBuffer()
    ..write(p.id)
    ..write(' ')
    ..write(p.humanId)
    ..write(' ')
    ..write(p.invoiceNumber ?? '')
    ..write(' ')
    ..write(df.format(p.purchaseDate))
    ..write(' ')
    ..write(p.supplierName ?? '')
    ..write(' ')
    ..write(p.brokerName ?? '');
  for (final l in p.lines) {
    b.write(' ');
    b.write(l.itemName);
    b.write(' ');
    b.write(l.itemName.replaceAll(RegExp(r'[\s_\-]'), '').toLowerCase());
    if (l.itemCode != null && l.itemCode!.trim().isNotEmpty) {
      b.write(' ');
      b.write(l.itemCode);
    }
  }
  b.write(' ');
  b.write(p.itemsSummary);
  return b.toString();
}

String _historyPaymentChipLabel(PurchaseStatus st) {
  switch (st) {
    case PurchaseStatus.paid:
      return 'Paid';
    case PurchaseStatus.overdue:
      return 'Overdue';
    case PurchaseStatus.draft:
      return 'Draft';
    case PurchaseStatus.dueSoon:
      return 'Due soon';
    case PurchaseStatus.partiallyPaid:
      return 'Partial';
    case PurchaseStatus.saved:
      return 'Saved';
    case PurchaseStatus.confirmed:
      return 'Unpaid';
    case PurchaseStatus.cancelled:
      return 'Cancelled';
    case PurchaseStatus.deleted:
      return 'Deleted';
    case PurchaseStatus.unknown:
      return '—';
  }
}

String _histCsvCell(String raw) {
  final s = raw.replaceAll('\r\n', ' ').replaceAll('\n', ' ').trim();
  if (s.contains(',') || s.contains('"')) {
    return '"${s.replaceAll('"', '""')}"';
  }
  return s;
}

List<TradePurchase> _filterPurchasesBySearch(
  List<TradePurchase> base,
  String searchQuery,
) {
  final sq = searchQuery.trim();
  if (sq.isEmpty) return base;
  return catalogFuzzyRank(
    sq,
    base,
    _purchaseSearchHaystack,
    minScore: sq.length <= 1 ? 8.0 : 22.0,
    limit: 400,
  );
}

bool _purchaseHistoryMatchesDuePrimary(TradePurchase p) {
  final st = p.statusEnum;
  if (st == PurchaseStatus.paid ||
      st == PurchaseStatus.draft ||
      st == PurchaseStatus.cancelled ||
      st == PurchaseStatus.deleted) {
    return false;
  }
  if (st == PurchaseStatus.overdue || st == PurchaseStatus.dueSoon) {
    return true;
  }
  if (p.remaining > 1e-6 &&
      (st == PurchaseStatus.confirmed ||
          st == PurchaseStatus.partiallyPaid ||
          st == PurchaseStatus.saved)) {
    return true;
  }
  return false;
}

/// Shared filter + sort pipeline for Purchase History (main screen + fullscreen search).
List<TradePurchase> purchaseHistoryVisibleSortedForRef(
  WidgetRef ref,
  List<TradePurchase> items,
  String searchQ, {
  Set<String> pendingDeleteIds = const {},
}) {
  var v = items;
  final primary = ref.read(purchaseHistoryPrimaryFilterProvider);
  if (primary == 'due') {
    v = v.where(_purchaseHistoryMatchesDuePrimary).toList();
  }
  if (primary == 'draft') {
    v = v.where((p) => p.statusEnum == PurchaseStatus.draft).toList();
  }
  if (primary == 'pending_delivery') {
    v = v.where((p) {
      if (p.statusEnum == PurchaseStatus.deleted ||
          p.statusEnum == PurchaseStatus.cancelled) {
        return false;
      }
      return !p.isDeliveryCommitted &&
          p.deliveryStatusEnum != DeliveryStatus.cancelled;
    }).toList();
  }
  if (primary == 'delivery_dispatched') {
    v = v.where((p) {
      final ds = p.deliveryStatusEnum;
      return ds == DeliveryStatus.dispatched || ds == DeliveryStatus.inTransit;
    }).toList();
  }
  if (primary == 'delivery_arrived') {
    v = v.where((p) {
      final ds = p.deliveryStatusEnum;
      return ds == DeliveryStatus.arrived || ds == DeliveryStatus.staffVerifying;
    }).toList();
  }
  if (primary == 'delivery_commit') {
    v = v.where((p) => p.deliveryStatusEnum.readyForOwnerCommit).toList();
  }
  if (primary == 'received') {
    v = v.where((p) => p.isDeliveryCommitted).toList();
  }
  if (primary == 'delivery_stuck') {
    v = v.where((p) {
      if (p.isDeliveryCommitted) return false;
      final st = p.statusEnum;
      if (st == PurchaseStatus.deleted || st == PurchaseStatus.cancelled) {
        return false;
      }
      return undeliveredDaysSincePurchase(p) >= 6;
    }).toList();
  }
  final s = ref.read(purchaseHistorySecondaryFilterProvider);
  if (s != null) {
    v = v.where((p) {
      final st = p.statusEnum;
      switch (s) {
        case 'pending':
          return st == PurchaseStatus.confirmed;
        case 'overdue':
          return st == PurchaseStatus.overdue;
        default:
          return true;
      }
    }).toList();
  }
  final subSup =
      ref.read(purchaseHistorySupplierContainsProvider)?.trim().toLowerCase();
  final subBr =
      ref.read(purchaseHistoryBrokerContainsProvider)?.trim().toLowerCase();
  final pack = ref.read(purchaseHistoryPackKindFilterProvider);
  if (!((subSup == null || subSup.isEmpty) &&
      (subBr == null || subBr.isEmpty) &&
      (pack == null || pack.isEmpty))) {
    v = v.where((p) {
      if (subSup != null && subSup.isNotEmpty) {
        final n = (p.supplierName ?? '').toLowerCase();
        if (!n.contains(subSup)) return false;
      }
      if (subBr != null && subBr.isNotEmpty) {
        final n = (p.brokerName ?? '').toLowerCase();
        if (!n.contains(subBr)) return false;
      }
      if (pack != null && pack.isNotEmpty) {
        if (!purchaseHistoryMatchesPackKindFilter(p, pack)) return false;
      }
      return true;
    }).toList();
  }
  if (pendingDeleteIds.isNotEmpty) {
    v = v.where((p) => !pendingDeleteIds.contains(p.id)).toList();
  }
  v = _filterPurchasesBySearch(v, searchQ);
  final out = List<TradePurchase>.of(v);
  final undeliveredSort = ref.read(purchaseHistoryUndeliveredSortProvider);

  // Undelivered-days sort overrides everything except active filters: most days waiting → top.
  if (undeliveredSort) {
    int deliveryAge(TradePurchase p) {
      if (p.isDeliveryCommitted) return -1;
      final st = p.statusEnum;
      if (st == PurchaseStatus.deleted ||
          st == PurchaseStatus.cancelled ||
          st == PurchaseStatus.paid) {
        return -1;
      }
      return undeliveredDaysSincePurchase(p);
    }

    out.sort((a, b) {
      final aa = deliveryAge(a);
      final ab = deliveryAge(b);
      // Both undelivered: highest age first
      if (aa > -1 && ab > -1) return ab.compareTo(aa);
      // Only one undelivered: it goes to top
      if (aa > -1) return -1;
      if (ab > -1) return 1;

      // If none undelivered, fallback to standard priority
      final pa = _purchaseBusinessPriority(a);
      final pb = _purchaseBusinessPriority(b);
      if (pa != pb) return pa.compareTo(pb);
      return b.purchaseDate.compareTo(a.purchaseDate);
    });
    return out;
  }

  out.sort((a, b) {
    final pa = _purchaseBusinessPriority(a);
    final pb = _purchaseBusinessPriority(b);
    if (pa != pb) return pa.compareTo(pb);

    // Within same priority, newest first (except overdue/pending which is oldest first)
    if (pa == 0 || pa == 2) {
      // Overdue/Pending: most days waiting (highest age) at top
      return undeliveredDaysSincePurchase(b)
          .compareTo(undeliveredDaysSincePurchase(a));
    }

    final dt = b.purchaseDate.compareTo(a.purchaseDate);
    if (dt != 0) return dt;
    return b.humanId.compareTo(a.humanId);
  });

  return out;
}

int _purchaseBusinessPriority(TradePurchase p) {
  final st = p.statusEnum;
  if (st == PurchaseStatus.overdue) return 0;

  // Due today
  if (p.dueDate != null) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(p.dueDate!.year, p.dueDate!.month, p.dueDate!.day);
    if (d == today &&
        st != PurchaseStatus.paid &&
        st != PurchaseStatus.cancelled) {
      return 1;
    }
  }

  // Pending / Recent
  if (!p.isDeliveryCommitted &&
      st != PurchaseStatus.paid &&
      st != PurchaseStatus.cancelled &&
      st != PurchaseStatus.draft) {
    return 2;
  }

  if (st == PurchaseStatus.draft) return 3;

  // Paid / Received / Cancelled
  return 4;
}

bool _showQuickDeliverIcon(TradePurchase p) {
  final st = p.statusEnum;
  if (st == PurchaseStatus.deleted || st == PurchaseStatus.cancelled) {
    return false;
  }
  return p.deliveryStatusEnum.readyForOwnerCommit;
}

bool _showQuickPaidIcon(TradePurchase p) {
  final st = p.statusEnum;
  if (st == PurchaseStatus.deleted ||
      st == PurchaseStatus.cancelled ||
      st == PurchaseStatus.draft) {
    return false;
  }
  return st != PurchaseStatus.paid;
}

/// Purchase History — filters, search, swipe actions, multi-select.
class PurchaseHomePage extends ConsumerStatefulWidget {
  const PurchaseHomePage({super.key});

  @override
  ConsumerState<PurchaseHomePage> createState() => _PurchaseHomePageState();
}

class _PurchaseHomePageState extends ConsumerState<PurchaseHomePage> {
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  final _scroll = ScrollController();
  Timer? _debounce;
  bool _selectMode = false;
  final _selected = <String>{};

  /// Purchase IDs hidden immediately while delete API runs (rolled back on failure).
  final _pendingDeleteIds = <String>{};

  /// Rows patched until list refresh completes after mark paid/delivered.
  final Map<String, TradePurchase> _optimisticPurchasePatches = {};

  void _clearLocalStateForDeletedPurchases(Iterable<String> ids) {
    if (!mounted) return;
    setState(() {
      for (final id in ids) {
        _optimisticPurchasePatches.remove(id);
        _selected.remove(id);
      }
    });
  }

  String _lastRouteFilter = '';
  _HistPeriodPreset _preset = _HistPeriodPreset.month;
  bool _isRefreshing = false;

  void _applyPreset(_HistPeriodPreset p) {
    final n = DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    ref.read(analyticsDateRangeProvider.notifier).state = switch (p) {
      _HistPeriodPreset.today => (from: today, to: today),
      _HistPeriodPreset.week => (
          from: today.subtract(const Duration(days: 6)),
          to: today
        ),
      _HistPeriodPreset.month => (
          from: today.subtract(const Duration(days: 29)),
          to: today
        ),
      _HistPeriodPreset.year => (from: DateTime(n.year, 1, 1), to: today),
      _HistPeriodPreset.allTime => (from: DateTime(2020, 1, 1), to: today),
      _HistPeriodPreset.custom => ref.read(analyticsDateRangeProvider),
    };
    setState(() => _preset = p);
  }

  Future<void> _refreshHistory() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    invalidatePurchaseListSurfacesLight(ref);
    try {
      await ref.read(tradePurchasesListProvider.future);
    } catch (_) {}
    if (mounted) setState(() => _isRefreshing = false);
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final range = ref.read(analyticsDateRangeProvider);
    final picked = await showFullscreenDateRangePicker(
      context,
      initialStart: range.from,
      initialEnd: range.to,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked == null || !mounted) return;
    ref.read(analyticsDateRangeProvider.notifier).state =
        (from: picked.start, to: picked.end);
    setState(() => _preset = _HistPeriodPreset.custom);
  }

  Future<void> _openPeriodPicker() async {
    await showHexaBottomSheet<void>(
      context: context,
      compact: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(
            title: Text('Period',
                style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('Affects History + Reports totals'),
          ),
          for (final e in const [
            (_HistPeriodPreset.today, 'Today'),
            (_HistPeriodPreset.week, 'This week'),
            (_HistPeriodPreset.month, 'This month'),
            (_HistPeriodPreset.year, 'This year'),
            (_HistPeriodPreset.allTime, 'All time'),
            (_HistPeriodPreset.custom, 'Custom range'),
          ])
            ListTile(
              leading: Icon(
                _preset == e.$1
                    ? Icons.check_circle
                    : Icons.circle_outlined,
              ),
              title: Text(e.$2),
              onTap: () async {
                Navigator.pop(context);
                if (e.$1 == _HistPeriodPreset.custom) {
                  await _pickCustomRange();
                } else {
                  _applyPreset(e.$1);
                }
              },
            ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
    _searchFocus.addListener(() => setState(() {}));
    _scroll.addListener(_onHistoryScrollNearEnd);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // IndexedStack keeps History mounted off-screen; never force shell branch here
    // (that fought Stock/Home tab selection and tripped Riverpod during build).
    final shell = StatefulNavigationShell.maybeOf(context);
    if (shell?.currentIndex != ShellBranch.history) return;

    final routerState = GoRouterState.of(context);
    final raw = routerState.uri.queryParameters['filter'];
    final f = (raw == null || raw.isEmpty) ? 'all' : raw.toLowerCase();
    if (f == _lastRouteFilter) return;
    _lastRouteFilter = f;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (StatefulNavigationShell.maybeOf(context)?.currentIndex !=
          ShellBranch.history) {
        return;
      }
      _syncFilterFromRoute();
    });
  }

  void _syncFilterFromRoute() {
    final params = GoRouterState.of(context).uri.queryParameters;
    final mapped = _purchaseFilterFromDeliveryStatus(
      params['delivery_status'],
    );
    final q = params['filter'];
    final f = (mapped ?? (q == null || q.isEmpty ? 'all' : q)).toLowerCase();
    if (f == 'pending' || f == 'overdue') {
      ref.read(purchaseHistoryPrimaryFilterProvider.notifier).state = 'all';
      ref.read(purchaseHistorySecondaryFilterProvider.notifier).state = f;
    } else if (f == 'paid') {
      ref.read(purchaseHistorySecondaryFilterProvider.notifier).state = null;
      ref.read(purchaseHistoryPrimaryFilterProvider.notifier).state = 'paid';
    } else if (f == 'due_today' || f == 'due_soon') {
      ref.read(purchaseHistorySecondaryFilterProvider.notifier).state = null;
      ref.read(purchaseHistoryPrimaryFilterProvider.notifier).state = 'due';
    } else {
      ref.read(purchaseHistorySecondaryFilterProvider.notifier).state = null;
      final primary = _routePrimaryPurchaseFilters.contains(f) ? f : 'all';
      ref.read(purchaseHistoryPrimaryFilterProvider.notifier).state = primary;
      ref.read(purchaseHistoryUndeliveredSortProvider.notifier).state =
          primary == 'pending_delivery' || primary == 'delivery_stuck';
    }
  }

  @override
  void dispose() {
    _scroll.removeListener(_onHistoryScrollNearEnd);
    _debounce?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onHistoryScrollNearEnd() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels < pos.maxScrollExtent - 300) return;
    final async = ref.read(tradePurchasesListProvider);
    final hasMore = async.maybeWhen(
      data: (v) => v.hasMore,
      orElse: () => false,
    );
    if (!hasMore) return;
    unawaited(ref.read(tradePurchasesListProvider.notifier).loadMore());
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      ref.read(purchaseHistorySearchProvider.notifier).state =
          _searchCtrl.text.trim();
    });
  }

  void _selectPrimary(String key) {
    ref.read(purchaseHistoryPrimaryFilterProvider.notifier).state = key;
    ref.read(purchaseHistorySecondaryFilterProvider.notifier).state = null;
    if (key == 'pending_delivery') {
      ref.read(purchaseHistoryUndeliveredSortProvider.notifier).state = true;
    } else {
      ref.read(purchaseHistoryUndeliveredSortProvider.notifier).state = false;
    }
    context.go(key == 'all' ? '/purchase' : '/purchase?filter=$key');
  }

  void _selectSecondary(String key) {
    ref.read(purchaseHistoryPrimaryFilterProvider.notifier).state = 'all';
    ref.read(purchaseHistorySecondaryFilterProvider.notifier).state = key;
    ref.read(purchaseHistoryUndeliveredSortProvider.notifier).state = false;
    context.go('/purchase?filter=$key');
  }

  Future<void> _openMoreFilters() async {
    await showHexaBottomSheet<void>(
      context: context,
      compact: false,
      padding: EdgeInsets.zero,
      child: SizedBox(
        height: HexaResponsive.adaptiveSheetMaxHeight(context) * 0.78,
        child: const _PurchaseHistoryFiltersSheet(),
      ),
    );
  }

  List<TradePurchase> _buildVisibleSorted(
    List<TradePurchase> items,
    String searchQ,
  ) {
    return purchaseHistoryVisibleSortedForRef(
      ref,
      items,
      searchQ,
      pendingDeleteIds: _pendingDeleteIds,
    );
  }

  Future<void> _confirmDelete(BuildContext context, TradePurchase p) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete purchase?'),
        content: Text('Remove ${p.humanId}?'),
        actions: [
          TextButton(
              onPressed: () => ctx.pop(false), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => ctx.pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    setState(() => _pendingDeleteIds.add(p.id));
    try {
      await ref.read(hexaApiProvider).deleteTradePurchase(
            businessId: session.primaryBusiness.id,
            purchaseId: p.id,
          );
      invalidateAfterPurchaseDelete(ref, purchase: p);
      _clearLocalStateForDeletedPurchases([p.id]);
      try {
        await ref.read(tradePurchasesListProvider.future);
      } catch (_) {}
      if (!mounted) return;
      setState(() => _pendingDeleteIds.remove(p.id));
      messenger.showSnackBar(const SnackBar(content: Text('Deleted')));
    } catch (e) {
      if (mounted) {
        setState(() => _pendingDeleteIds.remove(p.id));
      }
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e is DioException
                ? friendlyApiError(e)
                : 'Could not delete this purchase. Check your connection and try again.',
          ),
        ),
      );
    }
  }

  Future<void> _bulkDelete(BuildContext context) async {
    if (_selected.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${_selected.length} purchases?'),
        actions: [
          TextButton(
              onPressed: () => ctx.pop(false), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => ctx.pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    final ids = _selected.toList();
    final list = ref.read(tradePurchasesParsedProvider).valueOrNull ??
        const <TradePurchase>[];
    final catalogIds = <String>{};
    for (final id in ids) {
      for (final p in list) {
        if (p.id == id) {
          catalogIds.addAll(catalogItemIdsFromPurchase(p));
          break;
        }
      }
    }
    setState(() {
      for (final id in ids) {
        _pendingDeleteIds.add(id);
      }
      _selectMode = false;
      _selected.clear();
    });
    for (final id in ids) {
      try {
        await ref.read(hexaApiProvider).deleteTradePurchase(
              businessId: session.primaryBusiness.id,
              purchaseId: id,
            );
      } catch (_) {
        if (mounted) {
          setState(() => _pendingDeleteIds.remove(id));
        }
      }
    }
    invalidateAfterPurchaseDelete(
      ref,
      extraItemIds: catalogIds,
    );
    _clearLocalStateForDeletedPurchases(ids);
    for (final id in ids) {
      ref.invalidate(tradePurchaseDetailProvider(id));
    }
    try {
      await ref.read(tradePurchasesListProvider.future);
    } catch (_) {}
    if (mounted) {
      setState(() => _pendingDeleteIds.removeAll(ids));
    }
  }

  void _selectAllVisible(List<TradePurchase> visible) {
    if (visible.isEmpty) return;
    setState(() {
      _selectMode = true;
      _selected
        ..clear()
        ..addAll(visible.map((e) => e.id));
    });
  }

  Future<void> _exportSelectedCsv(List<TradePurchase> visible) async {
    if (_selected.isEmpty) return;
    final pick = visible.where((p) => _selected.contains(p.id)).toList();
    if (pick.isEmpty) return;
    final df = DateFormat('yyyy-MM-dd');
    final buf = StringBuffer()
      ..writeln(
          'human_id,purchase_date,supplier,total_inr,remaining_inr,status');
    for (final p in pick) {
      buf.writeln(
        '${_histCsvCell(p.humanId)},${df.format(p.purchaseDate)},'
        '${_histCsvCell(p.supplierName ?? '')},${p.totalAmount.toStringAsFixed(2)},'
        '${p.remaining.toStringAsFixed(2)},${_histCsvCell(p.derivedStatus)}',
      );
    }
    await Share.share(
      buf.toString(),
      subject: 'Purchase export (${pick.length})',
    );
  }

  List<TradePurchase> _mergeOptimisticRows(List<TradePurchase> list) {
    if (_optimisticPurchasePatches.isEmpty) return list;
    return [
      for (final row in list) _optimisticPurchasePatches[row.id] ?? row,
    ];
  }

  Future<void> _markPaidQuick(TradePurchase p) async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _optimisticPurchasePatches[p.id] = p.withOptimisticMarkedPaid();
    });
    try {
      await ref.read(hexaApiProvider).markPurchasePaid(
            businessId: session.primaryBusiness.id,
            purchaseId: p.id,
          );
      invalidatePurchaseMetadataLight(ref, purchaseId: p.id);
      try {
        await ref.read(tradePurchasesListProvider.future);
      } catch (_) {}
      if (mounted) {
        setState(() => _optimisticPurchasePatches.remove(p.id));
        showTopSnack(context, 'Marked as paid ✓');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _optimisticPurchasePatches.remove(p.id));
        try {
          await ref.read(tradePurchasesListProvider.future);
        } catch (_) {}
        showTopSnack(
          context,
          e is DioException
              ? friendlyApiError(e)
              : 'Could not mark purchase as paid. Try again.',
          isError: true,
        );
      }
    }
  }

  Future<void> _markDeliveredQuick(TradePurchase p) async {
    if (!p.deliveryStatusEnum.readyForOwnerCommit) return;
    HapticFeedback.mediumImpact();
    if (!mounted) return;
    await commitPurchaseStockFromList(context, ref, p);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final rows =
        ref.watch(tradePurchasesParsedProvider).whenData(_mergeOptimisticRows);
    final primary = ref.watch(purchaseHistoryPrimaryFilterProvider);
    final secondary = ref.watch(purchaseHistorySecondaryFilterProvider);
    final alerts = ref.watch(purchaseAlertsProvider);
    final monthStats = ref.watch(purchaseHistoryMonthStatsProvider);
    final range = ref.watch(analyticsDateRangeProvider);
    final inferred = _purchaseHistInferPreset(range);
    if (inferred != _preset && inferred != _HistPeriodPreset.custom) {
      _preset = inferred;
    }
    final hasAdv = (ref
                .watch(purchaseHistorySupplierContainsProvider)
                ?.trim()
                .isNotEmpty ??
            false) ||
        (ref.watch(purchaseHistoryBrokerContainsProvider)?.trim().isNotEmpty ??
            false) ||
        (ref.watch(purchaseHistoryPackKindFilterProvider)?.isNotEmpty ??
            false) ||
        ref.watch(purchaseHistoryDateFromProvider) != null ||
        ref.watch(purchaseHistoryDateToProvider) != null;
    ref.watch(purchaseHistorySortNewestFirstProvider);
    ref.watch(purchaseHistoryValueSortProvider);
    final undeliveredSort = ref.watch(purchaseHistoryUndeliveredSortProvider);
    final searchQ = ref.watch(purchaseHistorySearchProvider);
    final localWip = ref.watch(purchaseLocalWipDraftForHistoryProvider);
    final narrowHeader = MediaQuery.sizeOf(context).width < 520;

    return Scaffold(
      backgroundColor: HexaColors.brandBackground,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leadingWidth: 0,
        titleSpacing: 0,
        toolbarHeight: 52,
        backgroundColor: HexaColors.brandBackground,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        title: _selectMode
            ? Text('${_selected.length} selected',
                style: const TextStyle(fontWeight: FontWeight.w800))
            : Row(
                children: [
                  IconButton(
                    tooltip: 'Home',
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(
                      minWidth: 40,
                      minHeight: 40,
                    ),
                    icon: const Icon(Icons.home_outlined, size: 22),
                    onPressed: () {
                      final s = ref.read(sessionProvider);
                      if (s != null) context.go(authenticatedHomePath(s));
                    },
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Purchase History',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: HexaColors.brandPrimary,
                          ),
                        ),
                        Text(
                          '${DateFormat('d MMM').format(range.from)} → ${DateFormat('d MMM').format(range.to)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: HexaColors.neutral,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
        actions: [
          if (_selectMode) ...[
            IconButton(
              tooltip: 'Select all (filtered list)',
              onPressed: () {
                final items = rows.asData?.value;
                if (items == null) return;
                final v = _buildVisibleSorted(
                  items,
                  ref.read(purchaseHistorySearchProvider),
                );
                _selectAllVisible(v);
              },
              icon: const Icon(Icons.select_all_rounded),
            ),
            IconButton(
              tooltip: 'Export selected CSV',
              onPressed: () async {
                final items = rows.asData?.value;
                if (items == null) return;
                final v = _buildVisibleSorted(
                  items,
                  ref.read(purchaseHistorySearchProvider),
                );
                await _exportSelectedCsv(v);
              },
              icon: const Icon(Icons.ios_share_rounded),
            ),
            IconButton(
              tooltip: 'Delete',
              onPressed: () => _bulkDelete(context),
              icon: const Icon(Icons.delete_outline_rounded,
                  color: HexaColors.loss),
            ),
            IconButton(
              tooltip: 'Cancel',
              onPressed: () => setState(() {
                _selectMode = false;
                _selected.clear();
              }),
              icon: const Icon(Icons.close_rounded),
            ),
          ] else ...[
            if (!narrowHeader)
              IconButton(
                tooltip: 'Filter by period',
                icon: const Icon(Icons.calendar_today_outlined),
                onPressed: () => unawaited(_openPeriodPicker()),
              ),
            IconButton(
              tooltip: 'More filters',
              icon: Badge(
                isLabelVisible: hasAdv,
                child: const Icon(Icons.filter_list_rounded),
              ),
              onPressed: () => unawaited(_openMoreFilters()),
            ),
            PopupMenuButton<String>(
              tooltip: 'More',
              itemBuilder: (ctx) => [
                if (narrowHeader)
                  const PopupMenuItem(
                    value: 'period',
                    child: ListTile(
                      leading: Icon(Icons.calendar_today_outlined),
                      title: Text('Change period'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                const PopupMenuItem(
                  value: 'refresh',
                  child: ListTile(
                    leading: Icon(Icons.refresh_rounded),
                    title: Text('Refresh'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'select',
                  child: ListTile(
                    leading: Icon(Icons.checklist_rtl_rounded),
                    title: Text('Select purchases'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'scan',
                  child: ListTile(
                    leading: Icon(Icons.document_scanner_outlined),
                    title: Text('Scan bill'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
              onSelected: (v) {
                if (v == 'period') {
                  unawaited(_openPeriodPicker());
                } else if (v == 'refresh') {
                  unawaited(_refreshHistory());
                } else if (v == 'select') {
                  setState(() => _selectMode = true);
                } else if (v == 'scan') {
                  context.push('/purchase/scan');
                }
              },
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: narrowHeader
                  ? IconButton.filled(
                      tooltip: 'New purchase',
                      onPressed: () => context.push('/purchase/new'),
                      icon: const Icon(Icons.add_rounded, size: 22),
                      style: IconButton.styleFrom(
                        backgroundColor: HexaColors.brandPrimary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(40, 40),
                      ),
                    )
                  : FilledButton.icon(
                      onPressed: () => context.push('/purchase/new'),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('New purchase'),
                      style: FilledButton.styleFrom(
                        backgroundColor: HexaColors.brandPrimary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 36),
                      ),
                    ),
            ),
          ],
        ],
      ),
      body: HexaWebPageFrame(
        fullWidth: true,
        maxWidth: 800,
        child: session == null
          ? _SignInPrompt(onTap: () => context.go('/login'))
          : rows.when(
              skipLoadingOnReload: false,
              skipLoadingOnRefresh: true,
              loading: () => const ListSkeleton(),
              error: (e, _) {
                final dio = e is DioException ? e : null;
                final offline =
                    dio != null && dioIsNetworkError(dio);
                return FriendlyLoadError(
                  onRetry: () => unawaited(_refreshHistory()),
                  message: offline
                      ? 'Showing saved purchases — reconnecting…'
                      : 'Could not load purchases. Server error — tap to retry.',
                  subtitle: offline ? kFriendlyLoadNetworkSubtitle : null,
                );
              },
              data: (List<TradePurchase> items) {
                final visible = _buildVisibleSorted(items, searchQ);
                final showLocalWipRow = localWip != null &&
                    !_selectMode &&
                    (primary == 'draft' || primary == 'all');
                final searchActive =
                    _searchFocus.hasFocus || _searchCtrl.text.trim().isNotEmpty;
                final desktop =
                    context.isDesktopLayout && !_selectMode;
                final selectedId = ref.watch(purchaseSelectedIdProvider);
                TradePurchase? selectedSeed;
                if (desktop && selectedId != null) {
                  for (final row in visible) {
                    if (row.id == selectedId) {
                      selectedSeed = row;
                      break;
                    }
                  }
                }
                if (desktop && visible.isNotEmpty) {
                  final sid = selectedId ?? visible.first.id;
                  if (selectedId == null || selectedSeed == null) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        ref.read(purchaseSelectedIdProvider.notifier).state =
                            sid;
                      }
                    });
                  }
                }
                final effectiveSelectedId = desktop
                    ? (selectedId ?? (visible.isNotEmpty ? visible.first.id : null))
                    : null;
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _searchCtrl,
                              focusNode: _searchFocus,
                              style: const TextStyle(fontSize: 13),
                              decoration: const InputDecoration(
                                hintText: 'Search supplier, ID, items…',
                                isDense: true,
                                filled: true,
                                fillColor: Colors.white,
                                border: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.all(Radius.circular(8)),
                                ),
                                prefixIcon:
                                    Icon(Icons.search_rounded, size: 18),
                                contentPadding:
                                    EdgeInsets.fromLTRB(10, 4, 10, 4),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filledTonal(
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Scanner',
                            onPressed: () => context.push('/purchase/scan'),
                            icon: const Icon(Icons.document_scanner_outlined,
                                size: 18),
                          ),
                        ],
                      ),
                    ),
                    CollapsibleSearchChrome(
                      searchActive: searchActive,
                      chrome: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            height: 24,
                            width: double.infinity,
                            margin: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 2),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(3),
                              border: Border.all(color: HexaColors.brandBorder),
                            ),
                            child: Row(
                              children: [
                                _CompactMetric(
                                  label: monthStats.purchaseCount == 0 &&
                                          monthStats.totalInr < 1e-6
                                      ? '₹0'
                                      : _compactInrLakh(monthStats.totalInr),
                                  primary: true,
                                ),
                                _MetricSep(),
                                if (monthStats.purchaseCount > 0) ...[
                                  _CompactMetric(
                                      label: formatPurchaseHistoryMonthPackLine(
                                          monthStats)),
                                  _MetricSep(),
                                ],
                                _CompactMetric(
                                    label: '${monthStats.purchaseCount} Purch'),
                                if ((alerts['overdue'] ?? 0) > 0) ...[
                                  _MetricSep(),
                                  GestureDetector(
                                    onTap: () => _selectSecondary('overdue'),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 5,
                                            vertical: 1,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.red.shade600,
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          child: Text(
                                            '${alerts['overdue']}',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Overdue',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w900,
                                            color: HexaColors.loss,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    SafeArea(
                      top: false,
                      bottom: false,
                      minimum: EdgeInsets.zero,
                      child: SizedBox(
                        height: 38,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: FilterChip(
                                padding: EdgeInsets.zero,
                                labelPadding:
                                    const EdgeInsets.symmetric(horizontal: 6),
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                avatar: Icon(
                                  undeliveredSort
                                      ? Icons.local_shipping_rounded
                                      : Icons.local_shipping_outlined,
                                  size: 14,
                                  color: undeliveredSort
                                      ? const Color(0xFFEA580C)
                                      : const Color(0xFF64748B),
                                ),
                                label: Text(
                                  'Wait ↑',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: undeliveredSort
                                        ? const Color(0xFF0D9488)
                                        : null,
                                  ),
                                ),
                                selected: undeliveredSort,
                                showCheckmark: false,
                                onSelected: (on) {
                                  ref
                                      .read(
                                        purchaseHistoryUndeliveredSortProvider
                                            .notifier,
                                      )
                                      .state = on;
                                },
                              ),
                            ),
                            for (final e in const [
                              ('all', null, 'All'),
                              ('due', null, 'Due'),
                              ('paid', null, 'Paid'),
                              ('draft', null, 'Draft'),
                              (
                                'pending_delivery',
                                Icons.local_shipping_outlined,
                                'Undelivered'
                              ),
                              (
                                'delivery_stuck',
                                Icons.warning_amber_rounded,
                                'Stuck'
                              ),
                              (
                                'received',
                                Icons.check_circle_outline_rounded,
                                'Done'
                              ),
                            ])
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: FilterChip(
                                  padding: EdgeInsets.zero,
                                  labelPadding:
                                      const EdgeInsets.symmetric(horizontal: 6),
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  avatar: e.$2 == null
                                      ? null
                                      : Icon(e.$2, size: 14),
                                  label: Text(
                                    e.$3,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  selected:
                                      secondary == null && primary == e.$1,
                                  onSelected: (_) => _selectPrimary(e.$1),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (secondary != null || hasAdv)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            if (secondary != null)
                              ActionChip(
                                label: Text(
                                  'Status: $secondary · Clear',
                                  style: const TextStyle(fontSize: 11),
                                ),
                                onPressed: () => _selectPrimary('all'),
                              ),
                            if (hasAdv)
                              ActionChip(
                                label: const Text(
                                  'Clear advanced filters',
                                  style: TextStyle(fontSize: 11),
                                ),
                                onPressed: () {
                                  ref
                                      .read(
                                        purchaseHistorySupplierContainsProvider
                                            .notifier,
                                      )
                                      .state = null;
                                  ref
                                      .read(
                                        purchaseHistoryBrokerContainsProvider
                                            .notifier,
                                      )
                                      .state = null;
                                  ref
                                      .read(
                                        purchaseHistoryPackKindFilterProvider
                                            .notifier,
                                      )
                                      .state = null;
                                  ref
                                      .read(
                                        purchaseHistoryDateFromProvider
                                            .notifier,
                                      )
                                      .state = null;
                                  ref
                                      .read(
                                        purchaseHistoryDateToProvider.notifier,
                                      )
                                      .state = null;
                                },
                              ),
                          ],
                        ),
                      ),
                    if (visible.isNotEmpty &&
                        (items.length != visible.length ||
                            items.length >= kTradePurchasesHistoryFetchLimit))
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 2,
                        ),
                        child: Text(
                          items.length >= kTradePurchasesHistoryFetchLimit
                              ? 'Showing latest $kTradePurchasesHistoryFetchLimit · ${visible.length} match'
                              : '${visible.length} of ${items.length}',
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                        ),
                      ),
                    if (_isRefreshing) const OperationalRefreshingBanner(),
                    Expanded(
                      child: desktop
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  flex: 4,
                                  child: RefreshIndicator(
                                    onRefresh: _refreshHistory,
                                    child: _historyScrollContent(
                                      context: context,
                                      items: items,
                                      visible: visible,
                                      showLocalWipRow: showLocalWipRow,
                                      localWip: localWip,
                                      primary: primary,
                                      secondary: secondary,
                                      desktopListSelect: true,
                                      listSelectedId: effectiveSelectedId,
                                    ),
                                  ),
                                ),
                                const VerticalDivider(width: 1, thickness: 1),
                                Expanded(
                                  flex: 6,
                                  child: PurchaseDesktopDetailPane(
                                    purchaseId: effectiveSelectedId,
                                    seedPurchase: selectedSeed ??
                                        (visible.isNotEmpty &&
                                                effectiveSelectedId ==
                                                    visible.first.id
                                            ? visible.first
                                            : null),
                                  ),
                                ),
                              ],
                            )
                          : RefreshIndicator(
                        onRefresh: _refreshHistory,
                        child: visible.isEmpty && !showLocalWipRow
                            ? _purchaseHistoryCenteredEmptyScroll(
                                child: items.isEmpty
                                    ? _HistoryEmpty(
                                        onAdd: () =>
                                            context.push('/purchase/new'),
                                      )
                                    : _HistoryFiltersHideAll(
                                      loadedCount: items.length,
                                      onClearAll: () {
                                        ref
                                            .read(purchaseHistorySearchProvider
                                                .notifier)
                                            .state = '';
                                        _searchCtrl.clear();
                                        ref
                                            .read(
                                              purchaseHistoryPrimaryFilterProvider
                                                  .notifier,
                                            )
                                            .state = 'all';
                                        ref
                                            .read(
                                              purchaseHistorySecondaryFilterProvider
                                                  .notifier,
                                            )
                                            .state = null;
                                        ref
                                            .read(
                                              purchaseHistorySupplierContainsProvider
                                                  .notifier,
                                            )
                                            .state = null;
                                        ref
                                            .read(
                                              purchaseHistoryBrokerContainsProvider
                                                  .notifier,
                                            )
                                            .state = null;
                                        ref
                                            .read(
                                              purchaseHistoryPackKindFilterProvider
                                                  .notifier,
                                            )
                                            .state = null;
                                        ref
                                            .read(
                                              purchaseHistoryDateFromProvider
                                                  .notifier,
                                            )
                                            .state = null;
                                        ref
                                            .read(
                                              purchaseHistoryDateToProvider
                                                  .notifier,
                                            )
                                            .state = null;
                                        context.go('/purchase');
                                      },
                                    ),
                              )
                            : _historyScrollContent(
                                context: context,
                                items: items,
                                visible: visible,
                                showLocalWipRow: showLocalWipRow,
                                localWip: localWip,
                                primary: primary,
                                secondary: secondary,
                                desktopListSelect: false,
                                listSelectedId: null,
                              ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
    );
  }

  Widget _historyScrollContent({
    required BuildContext context,
    required List<TradePurchase> items,
    required List<TradePurchase> visible,
    required bool showLocalWipRow,
    required PurchaseLocalWipDraftVm? localWip,
    required String primary,
    required String? secondary,
    required bool desktopListSelect,
    required String? listSelectedId,
  }) {
    if (visible.isEmpty && !showLocalWipRow) {
      return _purchaseHistoryCenteredEmptyScroll(
        child: items.isEmpty
            ? _HistoryEmpty(onAdd: () => context.push('/purchase/new'))
            : _HistoryFiltersHideAll(
                loadedCount: items.length,
                onClearAll: () {
                ref.read(purchaseHistorySearchProvider.notifier).state = '';
                _searchCtrl.clear();
                ref.read(purchaseHistoryPrimaryFilterProvider.notifier).state =
                    'all';
                ref
                    .read(purchaseHistorySecondaryFilterProvider.notifier)
                    .state = null;
                ref
                    .read(purchaseHistorySupplierContainsProvider.notifier)
                    .state = null;
                ref
                    .read(purchaseHistoryBrokerContainsProvider.notifier)
                    .state = null;
                ref
                    .read(purchaseHistoryPackKindFilterProvider.notifier)
                    .state = null;
                ref.read(purchaseHistoryDateFromProvider.notifier).state =
                    null;
                ref.read(purchaseHistoryDateToProvider.notifier).state = null;
                context.go('/purchase');
              },
            ),
      );
    }
    final grouped = buildGroupedPurchaseHistory(visible);
    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      key: PageStorageKey<String>(
        'hist_${primary}_${secondary ?? ''}_${ref.watch(purchaseHistorySearchProvider)}',
      ),
      controller: _scroll,
      padding: EdgeInsets.fromLTRB(
        0,
        8,
        0,
        96 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      itemCount: grouped.length + (showLocalWipRow ? 1 : 0),
      itemBuilder: (context, i) {
        if (showLocalWipRow && i == 0) {
          return _LocalWipDraftHistoryRow(vm: localWip!);
        }
        final e = grouped[i - (showLocalWipRow ? 1 : 0)];
        if (e is PurchaseHistoryDateHeader) {
          return OperationalDateHeader(e.label);
        }
        final p = (e as PurchaseHistoryPurchaseRow).purchase;
        return _PurchaseRow(
          p: p,
          serial: visible.indexOf(p) + 1,
          selectMode: _selectMode,
          selected: _selected.contains(p.id),
          listHighlighted:
              desktopListSelect && listSelectedId == p.id,
          onLongPress: () {
            HapticFeedback.mediumImpact();
            setState(() {
              _selectMode = true;
              _selected.add(p.id);
            });
          },
          onTap: () {
            if (_selectMode) {
              setState(() {
                if (_selected.contains(p.id)) {
                  _selected.remove(p.id);
                } else {
                  _selected.add(p.id);
                }
              });
            } else if (desktopListSelect) {
              ref.read(purchaseSelectedIdProvider.notifier).state = p.id;
            } else {
              context.push('/purchase/detail/${p.id}', extra: p);
            }
          },
          onEdit: () => context.push('/purchase/edit/${p.id}'),
          onMarkPaid: () => _markPaidQuick(p),
          onMarkDelivered: () => _markDeliveredQuick(p),
          onDelete: () => _confirmDelete(context, p),
          onShare: () async {
            final biz = ref.read(invoiceBusinessProfileProvider);
            Future<void> doShare() async {
              try {
                final result = await sharePurchasePdf(p, biz);
                if (!context.mounted) return;
                if (result.ok) {
                  showTopSnack(context, result.message);
                  return;
                }
                showTopSnack(
                  context,
                  result.message,
                  isError: true,
                  duration: const Duration(seconds: 6),
                  action: SnackBarAction(
                    label: 'Retry',
                    onPressed: () => doShare(),
                  ),
                );
              } catch (e) {
                if (!context.mounted) return;
                showTopSnack(
                  context,
                  'Failed to export PDF.',
                  isError: true,
                );
              }
            }

            await doShare();
          },
        );
      },
    );
  }
}

class _PurchaseHistoryFiltersSheet extends ConsumerStatefulWidget {
  const _PurchaseHistoryFiltersSheet();

  @override
  ConsumerState<_PurchaseHistoryFiltersSheet> createState() =>
      _PurchaseHistoryFiltersSheetState();
}

class _PurchaseHistoryFiltersSheetState
    extends ConsumerState<_PurchaseHistoryFiltersSheet> {
  late final TextEditingController _supplier;
  late final TextEditingController _broker;

  @override
  void initState() {
    super.initState();
    _supplier = TextEditingController(
      text: ref.read(purchaseHistorySupplierContainsProvider) ?? '',
    );
    _broker = TextEditingController(
      text: ref.read(purchaseHistoryBrokerContainsProvider) ?? '',
    );
  }

  @override
  void dispose() {
    _supplier.dispose();
    _broker.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool isFrom) async {
    final cur = isFrom
        ? ref.read(purchaseHistoryDateFromProvider)
        : ref.read(purchaseHistoryDateToProvider);
    final now = DateTime.now();
    final first = DateTime(now.year - 5, 1, 1);
    final last = DateTime(now.year + 1, 12, 31);
    var initial = cur ?? now;
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;

    final d = await Navigator.of(context).push<DateTime>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) {
          var selected = initial;
          return Scaffold(
            appBar: AppBar(
              title: Text(isFrom ? 'From date' : 'To date'),
              leading: IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(ctx),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(
                    ctx,
                    DateTime(selected.year, selected.month, selected.day),
                  ),
                  child: const Text('Done'),
                ),
              ],
            ),
            body: SafeArea(
              child: CalendarDatePicker(
                initialDate: selected,
                firstDate: first,
                lastDate: last,
                onDateChanged: (v) => selected = v,
              ),
            ),
          );
        },
      ),
    );
    if (d == null || !mounted) return;
    if (isFrom) {
      ref.read(purchaseHistoryDateFromProvider.notifier).state = d;
    } else {
      ref.read(purchaseHistoryDateToProvider.notifier).state = d;
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd MMM yyyy');
    final pack = ref.watch(purchaseHistoryPackKindFilterProvider);
    final newest = ref.watch(purchaseHistorySortNewestFirstProvider);
    final dateFrom = ref.watch(purchaseHistoryDateFromProvider);
    final dateTo = ref.watch(purchaseHistoryDateToProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            children: [
                const Text(
                  'Filters & sort',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Latest first'),
                  value: newest,
                  onChanged: (v) {
                    ref
                        .read(purchaseHistorySortNewestFirstProvider.notifier)
                        .state = v;
                  },
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Amount sort',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    ChoiceChip(
                      label: const Text('Off'),
                      selected:
                          ref.watch(purchaseHistoryValueSortProvider) == null,
                      onSelected: (_) {
                        ref
                            .read(purchaseHistoryValueSortProvider.notifier)
                            .state = null;
                      },
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    ChoiceChip(
                      label: const Text('₹ High→Low'),
                      selected:
                          ref.watch(purchaseHistoryValueSortProvider) == 'high',
                    onSelected: (_) {
                      ref
                          .read(purchaseHistoryValueSortProvider.notifier)
                          .state = 'high';
                    },
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  ChoiceChip(
                    label: const Text('₹ Low→High'),
                    selected:
                        ref.watch(purchaseHistoryValueSortProvider) == 'low',
                    onSelected: (_) {
                      ref
                          .read(purchaseHistoryValueSortProvider.notifier)
                          .state = 'low';
                    },
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.hourglass_top_rounded),
                title: const Text('Pending (confirmed)'),
                onTap: () {
                  ref
                      .read(purchaseHistoryPrimaryFilterProvider.notifier)
                      .state = 'all';
                  ref
                      .read(purchaseHistorySecondaryFilterProvider.notifier)
                      .state = 'pending';
                  context.go('/purchase?filter=pending');
                  Navigator.pop(context);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.payments_rounded),
                title: const Text('Paid (server filter)'),
                onTap: () {
                  ref
                      .read(purchaseHistorySecondaryFilterProvider.notifier)
                      .state = null;
                  ref
                      .read(purchaseHistoryPrimaryFilterProvider.notifier)
                      .state = 'paid';
                  context.go('/purchase?filter=paid');
                  Navigator.pop(context);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.warning_amber_rounded),
                title: const Text('Overdue'),
                onTap: () {
                  ref
                      .read(purchaseHistoryPrimaryFilterProvider.notifier)
                      .state = 'all';
                  ref
                      .read(purchaseHistorySecondaryFilterProvider.notifier)
                      .state = 'overdue';
                  context.go('/purchase?filter=overdue');
                  Navigator.pop(context);
                },
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Purchase date from'),
                subtitle: Text(dateFrom != null ? df.format(dateFrom) : 'Any'),
                trailing: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    ref.read(purchaseHistoryDateFromProvider.notifier).state =
                        null;
                  },
                ),
                onTap: () => _pickDate(true),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Purchase date to'),
                subtitle: Text(dateTo != null ? df.format(dateTo) : 'Any'),
                trailing: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    ref.read(purchaseHistoryDateToProvider.notifier).state =
                        null;
                  },
                ),
                onTap: () => _pickDate(false),
              ),
              DropdownButtonFormField<String?>(
                key: ValueKey<String?>(pack),
                initialValue: pack,
                decoration: const InputDecoration(
                  labelText: 'Package type',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: null, child: Text('Any')),
                  DropdownMenuItem(value: 'bag', child: Text('Bag only')),
                  DropdownMenuItem(value: 'box', child: Text('Box only')),
                  DropdownMenuItem(value: 'tin', child: Text('Tin only')),
                  DropdownMenuItem(value: 'mixed', child: Text('Mixed')),
                ],
                onChanged: (v) {
                  ref
                      .read(purchaseHistoryPackKindFilterProvider.notifier)
                      .state = v;
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _supplier,
                decoration: const InputDecoration(
                  labelText: 'Supplier name contains',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _broker,
                decoration: const InputDecoration(
                  labelText: 'Broker name contains',
                  border: OutlineInputBorder(),
                ),
              ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton(
                  onPressed: () {
                    ref
                        .read(purchaseHistorySupplierContainsProvider.notifier)
                        .state = _supplier.text.trim().isEmpty
                            ? null
                            : _supplier.text.trim();
                    ref
                        .read(purchaseHistoryBrokerContainsProvider.notifier)
                        .state =
                        _broker.text.trim().isEmpty ? null : _broker.text.trim();
                    Navigator.pop(context);
                  },
                  child: const Text('Apply'),
                ),
                TextButton(
                  onPressed: () {
                    _supplier.clear();
                    _broker.clear();
                    ref
                        .read(purchaseHistorySupplierContainsProvider.notifier)
                        .state = null;
                    ref
                        .read(purchaseHistoryBrokerContainsProvider.notifier)
                        .state = null;
                    ref
                        .read(purchaseHistoryPackKindFilterProvider.notifier)
                        .state = null;
                    ref.read(purchaseHistoryDateFromProvider.notifier).state =
                        null;
                    ref.read(purchaseHistoryDateToProvider.notifier).state =
                        null;
                  },
                  child: const Text('Clear advanced filters'),
                ),
              ],
            ),
          ),
        ],
    );
  }
}

class _LocalWipDraftHistoryRow extends StatelessWidget {
  const _LocalWipDraftHistoryRow({required this.vm});

  final PurchaseLocalWipDraftVm vm;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () => context.pushNamed(
          'purchase_new',
          extra: <String, dynamic>{'resumeDraft': true},
        ),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.7),
              width: 1.5,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFFF59E0B).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'Draft',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFD97706),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            vm.titleLine,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: HexaDsType.purchaseQtyUnit.copyWith(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFF0F172A),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      vm.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: HexaColors.neutral,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Colors.grey.shade600),
            ],
          ),
        ),
      ),
    );
  }
}

class _PurchaseHistoryFullscreenSearchPage extends ConsumerStatefulWidget {
  const _PurchaseHistoryFullscreenSearchPage({
    required this.initialSearchText,
  });

  final String initialSearchText;

  @override
  ConsumerState<_PurchaseHistoryFullscreenSearchPage> createState() =>
      _PurchaseHistoryFullscreenSearchPageState();
}

class _PurchaseHistoryFullscreenSearchPageState
    extends ConsumerState<_PurchaseHistoryFullscreenSearchPage> {
  late final TextEditingController _c;
  final Map<String, TradePurchase> _optimisticPurchasePatches = {};
  _HistPeriodPreset _preset = _HistPeriodPreset.month;

  void _clearLocalStateForDeletedPurchases(Iterable<String> ids) {
    if (!mounted) return;
    setState(() {
      for (final id in ids) {
        _optimisticPurchasePatches.remove(id);
      }
    });
  }

  List<TradePurchase> _mergeOptimisticRows(List<TradePurchase> list) {
    if (_optimisticPurchasePatches.isEmpty) return list;
    return [
      for (final row in list) _optimisticPurchasePatches[row.id] ?? row,
    ];
  }

  void _applyPreset(_HistPeriodPreset p) {
    final n = DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    ref.read(analyticsDateRangeProvider.notifier).state = switch (p) {
      _HistPeriodPreset.today => (from: today, to: today),
      _HistPeriodPreset.week => (
          from: today.subtract(const Duration(days: 6)),
          to: today
        ),
      _HistPeriodPreset.month => (
          from: today.subtract(const Duration(days: 29)),
          to: today
        ),
      _HistPeriodPreset.year => (from: DateTime(n.year, 1, 1), to: today),
      _HistPeriodPreset.allTime => (from: DateTime(2020, 1, 1), to: today),
      _HistPeriodPreset.custom => ref.read(analyticsDateRangeProvider),
    };
    setState(() => _preset = p);
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final range = ref.read(analyticsDateRangeProvider);
    final picked = await showFullscreenDateRangePicker(
      context,
      initialStart: range.from,
      initialEnd: range.to,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked == null || !mounted) return;
    ref.read(analyticsDateRangeProvider.notifier).state =
        (from: picked.start, to: picked.end);
    setState(() => _preset = _HistPeriodPreset.custom);
  }

  Future<void> _openPeriodPicker() async {
    await showHexaBottomSheet<void>(
      context: context,
      compact: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(
            title: Text('Period',
                style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('Affects History + Reports totals'),
          ),
          for (final e in const [
            (_HistPeriodPreset.today, 'Today'),
            (_HistPeriodPreset.week, 'This week'),
            (_HistPeriodPreset.month, 'This month'),
            (_HistPeriodPreset.year, 'This year'),
            (_HistPeriodPreset.allTime, 'All time'),
            (_HistPeriodPreset.custom, 'Custom range'),
          ])
            ListTile(
              leading: Icon(
                _preset == e.$1
                    ? Icons.check_circle
                    : Icons.circle_outlined,
              ),
              title: Text(e.$2),
              onTap: () async {
                Navigator.pop(context);
                if (e.$1 == _HistPeriodPreset.custom) {
                  await _pickCustomRange();
                } else {
                  _applyPreset(e.$1);
                }
              },
            ),
        ],
      ),
    );
  }

  Future<void> _openMoreFilters() async {
    await showHexaBottomSheet<void>(
      context: context,
      compact: false,
      padding: EdgeInsets.zero,
      child: SizedBox(
        height: HexaResponsive.adaptiveSheetMaxHeight(context) * 0.78,
        child: const _PurchaseHistoryFiltersSheet(),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    ref.read(purchaseHistoryFullscreenSearchActiveProvider.notifier).state =
        true;
    _c = TextEditingController(text: widget.initialSearchText);
    _c.addListener(() {
      ref.read(purchaseHistorySearchProvider.notifier).state = _c.text.trim();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(purchaseHistorySearchProvider.notifier).state =
          widget.initialSearchText.trim();
    });
  }

  @override
  void dispose() {
    ref.read(purchaseHistoryFullscreenSearchActiveProvider.notifier).state =
        false;
    _c.dispose();
    super.dispose();
  }

  Future<void> _markPaid(TradePurchase p) async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _optimisticPurchasePatches[p.id] = p.withOptimisticMarkedPaid();
    });
    try {
      await ref.read(hexaApiProvider).markPurchasePaid(
            businessId: session.primaryBusiness.id,
            purchaseId: p.id,
          );
      invalidatePurchaseMetadataLight(ref, purchaseId: p.id);
      try {
        await ref.read(tradePurchasesListProvider.future);
      } catch (_) {}
      if (mounted) {
        setState(() => _optimisticPurchasePatches.remove(p.id));
        showTopSnack(context, 'Marked as paid ✓');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _optimisticPurchasePatches.remove(p.id));
        try {
          await ref.read(tradePurchasesListProvider.future);
        } catch (_) {}
        showTopSnack(
          context,
          e is DioException
              ? friendlyApiError(e)
              : 'Could not mark purchase as paid. Try again.',
          isError: true,
        );
      }
    }
  }

  Future<void> _markDelivered(TradePurchase p) async {
    if (!p.deliveryStatusEnum.readyForOwnerCommit) return;
    HapticFeedback.mediumImpact();
    if (!mounted) return;
    await commitPurchaseStockFromList(context, ref, p);
  }

  Future<void> _confirmDelete(BuildContext ctx, TradePurchase p) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        title: const Text('Delete purchase?'),
        content: Text('Remove ${p.humanId}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dCtx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !ctx.mounted) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      await ref.read(hexaApiProvider).deleteTradePurchase(
            businessId: session.primaryBusiness.id,
            purchaseId: p.id,
          );
      invalidateAfterPurchaseDelete(ref, purchase: p);
      _clearLocalStateForDeletedPurchases([p.id]);
      try {
        await ref.read(tradePurchasesListProvider.future);
      } catch (_) {}
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(content: Text('Deleted')),
        );
      }
    } catch (e) {
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text(
            e is DioException
                ? friendlyApiError(e)
                : 'Could not delete this purchase. Check your connection and try again.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final range = ref.watch(analyticsDateRangeProvider);
    final inferred = _purchaseHistInferPreset(range);
    if (inferred != _preset && inferred != _HistPeriodPreset.custom) {
      _preset = inferred;
    }
    final hasAdv = (ref
                .watch(purchaseHistorySupplierContainsProvider)
                ?.trim()
                .isNotEmpty ??
            false) ||
        (ref.watch(purchaseHistoryBrokerContainsProvider)?.trim().isNotEmpty ??
            false) ||
        (ref.watch(purchaseHistoryPackKindFilterProvider)?.isNotEmpty ??
            false) ||
        ref.watch(purchaseHistoryDateFromProvider) != null ||
        ref.watch(purchaseHistoryDateToProvider) != null;
    final rows =
        ref.watch(tradePurchasesParsedProvider).whenData(_mergeOptimisticRows);
    final searchQ = ref.watch(purchaseHistorySearchProvider);
    ref.watch(purchaseHistoryValueSortProvider);
    return FullscreenSearchShell(
      title: 'Search purchases',
      actions: [
        IconButton(
          tooltip: 'Filter by period',
          icon: const Icon(Icons.calendar_today_outlined),
          onPressed: () => unawaited(_openPeriodPicker()),
        ),
        IconButton(
          tooltip: 'More filters',
          icon: Badge(
            isLabelVisible: hasAdv,
            child: const Icon(Icons.filter_list_rounded),
          ),
          onPressed: () => unawaited(_openMoreFilters()),
        ),
      ],
      searchField: TextField(
        controller: _c,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: 'Search supplier, PUR ID, items, broker…',
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          prefixIcon: Icon(Icons.search_rounded, size: 22),
          contentPadding: EdgeInsets.symmetric(vertical: 10),
        ),
      ),
      body: rows.when(
        skipLoadingOnReload: false,
        skipLoadingOnRefresh: true,
        loading: () => const ListSkeleton(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 32),
        ),
        error: (_, __) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: FriendlyLoadError(
              message: 'Could not load purchases.',
              subtitle: kFriendlyLoadNetworkSubtitle,
              onRetry: () => ref.invalidate(tradePurchasesListProvider),
            ),
          ),
        ),
        data: (items) {
          final visible = purchaseHistoryVisibleSortedForRef(
            ref,
            items,
            searchQ,
            pendingDeleteIds: const {},
          );
          if (visible.isEmpty) {
            final emptyMsg = searchQ.trim().isEmpty
                ? 'No purchases in this period or filters.'
                : 'No matches for your search.';
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: EdgeInsets.fromLTRB(
                24,
                32,
                24,
                24 + MediaQuery.viewPaddingOf(context).bottom,
              ),
              children: [
                Icon(
                  Icons.inbox_outlined,
                  size: 48,
                  color: Colors.grey.shade500,
                ),
                const SizedBox(height: 16),
                Text(
                  emptyMsg,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0F172A),
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Try another period, clear filters, or pull to refresh on the History tab.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade700,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 20),
                Align(
                  child: FilledButton.icon(
                    onPressed: () => ref.invalidate(tradePurchasesListProvider),
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                    label: const Text('Retry load'),
                  ),
                ),
              ],
            );
          }
          final grouped = buildGroupedPurchaseHistory(visible);
          return ListView.builder(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: EdgeInsets.fromLTRB(
              0,
              8,
              0,
              96 + MediaQuery.viewPaddingOf(context).bottom,
            ),
            itemCount: grouped.length,
            itemBuilder: (ctx, i) {
              final e = grouped[i];
              if (e is PurchaseHistoryDateHeader) {
                return OperationalDateHeader(e.label);
              }
              final p = (e as PurchaseHistoryPurchaseRow).purchase;
              return _PurchaseRow(
                p: p,
                serial: visible.indexOf(p) + 1,
                selectMode: false,
                selected: false,
                onLongPress: () {},
                onTap: () => context.push(
                  '/purchase/detail/${p.id}',
                  extra: p,
                ),
                onEdit: () => context.push('/purchase/edit/${p.id}'),
                onMarkPaid: () => _markPaid(p),
                onMarkDelivered: () => _markDelivered(p),
                onDelete: () => _confirmDelete(ctx, p),
                onShare: () async {
                  final biz = ref.read(invoiceBusinessProfileProvider);
                  Future<void> doShare() async {
                    try {
                      final result = await sharePurchasePdf(p, biz);
                      if (!context.mounted) return;
                      if (result.ok) {
                        showTopSnack(context, result.message);
                        return;
                      }
                      showTopSnack(
                        context,
                        result.message,
                        isError: true,
                        duration: const Duration(seconds: 6),
                        action: SnackBarAction(
                          label: 'Retry',
                          onPressed: () => doShare(),
                        ),
                      );
                    } catch (e) {
                      if (!context.mounted) return;
                      showTopSnack(
                        context,
                        'Failed to export PDF.',
                        isError: true,
                      );
                    }
                  }

                  await doShare();
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _PurchaseRow extends StatelessWidget {
  const _PurchaseRow({
    required this.p,
    required this.serial,
    required this.selectMode,
    required this.selected,
    this.listHighlighted = false,
    required this.onLongPress,
    required this.onTap,
    required this.onEdit,
    required this.onMarkPaid,
    required this.onMarkDelivered,
    required this.onDelete,
    required this.onShare,
  });

  final TradePurchase p;
  final int serial;
  final bool selectMode;
  final bool selected;
  final bool listHighlighted;
  final VoidCallback onLongPress;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onMarkPaid;
  final VoidCallback onMarkDelivered;
  final VoidCallback onDelete;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final st = p.statusEnum;
    final supp = p.supplierName ?? p.supplierId?.toString() ?? '—';
    final headline = purchaseHistoryItemHeadline(p);
    final pack = purchaseHistoryPackSummary(p);
    final daysChip = _purchaseHistoryDaysChip(p);
    final agingBand = undeliveredAgingBandForPurchase(p);
    final ds = p.deliveryStatusEnum;
    final cancelled = st == PurchaseStatus.cancelled || ds == DeliveryStatus.cancelled;

    final tileInk = InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(0),
      child: Container(
        constraints: const BoxConstraints(minHeight: 80),
        decoration: deliveryStatusRowDecoration(
          deliveryStatus: ds,
          background: listHighlighted
              ? const Color(0xFFE8F4F2)
              : Colors.white,
          undeliveredBand: agingBand,
        ),
        padding: const EdgeInsets.fromLTRB(10, 5, 10, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          supp.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.2,
                            color: const Color(0xFF0F172A),
                            height: 1.1,
                            decoration:
                                cancelled ? TextDecoration.lineThrough : null,
                            decorationColor: const Color(0xFF9CA3AF),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _inr(p.totalAmount.round()),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF111827),
                          letterSpacing: -0.35,
                          height: 1.0,
                          decoration:
                              cancelled ? TextDecoration.lineThrough : null,
                          decorationColor: const Color(0xFF9CA3AF),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    headline,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF1E293B),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        pack,
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0D9488),
                          letterSpacing: 0.1,
                        ),
                      ),
                      const _Dot(),
                      _CompactDetailLabel(
                        label: formatPurchaseHumanDate(p.purchaseDate),
                      ),
                      const _Dot(),
                      _CompactDetailLabel(label: p.humanId),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (daysChip != null) ...[
                        daysChip,
                        const SizedBox(width: 6),
                      ],
                      _MiniBadge(st),
                      const SizedBox(width: 6),
                      PurchaseDeliveryBadge(
                        status: p.deliveryStatusEnum,
                        compact: true,
                      ),
                      const Spacer(),
                      if (!selectMode &&
                          (_showQuickDeliverIcon(p) || _showQuickPaidIcon(p)))
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_showQuickDeliverIcon(p))
                              _QuickActionBtn(
                                label: 'COMMIT STOCK',
                                color: Colors.orange.shade800,
                                bg: Colors.orange.shade50,
                                onTap: onMarkDelivered,
                              ),
                            if (_showQuickPaidIcon(p))
                              _QuickActionBtn(
                                label: 'PAY',
                                color: HexaColors.brandAccent,
                                bg: HexaColors.brandAccent
                                    .withValues(alpha: 0.1),
                                onTap: onMarkPaid,
                              ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    final card = Container(
      decoration: deliveryStatusRowDecoration(
        deliveryStatus: ds,
        background: Colors.white,
        undeliveredBand: agingBand,
        border: Border(bottom: BorderSide(color: HexaColors.brandBorder)),
      ),
      child: Material(
        color: Colors.transparent,
        child: tileInk,
      ),
    );

    if (selectMode) return card;

    return Slidable(
      key: ValueKey(p.id),
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        children: [
          SlidableAction(
            onPressed: (_) => onEdit(),
            backgroundColor: HexaColors.brandPrimary,
            foregroundColor: Colors.white,
            icon: Icons.edit_rounded,
            label: 'Edit',
          ),
          SlidableAction(
            onPressed: (_) => onMarkPaid(),
            backgroundColor: HexaColors.brandAccent,
            foregroundColor: Colors.white,
            icon: Icons.payments_rounded,
            label: 'Paid',
          ),
          SlidableAction(
            onPressed: (_) => onShare(),
            backgroundColor: Colors.teal,
            foregroundColor: Colors.white,
            icon: Icons.share_rounded,
            label: 'Share',
          ),
          SlidableAction(
            onPressed: (_) => onDelete(),
            backgroundColor: HexaColors.loss,
            foregroundColor: Colors.white,
            icon: Icons.delete_outline_rounded,
            label: 'Del',
          ),
        ],
      ),
      child: card,
    );
  }
}

class _MiniBadge extends StatelessWidget {
  const _MiniBadge(this.st);
  final PurchaseStatus st;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: st.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: st.color.withValues(alpha: 0.45), width: 1),
      ),
      child: Text(
        _historyPaymentChipLabel(st).toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          height: 1.1,
          color: st.color,
        ),
      ),
    );
  }
}

class _CompactMetric extends StatelessWidget {
  const _CompactMetric({required this.label, this.primary = false});
  final String label;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w900,
      color: primary ? HexaColors.brandPrimary : const Color(0xFF475569),
    );
    return Text(label, style: style);
  }
}

class _MetricSep extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text('|',
          style: TextStyle(color: Colors.grey.shade300, fontSize: 10)),
    );
  }
}

class _CompactDetailLabel extends StatelessWidget {
  const _CompactDetailLabel({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w800,
        color: Color(0xFF64748B),
        letterSpacing: 0.1,
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child:
          Text('•', style: TextStyle(color: Colors.grey.shade400, fontSize: 8)),
    );
  }
}

class _QuickActionBtn extends StatelessWidget {
  const _QuickActionBtn(
      {required this.label,
      required this.color,
      required this.bg,
      required this.onTap});
  final String label;
  final Color color;
  final Color bg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        constraints: const BoxConstraints(minHeight: 32),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        margin: const EdgeInsets.only(left: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.2,
              color: color,
              height: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}

class _HistoryFiltersHideAll extends StatelessWidget {
  const _HistoryFiltersHideAll({
    required this.loadedCount,
    required this.onClearAll,
  });

  final int loadedCount;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.filter_alt_off_rounded,
              size: 52,
              color: Colors.orange.shade700,
            ),
            const SizedBox(height: 14),
            Text(
              'Filters hide all purchases',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: HexaColors.brandPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Search or filters hide every one of your $loadedCount loaded '
              'purchases. Clear filters to see the list again.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.35,
                color: Colors.grey.shade800,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 22),
            FilledButton(
              onPressed: onClearAll,
              child: const Text('Clear search & filters'),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryEmpty extends StatelessWidget {
  const _HistoryEmpty({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return HexaEmptyState(
      icon: Icons.receipt_long_outlined,
      title: 'No purchases yet',
      subtitle:
          'Create a purchase to see it here. Search and filters apply once you have bills on file.',
      primaryActionLabel: 'New purchase',
      onPrimaryAction: onAdd,
    );
  }
}

class _SignInPrompt extends StatelessWidget {
  const _SignInPrompt({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FilledButton(onPressed: onTap, child: const Text('Sign In')),
    );
  }
}
