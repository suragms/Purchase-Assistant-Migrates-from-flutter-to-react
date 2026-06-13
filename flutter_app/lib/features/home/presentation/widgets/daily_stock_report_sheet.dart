import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/design_system/hexa_responsive.dart';
import '../../../../core/providers/home_dashboard_provider.dart'
    show homeStockMovementSectionVisibleProvider;
import '../../../../core/providers/home_owner_dashboard_providers.dart';
import '../../../../core/theme/hexa_colors.dart';
import '../../../stock/presentation/widgets/stock_today_feed.dart';

/// One-tap daily summary for owner (WhatsApp-friendly text).
class DailyStockReportSheet extends ConsumerWidget {
  const DailyStockReportSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showHexaBottomSheet<void>(
      context: context,
      compact: false,
      padding: EdgeInsets.zero,
      child: SizedBox(
        height: HexaResponsive.adaptiveSheetMaxHeight(context),
        child: const DailyStockReportSheet(),
      ),
    );
  }

  String _buildWhatsAppText({
    required String dateLabel,
    required List<Map<String, dynamic>> purchases,
    required List<Map<String, dynamic>> audits,
    required int lowN,
    required int critN,
    required List<Map<String, dynamic>> variances,
  }) {
    final buf = StringBuffer()
      ..writeln('*HARISREE STOCK REPORT — $dateLabel*')
      ..writeln()
      ..writeln('📦 TODAY\'S PURCHASES: ${purchases.length} bill(s)');
    for (final p in purchases.take(5)) {
      final amt = p['total_amount'];
      buf.writeln('• ${p['human_id'] ?? p['id']} — ₹$amt');
    }
    buf
      ..writeln()
      ..writeln('📊 STOCK UPDATES: ${audits.length} change(s)');
    buf
      ..writeln()
      ..writeln('⚠ LOW STOCK: $lowN low · $critN critical');
    if (variances.isNotEmpty) {
      buf.writeln();
      buf.writeln('❗ VARIANCES:');
      for (final v in variances.take(5)) {
        buf.writeln(
          '• ${v['item_name']}: expected ${v['expected_qty']} · found ${v['found_qty']}',
        );
      }
    }
    buf.writeln();
    buf.writeln('_Harisree Agency · HexaStack_');
    return buf.toString();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.read(homeStockMovementSectionVisibleProvider.notifier).state = true;
    final now = DateTime.now();
    final dateLabel = DateFormat('d MMM yyyy').format(now);
    final purchases = ref.watch(homeRecentPurchasesCompactProvider);
    final audits = ref.watch(stockAuditDayProvider(
      DateTime(now.year, now.month, now.day),
    ));
    final lowN = ref.watch(stockLowCountProvider).valueOrNull ?? 0;
    final critN = ref.watch(stockCriticalCountProvider).valueOrNull ?? 0;
    final variances = ref.watch(stockVariancesTodayProvider);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Daily report — $dateLabel',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              purchases.when(
                loading: () => const LinearProgressIndicator(minHeight: 2),
                error: (_, __) => const Text('Purchases unavailable'),
                data: (rows) => _Section(
                  title: "Today's purchases",
                  child: rows.isEmpty
                      ? const Text('No purchases today')
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final p in rows)
                              Text(
                                '${p['human_id'] ?? 'Bill'} · ₹${p['total_amount'] ?? '—'}',
                                style: const TextStyle(fontSize: 13),
                              ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 16),
              audits.when(
                loading: () => const LinearProgressIndicator(minHeight: 2),
                error: (_, __) => const Text('Stock updates unavailable'),
                data: (rows) => _Section(
                  title: 'Stock movement',
                  child: StockTodayFeed(
                    rows: rows,
                    maxRows: 8,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _Section(
                title: 'Low stock snapshot',
                child: Text(
                  '$lowN low · $critN critical items need attention',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              variances.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (v) {
                  if (v.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: _Section(
                      title: 'Variances',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final row in v.take(5))
                            Text(
                              '${row['item_name']}: expected ${row['expected_qty']} · found ${row['found_qty']}',
                              style: const TextStyle(fontSize: 13),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 12 + bottomInset),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final p = purchases.valueOrNull ?? [];
                      final a = audits.valueOrNull ?? [];
                      final v = variances.valueOrNull ?? [];
                      final text = _buildWhatsAppText(
                        dateLabel: dateLabel,
                        purchases: p,
                        audits: a,
                        lowN: lowN,
                        critN: critN,
                        variances: v,
                      );
                      await Share.share(text);
                    },
                    icon: const Icon(Icons.chat_rounded),
                    label: const Text('WhatsApp'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: HexaColors.brandPrimary,
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}
