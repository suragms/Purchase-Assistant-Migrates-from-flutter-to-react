import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/features/reports/presentation/reports_overview_chart_section.dart';

void main() {
  test('reportsOverviewChartSize does not throw when cap is below 120', () {
    expect(
      () => reportsOverviewChartSize(280, 390),
      returnsNormally,
    );
    expect(reportsOverviewChartSize(280, 390), lessThanOrEqualTo(120));
    expect(reportsOverviewChartSize(280, 390), greaterThan(0));
  });

  test('reportsOverviewChartSize respects large viewport', () {
    final size = reportsOverviewChartSize(800, 390);
    expect(size, greaterThanOrEqualTo(120));
    expect(size, lessThanOrEqualTo(200));
  });
}
