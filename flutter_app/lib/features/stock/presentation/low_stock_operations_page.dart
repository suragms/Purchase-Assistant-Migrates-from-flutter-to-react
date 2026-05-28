import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/realtime_events_provider.dart';
import '../../../core/providers/home_dashboard_provider.dart';
import '../../../core/providers/analytics_kpi_provider.dart';
import '../../../core/providers/low_stock_providers.dart';
import '../../../core/design_system/hexa_responsive.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/widgets/friendly_load_error.dart';
import 'widgets/low_stock_category_group.dart';
import 'widgets/low_stock_desktop_shell.dart';
import 'widgets/low_stock_filter_bar.dart';
import 'widgets/low_stock_bulk_export.dart';
import 'widgets/low_stock_ops_header.dart';
import '../../../core/auth/session_notifier.dart';

class LowStockOperationsPage extends ConsumerStatefulWidget {
  const LowStockOperationsPage({super.key, required this.staffMode});

  final bool staffMode;

  @override
  ConsumerState<LowStockOperationsPage> createState() =>
      _LowStockOperationsPageState();
}

class _LowStockOperationsPageState extends ConsumerState<LowStockOperationsPage> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  String _search = '';
  LowStockOpsFilter _active = LowStockOpsFilter.all;
  String? _selectedCategory;
  bool _bulkMode = false;
  final _selectedIds = <String>{};
  Map<String, dynamic>? _selectedItem;
  bool _didShowReminderDialog = false;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      final q = _searchCtrl.text.trim();
      if (_search == q) return;
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 200), () {
        if (!mounted) return;
        setState(() => _search = q);
        final cur = ref.read(lowStockOperationsQueryProvider);
        ref.read(lowStockOperationsQueryProvider.notifier).state =
            cur.copyWith(q: q, page: 1);
      });
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final uri = GoRouterState.of(context).uri;
      final rawFilter = uri.queryParameters['filter'];
      final rawQ = uri.queryParameters['q'];

      if (rawFilter != null && rawFilter.trim().isNotEmpty) {
        final f = _filterFromRoute(rawFilter.trim());
        if (f != _active) {
          setState(() => _active = f);
          final cur = ref.read(lowStockOperationsQueryProvider);
          ref.read(lowStockOperationsQueryProvider.notifier).state =
              cur.copyWith(filter: _backendFilterFor(f), page: 1);
        }
      }

      if (rawQ != null && rawQ.trim().isNotEmpty) {
        final q = rawQ.trim();
        _search = q;
        _searchCtrl.text = q;
        final cur = ref.read(lowStockOperationsQueryProvider);
        ref.read(lowStockOperationsQueryProvider.notifier).state =
            cur.copyWith(q: q, page: 1);
      }
    });
  }

  LowStockOpsFilter _filterFromRoute(String raw) => switch (raw) {
        'all' => LowStockOpsFilter.all,
        'low' => LowStockOpsFilter.low,
        'out' => LowStockOpsFilter.out,
        'pending' => LowStockOpsFilter.pending,
        'delayed' => LowStockOpsFilter.delayed,
        'disputed' => LowStockOpsFilter.disputed,
        'verification' => LowStockOpsFilter.verification,
        'urgent' => LowStockOpsFilter.urgent,
        'high_impact' => LowStockOpsFilter.highSalesImpact,
        _ => LowStockOpsFilter.all,
      };

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(lowStockOperationsSummaryProvider);
    ref.invalidate(lowStockOperationsPageProvider);
  }

  String _backendFilterFor(LowStockOpsFilter f) => switch (f) {
        LowStockOpsFilter.all => 'all',
        LowStockOpsFilter.low => 'low',
        LowStockOpsFilter.out => 'out',
        LowStockOpsFilter.pending => 'pending',
        LowStockOpsFilter.delayed => 'delayed',
        LowStockOpsFilter.disputed => 'disputed',
        LowStockOpsFilter.verification => 'verification',
        LowStockOpsFilter.urgent => 'urgent',
        LowStockOpsFilter.highSalesImpact => 'high_impact',
      };

  void _showSmartReminderIfNeeded({
    required int outCount,
    required int delayedCount,
    required int pendingVerificationCount,
  }) {
    if (_didShowReminderDialog) return;
    final reminders = <String>[
      if (outCount > 0) '$outCount items are out of stock.',
      if (delayedCount > 0) '$delayedCount supplier orders are delayed.',
      if (pendingVerificationCount > 0)
        '$pendingVerificationCount items need physical verification.',
    ];
    if (reminders.isEmpty) return;
    _didShowReminderDialog = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(widget.staffMode ? 'Staff reminder' : 'Owner reminder'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final r in reminders)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('• $r'),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Later'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                if (widget.staffMode) {
                  context.push('/staff/low-stock?filter=verification');
                } else {
                  context.push('/stock/reorder');
                }
              },
              child: Text(widget.staffMode ? 'Open verification' : 'Open reorder'),
            ),
          ],
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(realtimeInvalidationProvider);

    final desktop = HexaBreakpoints.isDesktop(context);
    final gutter = HexaResponsive.pageGutter(context, operational: true);

    final period = ref.watch(homePeriodProvider);
    final customRange = ref.watch(analyticsDateRangeProvider);
    final range = homePeriodRange(
      period,
      now: DateTime.now(),
      custom: period == HomePeriod.custom
          ? (start: customRange.from, endInclusive: customRange.to)
          : null,
    );
    final periodDays = range.end.difference(range.start).inDays;

    final summaryAsync = ref.watch(lowStockOperationsSummaryProvider);
    final opsAsync = ref.watch(lowStockOperationsPageProvider);

    return Scaffold(
      backgroundColor: HexaColors.brandBackground,
      body: SafeArea(
        child: summaryAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, __) => FriendlyLoadError(
            message: 'Could not load low stock',
            onRetry: () => _refresh(),
          ),
          data: (summary) {
            final totalAttention =
                (summary['total_attention'] as num?)?.toInt() ?? 0;
            final outCount =
                (summary['out_of_stock'] as num?)?.toInt() ?? 0;
            final pendingCount =
                (summary['pending_purchase'] as num?)?.toInt() ?? 0;
            final delayedCount =
                (summary['delayed_supplier'] as num?)?.toInt() ?? 0;
            final mismatchCount =
                (summary['mismatch_items'] as num?)?.toInt() ?? 0;
            final pendingVerificationCount =
                (summary['pending_verification'] as num?)?.toInt() ?? 0;
            final impactUnitsPerDay =
                (summary['estimated_impact_units_per_day'] as num?)?.toDouble() ??
                    0.0;
            final estimatedImpactLabel =
                'Impact: ${impactUnitsPerDay.toStringAsFixed(0)} / day';
            _showSmartReminderIfNeeded(
              outCount: outCount,
              delayedCount: delayedCount,
              pendingVerificationCount: pendingVerificationCount,
            );

            final headerDelegate = _LowStockHeaderDelegate(
              totalAttention: totalAttention,
              outCount: outCount,
              pendingCount: pendingCount,
              delayedCount: delayedCount,
              mismatchCount: mismatchCount,
              pendingVerificationCount: pendingVerificationCount,
              estimatedImpactLabel: estimatedImpactLabel,
              active: _active,
              bulkMode: _bulkMode,
              selectedCount: _selectedIds.length,
              onBulkModeChanged: (v) {
                setState(() {
                  _bulkMode = v;
                  if (!v) _selectedIds.clear();
                });
              },
              onActiveChanged: (v) {
                setState(() {
                  _active = v;
                  if (_selectedCategory != null) _selectedCategory = null;
                });
                final cur = ref.read(lowStockOperationsQueryProvider);
                ref.read(lowStockOperationsQueryProvider.notifier).state =
                    cur.copyWith(
                  filter: _backendFilterFor(v),
                  page: 1,
                );
              },
            );

            return RefreshIndicator(
              onRefresh: _refresh,
              child: opsAsync.when(
                loading: () => CustomScrollView(
                  slivers: [
                    const SliverToBoxAdapter(
                      child: Center(child: CircularProgressIndicator()),
                    )
                  ],
                ),
                error: (e, __) => CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: FriendlyLoadError(
                        message: 'Could not load low stock items',
                        onRetry: () => _refresh(),
                      ),
                    )
                  ],
                ),
                data: (ops) {
                  final rawItems = ops['items'] as List? ?? const [];
                  final seenIds = <String>{};
                  final items = <Map<String, dynamic>>[];
                  for (final e in rawItems) {
                    if (e is! Map) continue;
                    final row = Map<String, dynamic>.from(e);
                    final id = row['id']?.toString().trim() ?? '';
                    if (id.isNotEmpty) {
                      if (seenIds.contains(id)) continue;
                      seenIds.add(id);
                    }
                    items.add(row);
                  }

                  final grouped = <String, Map<String, List<Map<String, dynamic>>>>{};
                  for (final item in items) {
                    final cat =
                        item['category_name']?.toString().trim() ?? '';
                    final catKey = cat.isNotEmpty ? cat : 'Unknown';
                    final sub =
                        item['subcategory_name']?.toString().trim() ?? '';
                    final subKey = sub.isNotEmpty ? sub : 'Other';
                    grouped.putIfAbsent(catKey, () => {});
                    grouped[catKey]!.putIfAbsent(subKey, () => []);
                    grouped[catKey]![subKey]!.add(item);
                  }
                  final effectiveSelectedCategory =
                      (_selectedCategory != null && grouped.containsKey(_selectedCategory))
                          ? _selectedCategory
                          : null;

                  return CustomScrollView(
                    slivers: [
                      SliverPersistentHeader(
                        pinned: true,
                        delegate: headerDelegate,
                      ),
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 0),
                        sliver: SliverToBoxAdapter(
                          child: desktop
                              ? const SizedBox.shrink()
                              : Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: TextField(
                                    controller: _searchCtrl,
                                    decoration: InputDecoration(
                                      hintText: 'Search items…',
                                      prefixIcon: const Icon(Icons.search,
                                          size: 20),
                                      filled: true,
                                      fillColor: Colors.white,
                                      isDense: true,
                                      border: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(12),
                                      ),
                                    ),
                                  ),
                                ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 8),
                          child: _LowStockSmartActionCard(
                            staffMode: widget.staffMode,
                            outCount: outCount,
                            pendingCount: pendingCount,
                            delayedCount: delayedCount,
                            pendingVerificationCount: pendingVerificationCount,
                          ),
                        ),
                      ),
                      if (desktop)
                        SliverFillRemaining(
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: gutter),
                            child: LowStockDesktopShell(
                              grouped: grouped,
                              staffMode: widget.staffMode,
                              periodDays: periodDays,
                              selectedCategory: effectiveSelectedCategory,
                              searchController: _searchCtrl,
                              bulkMode: _bulkMode,
                              selectedIds: _selectedIds,
                              selectedItem: _selectedItem,
                              onToggleSelect: (id, selected) {
                                setState(() {
                                  if (selected) {
                                    _selectedIds.add(id);
                                  } else {
                                    _selectedIds.remove(id);
                                  }
                                });
                              },
                              onSelectItem: (item) {
                                setState(() => _selectedItem = item);
                              },
                              onSelectedCategory: (v) {
                                setState(() => _selectedCategory = v);
                              },
                            ),
                          ),
                        )
                      else
                        if (_bulkMode)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 8),
                              child: Wrap(
                                spacing: 8,
                                children: [
                                  FilledButton.tonal(
                                    onPressed: _selectedIds.isEmpty
                                        ? null
                                        : () {
                                            final rows = items
                                                .where((e) => _selectedIds
                                                    .contains(e['id']?.toString()))
                                                .toList();
                                            exportLowStockSelectionCsv(
                                              context,
                                              items: rows,
                                            );
                                          },
                                    child: const Text('Export CSV'),
                                  ),
                                  if (!widget.staffMode)
                                    OutlinedButton(
                                      onPressed: _selectedIds.length != 1
                                          ? null
                                          : () async {
                                              final id = _selectedIds.first;
                                              final session =
                                                  ref.read(sessionProvider);
                                              if (session == null) return;
                                              try {
                                                await ref
                                                    .read(hexaApiProvider)
                                                    .addItemToReorderList(
                                                      businessId: session
                                                          .primaryBusiness.id,
                                                      itemId: id,
                                                    );
                                                ref.invalidate(
                                                    lowStockOperationsSummaryProvider);
                                                ref.invalidate(
                                                    lowStockOperationsPageProvider);
                                                if (!context.mounted) return;
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  const SnackBar(
                                                    content: Text(
                                                        'Added to reorder list'),
                                                  ),
                                                );
                                              } catch (_) {}
                                            },
                                      child: const Text('Reorder list'),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 0),
                            child: LowStockCategoryGroup(
                              grouped: grouped,
                              staffMode: widget.staffMode,
                              periodDays: periodDays,
                              bulkMode: _bulkMode,
                              selectedIds: _selectedIds,
                              onToggleSelect: (id, selected) {
                                setState(() {
                                  if (selected) {
                                    _selectedIds.add(id);
                                  } else {
                                    _selectedIds.remove(id);
                                  }
                                });
                              },
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

class _LowStockSmartActionCard extends StatelessWidget {
  const _LowStockSmartActionCard({
    required this.staffMode,
    required this.outCount,
    required this.pendingCount,
    required this.delayedCount,
    required this.pendingVerificationCount,
  });

  final bool staffMode;
  final int outCount;
  final int pendingCount;
  final int delayedCount;
  final int pendingVerificationCount;

  @override
  Widget build(BuildContext context) {
    final todos = <String>[
      if (outCount > 0) 'Place reorder for out-of-stock items',
      if (pendingVerificationCount > 0) 'Verify physical counts from warehouse',
      if (delayedCount > 0) 'Follow up with delayed suppliers',
      if (outCount == 0 && pendingVerificationCount == 0 && delayedCount == 0)
        'No critical blockers. Monitor pending items.',
    ];
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              staffMode ? 'Staff action focus' : 'Owner action focus',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              'Pending: $pendingCount · Out: $outCount · Verification: $pendingVerificationCount · Delayed: $delayedCount',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 8),
            for (final t in todos)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '• $t',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonal(
                  onPressed: () {
                    if (staffMode) {
                      context.push('/staff/low-stock?filter=verification');
                    } else {
                      context.push('/stock/reorder');
                    }
                  },
                  child: Text(staffMode ? 'Open verification' : 'Open reorder list'),
                ),
                OutlinedButton(
                  onPressed: () {
                    context.push(staffMode ? '/staff/stock' : '/stock');
                  },
                  child: const Text('Open stock table'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LowStockHeaderDelegate extends SliverPersistentHeaderDelegate {
  _LowStockHeaderDelegate({
    required this.totalAttention,
    required this.outCount,
    required this.pendingCount,
    required this.delayedCount,
    required this.mismatchCount,
    required this.pendingVerificationCount,
    required this.estimatedImpactLabel,
    required this.active,
    required this.onActiveChanged,
    required this.bulkMode,
    required this.selectedCount,
    required this.onBulkModeChanged,
  });

  final int totalAttention;
  final int outCount;
  final int pendingCount;
  final int delayedCount;
  final int mismatchCount;
  final int pendingVerificationCount;
  final String estimatedImpactLabel;
  final LowStockOpsFilter active;
  final ValueChanged<LowStockOpsFilter> onActiveChanged;
  final bool bulkMode;
  final int selectedCount;
  final ValueChanged<bool> onBulkModeChanged;

  @override
  double get minExtent => 164;

  @override
  double get maxExtent => 164;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Material(
      color: HexaColors.brandBackground,
      elevation: overlapsContent ? 1 : 0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LowStockOpsHeader(
            totalAttention: totalAttention,
            outCount: outCount,
            pendingCount: pendingCount,
            delayedCount: delayedCount,
            mismatchCount: mismatchCount,
            pendingVerificationCount: pendingVerificationCount,
            estimatedImpactLabel: estimatedImpactLabel,
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: LowStockFilterBar(
              active: active,
              onActiveChanged: onActiveChanged,
              bulkMode: bulkMode,
              selectedCount: selectedCount,
              onBulkModeChanged: onBulkModeChanged,
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _LowStockHeaderDelegate oldDelegate) {
    return oldDelegate.totalAttention != totalAttention ||
        oldDelegate.outCount != outCount ||
        oldDelegate.pendingCount != pendingCount ||
        oldDelegate.delayedCount != delayedCount ||
        oldDelegate.mismatchCount != mismatchCount ||
        oldDelegate.pendingVerificationCount != pendingVerificationCount ||
        oldDelegate.estimatedImpactLabel != estimatedImpactLabel ||
        oldDelegate.active != active ||
        oldDelegate.bulkMode != bulkMode ||
        oldDelegate.selectedCount != selectedCount;
  }
}

