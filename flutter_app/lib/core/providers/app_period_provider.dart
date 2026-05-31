import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'analytics_kpi_provider.dart' show analyticsDateRangeProvider;
import 'home_dashboard_provider.dart';

String _apiDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Calendar range for [period] (custom uses [analyticsDateRangeProvider]).
({DateTime from, DateTime to}) appPeriodDateRange(Ref ref, AppPeriod period) {
  if (period == AppPeriod.custom) {
    final r = ref.read(analyticsDateRangeProvider);
    return (from: r.from, to: r.to);
  }
  final now = DateTime.now();
  return switch (period) {
    AppPeriod.today => (
        from: DateTime(now.year, now.month, now.day),
        to: now,
      ),
    AppPeriod.week => (from: now.subtract(const Duration(days: 7)), to: now),
    AppPeriod.month => (from: DateTime(now.year, now.month, 1), to: now),
    AppPeriod.quarter => (
        from: DateTime(now.year, now.month - ((now.month - 1) % 3), 1),
        to: now,
      ),
    AppPeriod.year => (from: DateTime(now.year, 1, 1), to: now),
    AppPeriod.allTime => (from: DateTime(1970, 1, 1), to: DateTime(2099, 12, 31)),
    AppPeriod.custom => (from: now, to: now),
  };
}

String appPeriodApiDateFrom(Ref ref, AppPeriod period) =>
    _apiDate(appPeriodDateRange(ref, period).from);

String appPeriodApiDateTo(Ref ref, AppPeriod period) =>
    _apiDate(appPeriodDateRange(ref, period).to);

enum AppPeriod { today, week, month, quarter, year, allTime, custom }

final appSelectedPeriodProvider = StateProvider<AppPeriod>(
  (ref) => AppPeriod.month,
  name: 'appSelectedPeriod',
);

extension AppPeriodX on AppPeriod {
  String get label => switch (this) {
        AppPeriod.today => 'Today',
        AppPeriod.week => 'Week',
        AppPeriod.month => 'Month',
        AppPeriod.quarter => 'Quarter',
        AppPeriod.year => 'Year',
        AppPeriod.allTime => 'All time',
        AppPeriod.custom => 'Custom',
      };
}

AppPeriod appPeriodFromHomePeriod(HomePeriod period) => switch (period) {
      HomePeriod.today => AppPeriod.today,
      HomePeriod.week => AppPeriod.week,
      HomePeriod.month => AppPeriod.month,
      HomePeriod.year => AppPeriod.year,
      HomePeriod.allTime => AppPeriod.allTime,
      HomePeriod.custom => AppPeriod.custom,
    };

/// Keeps Reports date range aligned when home period changes (BLOGIC-08 / FEAT-004).
void syncReportsRangeFromHomePeriod(WidgetRef ref, HomePeriod period) {
  ref.read(appSelectedPeriodProvider.notifier).state =
      appPeriodFromHomePeriod(period);
  final custom = ref.read(homeCustomDateRangeProvider);
  final range = homePeriodRange(period, custom: custom);
  final from = DateTime(range.start.year, range.start.month, range.start.day);
  final rawTo = range.end.subtract(const Duration(days: 1));
  final to = DateTime(rawTo.year, rawTo.month, rawTo.day);
  ref.read(analyticsDateRangeProvider.notifier).state = (from: from, to: to);
}

/// Call when user changes period on Home so Reports opens on the same window.
final homePeriodSyncListenerProvider = Provider<void>((ref) {
  ref.listen<HomePeriod>(homePeriodProvider, (prev, next) {
    if (prev == next) return;
    ref.read(appSelectedPeriodProvider.notifier).state =
        appPeriodFromHomePeriod(next);
    final custom = ref.read(homeCustomDateRangeProvider);
    final range = homePeriodRange(next, custom: custom);
    final from = DateTime(range.start.year, range.start.month, range.start.day);
    final rawTo = range.end.subtract(const Duration(days: 1));
    final to = DateTime(rawTo.year, rawTo.month, rawTo.day);
    ref.read(analyticsDateRangeProvider.notifier).state = (from: from, to: to);
  });
});
