import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/design_system/hexa_operational_tokens.dart';
import '../../../core/providers/business_write_event.dart';
import '../../../core/providers/business_write_revision.dart';
import '../../../core/providers/deferred_invalidation.dart';
import '../../../core/providers/home_dashboard_provider.dart';
import '../../../core/providers/home_owner_dashboard_providers.dart';
import '../../../core/router/navigation_ext.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../../../shared/widgets/hexa_empty_state.dart';
import 'widgets/home_period_filter_row.dart';
import 'widgets/home_recent_changes_section.dart' show HomeSectionSkeleton;
import 'widgets/home_warehouse_activity_row.dart';

String _periodTitle(HomePeriod period) {
  return switch (period) {
    HomePeriod.today => 'Recent activity (today)',
    HomePeriod.week => 'Recent activity (week)',
    HomePeriod.month => 'Recent activity (month)',
    HomePeriod.year => 'Recent activity (year)',
    HomePeriod.allTime => 'Recent activity (all time)',
    HomePeriod.custom => 'Recent activity (custom range)',
  };
}

/// Full warehouse activity — opened from Home → View all / Show more.
class HomeWarehouseActivityPage extends ConsumerStatefulWidget {
  const HomeWarehouseActivityPage({super.key});

  @override
  ConsumerState<HomeWarehouseActivityPage> createState() =>
      _HomeWarehouseActivityPageState();
}

class _HomeWarehouseActivityPageState
    extends ConsumerState<HomeWarehouseActivityPage> {
  List<HomeActivityItem>? _cachedItems;

  Future<void> _reload() async {
    ref.invalidate(homeWarehouseActivityFullProvider);
    ref.invalidate(homeRecentActivityFeedProvider);
    await ref.read(homeWarehouseActivityFullProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<BusinessWriteEvent>(businessWriteEventProvider, (prev, next) {
      if (next.revision <= (prev?.revision ?? -1)) return;
      deferInvalidate(ref, homeWarehouseActivityFullProvider);
      deferInvalidate(ref, homeRecentActivityFeedProvider);
    });
    ref.listen<int>(businessDataWriteRevisionProvider, (prev, next) {
      if (prev == null || next <= prev) return;
      deferInvalidate(ref, homeWarehouseActivityFullProvider);
      deferInvalidate(ref, homeRecentActivityFeedProvider);
    });

    final period = ref.watch(homePeriodProvider);
    final feedAsync = ref.watch(homeWarehouseActivityFullProvider);
    final title = _periodTitle(period);

    feedAsync.whenData((items) {
      if (_cachedItems != items) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() => _cachedItems = items);
        });
      }
    });

    final displayItems = feedAsync.valueOrNull ?? _cachedItems;
    final showSkeleton = feedAsync.isLoading && displayItems == null;
    final showRefreshBanner =
        feedAsync.isLoading && displayItems != null && displayItems.isNotEmpty;

    return Scaffold(
      backgroundColor: HexaColors.brandBackground,
      appBar: AppBar(
        title: Text(
          'Warehouse activity',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.popOrGo('/home'),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const HomePeriodFilterRow(),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 2, 16, 0),
                      child: Text(
                        'Applies to purchase center and warehouse activity',
                        style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                      ),
                    ),
                    if (showRefreshBanner)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: LinearProgressIndicator(minHeight: 2),
                      ),
                  ],
                ),
              ),
            ),
            if (showSkeleton)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: HomeSectionSkeleton(rows: 8),
                ),
              )
            else if (feedAsync.hasError && displayItems == null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: FriendlyLoadError(
                  message: 'Could not load activity',
                  onRetry: _reload,
                ),
              )
            else if (displayItems == null || displayItems.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: HexaEmptyState(
                  icon: Icons.history_rounded,
                  title: 'No activity in this period',
                  subtitle:
                      'Deliveries, purchases, and stock updates appear here.',
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                sliver: SliverToBoxAdapter(
                  child: Card(
                    margin: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                title,
                                style: HexaOp.cardTitle(context),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${displayItems.length} events in period',
                                style: HexaDsType.label(
                                  11,
                                  color: HexaDsColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        _ActivityTableHeader(),
                        for (var i = 0; i < displayItems.length; i++) ...[
                          WarehouseActivityDetailRow(item: displayItems[i]),
                          if (i < displayItems.length - 1)
                            const Divider(height: 1),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ActivityTableHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 34,
            child: Text(
              'Bill · Entered by',
              style: HexaDsType.label(10, color: HexaDsColors.textMuted),
            ),
          ),
          Expanded(
            flex: 38,
            child: Text(
              'Qty · Bags · Tins',
              textAlign: TextAlign.center,
              style: HexaDsType.label(10, color: HexaDsColors.textMuted),
            ),
          ),
          Expanded(
            flex: 28,
            child: Text(
              'Verified by',
              textAlign: TextAlign.end,
              style: HexaDsType.label(10, color: HexaDsColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}
