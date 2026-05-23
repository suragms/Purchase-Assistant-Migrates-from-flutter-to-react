import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/app_period_provider.dart'
    show syncReportsRangeFromHomePeriod;
import '../../../../core/providers/home_dashboard_provider.dart';
import '../../../../shared/widgets/operational_ui.dart';

/// Global period chips (synced with Reports via [homePeriodProvider]).
class HomePeriodFilterRow extends ConsumerStatefulWidget {
  const HomePeriodFilterRow({super.key});

  @override
  ConsumerState<HomePeriodFilterRow> createState() =>
      _HomePeriodFilterRowState();
}

class _HomePeriodFilterRowState extends ConsumerState<HomePeriodFilterRow> {
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _setPeriod(HomePeriod p) {
    ref.read(homePeriodProvider.notifier).state = p;
    syncReportsRangeFromHomePeriod(ref, p);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      bustHomeDashboardVolatileCaches();
      ref.invalidate(homeDashboardDataProvider);
    });
  }

  Future<void> _pickCustom() async {
    final now = DateTime.now();
    final existing = ref.read(homeCustomDateRangeProvider);
    final initial = existing != null
        ? DateTimeRange(start: existing.start, end: existing.endInclusive)
        : DateTimeRange(
            start: now.subtract(const Duration(days: 29)),
            end: now,
          );
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: initial,
    );
    if (picked == null || !mounted) return;
    ref.read(homeCustomDateRangeProvider.notifier).state = (
      start: picked.start,
      endInclusive: picked.end,
    );
    _setPeriod(HomePeriod.custom);
  }

  @override
  Widget build(BuildContext context) {
    final period = ref.watch(homePeriodProvider);
    final labels = HomePeriod.values.map((p) => p.label).toList();
    final selected = period.label;

    return OperationalPillRow(
      labels: labels,
      selected: selected,
      height: 32,
      onSelected: (label) {
        final match = HomePeriod.values.where((p) => p.label == label);
        if (match.isEmpty) return;
        final p = match.first;
        if (p == HomePeriod.custom) {
          _pickCustom();
        } else {
          _setPeriod(p);
        }
      },
    );
  }
}
