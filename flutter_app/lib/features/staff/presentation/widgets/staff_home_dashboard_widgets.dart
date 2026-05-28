import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';

import '../../../../core/design_system/hexa_ds_tokens.dart';
import '../../../../core/design_system/hexa_operational_tokens.dart';
import '../../../../core/providers/search_focus_provider.dart';
import '../../../../core/providers/staff_home_providers.dart';
import '../../../../core/theme/hexa_colors.dart';

/// Section label for staff home blocks.
class StaffHomeSectionHeader extends StatelessWidget {
  const StaffHomeSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: HexaDsType.heading(15)),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: HexaDsType.body(13, color: HexaDsColors.textMuted),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Compact shift metrics row (~72px) with shimmer while loading.
class StaffHomeShiftSnapshotStrip extends ConsumerWidget {
  const StaffHomeShiftSnapshotStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(staffTodaySummaryProvider);
    final pendingDel = ref.watch(staffPendingDeliveryCountProvider);

    return summaryAsync.when(
      loading: () => const StaffHomeShiftSnapshotSkeleton(),
      error: (_, __) => StaffHomeShiftSnapshotRow(
        scans: '–',
        stock: '–',
        purchases: '–',
        deliveries: pendingDel > 0 ? '$pendingDel' : '–',
      ),
      data: (s) => StaffHomeShiftSnapshotRow(
        scans: '${s.scanned}',
        stock: '${s.stockUpdates}',
        purchases: '${s.purchases}',
        deliveries: '$pendingDel',
      ),
    );
  }
}

class StaffHomeShiftSnapshotRow extends StatelessWidget {
  const StaffHomeShiftSnapshotRow({
    super.key,
    required this.scans,
    required this.stock,
    required this.purchases,
    required this.deliveries,
  });

