import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/design_system/hexa_ds_tokens.dart';
import '../../../../core/providers/home_dashboard_provider.dart';
import '../../../../core/providers/home_owner_dashboard_providers.dart';
import '../../../../core/theme/hexa_colors.dart';
import '../../../../shared/widgets/operational_ui.dart';

String _inr(num n) =>
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
        .format(n);

String _timeAgo(DateTime at) {
  final diff = DateTime.now().difference(at);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return DateFormat('d MMM').format(at);
}

/// Owner quick stats: today · month · items · stock alerts.
class HomeQuickStatsRow extends StatelessWidget {
  const HomeQuickStatsRow({
    super.key,
    required this.todayAsync,
    required this.monthAsync,
    required this.lowN,
    required this.critN,
  });

  final AsyncValue<HomeDashboardData> todayAsync;
  final AsyncValue<HomeDashboardData> monthAsync;
  final AsyncValue<int> lowN;
  final AsyncValue<int> critN;

  @override
  Widget build(BuildContext context) {
    final today = todayAsync.valueOrNull;
    final month = monthAsync.valueOrNull;
    final low = lowN.valueOrNull ?? 0;
    final crit = critN.valueOrNull ?? 0;
    final alerts = low + crit;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OperationalStatChip(
          label: 'Today spend',
          value: todayAsync.isLoading
              ? '…'
              : _inr(today?.totalPurchase ?? 0),
          onTap: () => context.go('/reports'),
        ),
        OperationalStatChip(
          label: 'This month',
          value: monthAsync.isLoading
              ? '…'
              : _inr(month?.totalPurchase ?? 0),
          onTap: () => context.go('/reports'),
        ),
        OperationalStatChip(
          label: 'Items bought',
          value: monthAsync.isLoading
              ? '…'
              : '${month?.purchaseCount ?? today?.purchaseCount ?? 0}',
        ),
        OperationalStatChip(
          label: 'Stock alerts',
          value: lowN.isLoading && critN.isLoading ? '…' : '$alerts',
          tint: alerts > 0 ? const Color(0xFFE65100) : null,
          onTap: () => context.go('/stock'),
        ),
      ],
    );
  }
}

/// Staff signed in within the last few minutes (server active-sessions).
class HomeStaffActivitySection extends ConsumerWidget {
  const HomeStaffActivitySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staffAsync = ref.watch(activeStaffSessionsProvider);

    return staffAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (rows) {
        if (rows.isEmpty) {
          return OperationalSection(
            title: 'Staff activity',
            dense: true,
            child: Text(
              'No staff active right now',
              style: HexaDsType.bodySm(context),
            ),
          );
        }
        return OperationalSection(
          title: 'Staff activity',
          dense: true,
          trailing: Text(
            '${rows.length} active',
            style: HexaDsType.labelCaps(context).copyWith(
              color: const Color(0xFF2E7D32),
              fontWeight: FontWeight.w800,
            ),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final r in rows)
                _StaffChip(
                  name: r['name']?.toString() ??
                      r['email']?.toString() ??
                      'Staff',
                  role: r['role']?.toString() ?? '',
                  lastActive: _parseAt(r['last_active_at']),
                ),
            ],
          ),
        );
      },
    );
  }

  static DateTime? _parseAt(dynamic raw) {
    if (raw is String && raw.isNotEmpty) {
      return DateTime.tryParse(raw)?.toLocal();
    }
    return null;
  }
}

class _StaffChip extends StatelessWidget {
  const _StaffChip({
    required this.name,
    required this.role,
    this.lastActive,
  });

  final String name;
  final String role;
  final DateTime? lastActive;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    final ago = lastActive != null ? _timeAgo(lastActive!) : '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF2E7D32).withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: HexaColors.brandPrimary.withValues(alpha: 0.15),
            child: Text(
              initial,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: HexaColors.brandPrimary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                style: HexaDsType.bodySm(context).copyWith(
                  fontWeight: FontWeight.w800,
                  color: HexaDsColors.textPrimary,
                ),
              ),
              if (ago.isNotEmpty)
                Text(
                  role.isNotEmpty ? '$role · $ago' : ago,
                  style: HexaDsType.labelCaps(context),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Last 5 purchases + stock changes, newest first.
class HomeRecentActivitySection extends ConsumerWidget {
  const HomeRecentActivitySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedAsync = ref.watch(homeRecentActivityFeedProvider);

    return OperationalSection(
      title: 'Recent changes',
      dense: true,
      trailing: TextButton(
        onPressed: () => context.go('/purchase'),
        child: const Text('See all', style: TextStyle(fontSize: 12)),
      ),
      child: feedAsync.when(
        loading: () => const Center(
          child: Padding(
            padding: EdgeInsets.all(12),
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        error: (_, __) => const Text('Could not load recent activity'),
        data: (items) {
          if (items.isEmpty) {
            return Text(
              'No purchases or stock updates yet',
              style: HexaDsType.bodySm(context),
            );
          }
          return Column(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                _ActivityTile(item: items[i]),
                if (i < items.length - 1)
                  const Divider(height: 1, indent: 12, endIndent: 12),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.item});

  final HomeActivityItem item;

  @override
  Widget build(BuildContext context) {
    final isPurchase = item.kind == 'purchase';
    final icon = isPurchase
        ? Icons.shopping_cart_outlined
        : Icons.inventory_2_outlined;
    final color =
        isPurchase ? HexaColors.brandPrimary : const Color(0xFF0D9488);

    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: color.withValues(alpha: 0.12),
        child: Icon(icon, size: 18, color: color),
      ),
      title: Text(
        item.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: HexaDsType.listTitle(context).copyWith(
          fontWeight: FontWeight.w800,
          fontSize: 13,
        ),
      ),
      subtitle: Text(
        '${item.subtitle.isNotEmpty ? '${item.subtitle} · ' : ''}${_timeAgo(item.at)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: HexaDsType.bodySm(context),
      ),
      trailing: item.amountInr != null && item.amountInr! > 0
          ? Text(
              _inr(item.amountInr!),
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 12,
                color: HexaColors.brandPrimary,
              ),
            )
          : null,
      onTap: () {
        final id = item.routeId;
        if (id == null || id.isEmpty) return;
        if (isPurchase) {
          context.push('/purchase/detail/$id');
        } else {
          context.push('/catalog/item/$id');
        }
      },
    );
  }
}