  final String scans;
  final String stock;
  final String purchases;
  final String deliveries;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: HexaColors.brandBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        child: IntrinsicHeight(
          child: Row(
            children: [
              _ShiftTile(value: scans, label: 'Scans', icon: Icons.qr_code_scanner_outlined),
              _vDivider(),
              _ShiftTile(value: stock, label: 'Stock', icon: Icons.inventory_2_outlined),
              _vDivider(),
              _ShiftTile(value: purchases, label: 'Purchases', icon: Icons.receipt_long_outlined),
              _vDivider(),
              _ShiftTile(
                value: deliveries,
                label: 'Deliveries',
                icon: Icons.local_shipping_outlined,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _vDivider() => Container(
        width: 1,
        margin: const EdgeInsets.symmetric(vertical: 4),
        color: HexaColors.brandBorder,
      );
}

class _ShiftTile extends StatelessWidget {
  const _ShiftTile({
    required this.value,
    required this.label,
    required this.icon,
  });

  final String value;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 15, color: HexaColors.brandPrimary),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, height: 1),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: HexaDsType.label(10, color: HexaDsColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class StaffHomeShiftSnapshotSkeleton extends StatelessWidget {
  const StaffHomeShiftSnapshotSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: const Color(0xFFE8ECEF),
      highlightColor: const Color(0xFFF8FAFC),
      child: const StaffHomeShiftSnapshotRow(
        scans: '–',
        stock: '–',
        purchases: '–',
        deliveries: '–',
      ),
    );
  }
}

/// Bordered card with today's counts — structured, not floating icons.
class StaffHomeTodaySummaryCard extends StatelessWidget {
  const StaffHomeTodaySummaryCard({
    super.key,
    required this.summary,
  });

  final StaffTodayActivitySummary summary;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: HexaColors.brandBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'Your shift today',
                  style: HexaDsType.heading(15),
                ),
                const Spacer(),
                Text(
                  '${summary.total} actions',
                  style: HexaDsType.label(11, color: HexaDsColors.textMuted)
                      .copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 10),
            IntrinsicHeight(
              child: Row(
                children: [
                  _MetricCell(
                    value: '${summary.scanned}',
                    label: 'Scanned',
                    icon: Icons.qr_code_scanner_outlined,
                  ),
                  _divider(),
                  _MetricCell(
                    value: '${summary.itemsChecked}',
                    label: 'Checked',
                    icon: Icons.fact_check_outlined,
                  ),
                  _divider(),
                  _MetricCell(
                    value: '${summary.stockUpdates}',
                    label: 'Stock',
                    icon: Icons.inventory_2_outlined,
                  ),
                  _divider(),
                  _MetricCell(
                    value: '${summary.purchases}',
                    label: 'Purchases',
                    icon: Icons.receipt_long_outlined,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        margin: const EdgeInsets.symmetric(vertical: 4),
        color: HexaColors.brandBorder,
      );
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({
    required this.value,
    required this.label,
    required this.icon,
  });

  final String value;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 16, color: HexaColors.brandPrimary),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: HexaDsType.label(10, color: HexaDsColors.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Full-width actionable row for deliveries, barcodes, low stock.
class StaffHomeAttentionTile extends StatelessWidget {
  const StaffHomeAttentionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.count,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final int count;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: accent.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: accent.withValues(alpha: 0.35)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: accent, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: HexaDsType.body(12, color: HexaDsColors.textMuted),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded, color: accent.withValues(alpha: 0.8)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// List-style tool row: icon, title, subtitle, optional badge, chevron.
class StaffHomeActionRow extends StatelessWidget {
  const StaffHomeActionRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge = 0,
    this.isFirst = false,
    this.isLast = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final int badge;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.vertical(
      top: isFirst ? const Radius.circular(12) : Radius.zero,
      bottom: isLast ? const Radius.circular(12) : Radius.zero,
    );

    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: const BorderSide(color: HexaColors.brandBorder),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Container(
          constraints: const BoxConstraints(minHeight: HexaOp.listRowMin),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: isLast
                  ? BorderSide.none
                  : const BorderSide(color: HexaColors.brandBorder, width: 0.5),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: HexaColors.brandPrimary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 22, color: HexaColors.brandPrimary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: HexaDsType.body(12, color: HexaDsColors.textMuted),
                    ),
                  ],
                ),
              ),
              if (badge > 0) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: HexaColors.loss,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    badge > 99 ? '99+' : '$badge',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Groups [StaffHomeActionRow] into one bordered list.
class StaffHomeActionGroup extends StatelessWidget {
  const StaffHomeActionGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

class _ToolSpec {
  const _ToolSpec(this.label, this.icon, this.color, this.onTap);
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
}

/// Compact 3×2 tools grid (~96px) for staff home.
class StaffHomeToolsGrid extends ConsumerWidget {
  const StaffHomeToolsGrid({
    super.key,
    required this.lowCount,
    required this.focus,
  });

  final int lowCount;
  final StaffHomeFocus focus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tools = <_ToolSpec>[
      _ToolSpec(
        'Search',
        Icons.search_rounded,
        HexaColors.brandPrimary,
        () {
          ref.read(searchFocusRequestedProvider.notifier).state = true;
          context.go('/staff/search');
        },
      ),
      _ToolSpec(
        'Stock',
        Icons.inventory_2_outlined,
        const Color(0xFF1565C0),
        () => context.go('/staff/stock'),
      ),
      if (staffHomeShowsBarcodeTools(focus))
        _ToolSpec(
          'Labels',
          Icons.print_outlined,
          const Color(0xFF455A64),
          () => context.push('/barcode/bulk-print'),
        ),
      if (staffHomeShowsPurchaseTools(focus))
        _ToolSpec(
          'History',
          Icons.receipt_long_outlined,
          const Color(0xFF0D9488),
          () => context.go('/staff/purchase-history'),
        ),
      _ToolSpec(
        'Low stock',
        Icons.warning_amber_rounded,
        HexaColors.warning,
        () => context.push('/staff/low-stock'),
      ),
      if (staffHomeShowsPurchaseTools(focus))
        _ToolSpec(
          'Cash buy',
          Icons.add_shopping_cart_rounded,
          HexaColors.profit,
          () => context.push('/staff/quick-purchase'),
        ),
    ];

    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.35,
      children: [
        for (final t in tools)
          Material(
            color: t.color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: t.onTap,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(t.icon, color: t.color, size: 22),
                    const SizedBox(height: 4),
                    Text(
                      t.label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: t.color,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class StaffHomeRecentScansStrip extends ConsumerWidget {
  const StaffHomeRecentScansStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scansAsync = ref.watch(staffRecentScansProvider);
    return scansAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (scans) {
        if (scans.isEmpty) return const SizedBox.shrink();
        final recent = scans.take(5).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const StaffHomeSectionHeader(
              title: 'Recent scans',
              subtitle: 'Quick jump to recently scanned items',
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final s in recent)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        avatar: const Icon(Icons.qr_code_scanner_rounded, size: 16),
                        label: Text(
                          (s.name.isNotEmpty ? s.name : s.code),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        onPressed: () {
                          if (s.id.isNotEmpty) {
                            context.push('/catalog/item/${s.id}?source=scan');
                          } else {
                            context.push('/barcode/scan-history');
                          }
                        },
                      ),
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

/// Vertical recent activity list (scans + log actions).
class StaffHomeRecentActivitySection extends ConsumerWidget {
  const StaffHomeRecentActivitySection({super.key});

  static String _timeAgo(DateTime at) {
    final d = DateTime.now().difference(at);
    if (d.inSeconds < 60) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return DateFormat.MMMd().format(at);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(staffRecentActivityProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StaffHomeSectionHeader(
          title: 'Recent activity',
          subtitle: 'Scans, stock updates, and purchases today',
        ),
        async.when(
          loading: () => const SizedBox(
            height: 120,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (_, __) => Text(
            'Could not load recent activity.',
            style: HexaDsType.body(13, color: HexaDsColors.textMuted),
          ),
          data: (items) {
            if (items.isEmpty) {
              return Text(
                'No activity yet today — tap Scan above.',
                style: HexaDsType.body(14, color: HexaDsColors.textMuted),
              );
            }
            return Column(
              children: [
                for (final item in items)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor:
                          HexaColors.brandPrimary.withValues(alpha: 0.12),
                      child: Icon(
                        item.isScan
                            ? Icons.qr_code_scanner_outlined
                            : Icons.history_rounded,
                        size: 16,
                        color: HexaColors.brandPrimary,
                      ),
                    ),
                    title: Text(
                      item.label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    subtitle: item.subtitle != null
                        ? Text(
                            item.subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: HexaDsType.body(12, color: HexaDsColors.textMuted),
                          )
                        : null,
                    trailing: Text(
                      _timeAgo(item.when),
                      style: HexaDsType.label(11, color: HexaDsColors.textMuted),
                    ),
                    onTap: item.itemId != null && item.itemId!.isNotEmpty
                        ? () => context.push(
                              '/catalog/item/${item.itemId}?source=scan',
                            )
                        : null,
                  ),
              ],
            );
          },
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => context.push('/staff/activity'),
            child: const Text('Full activity log'),
          ),
        ),
      ],
    );
  }
}
