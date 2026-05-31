import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ReportsUnitFilter { all, bag, box, tin, kg }

enum ReportsSort { latest, highestQty, highestValue, az }

enum ReportsStockStatusFilter {
  all,
  fast,
  slow,
  dead,
  zero,
  over,
  under,
}

class ReportsFilterState {
  const ReportsFilterState({
    this.searchQuery = '',
    this.units = const {ReportsUnitFilter.all},
    this.sort = ReportsSort.highestValue,
    this.stockStatus = ReportsStockStatusFilter.all,
    this.categoryIds = const {},
    this.subcategoryIds = const {},
    this.supplierIds = const {},
    this.brokerIds = const {},
    this.minPurchaseValue,
    this.maxPurchaseValue,
    this.activeViewId,
  });

  final String searchQuery;
  final Set<ReportsUnitFilter> units;
  final ReportsSort sort;
  final ReportsStockStatusFilter stockStatus;
  final Set<String> categoryIds;
  final Set<String> subcategoryIds;
  final Set<String> supplierIds;
  final Set<String> brokerIds;
  final double? minPurchaseValue;
  final double? maxPurchaseValue;
  final String? activeViewId;

  int get activeCount {
    var n = 0;
    if (searchQuery.trim().isNotEmpty) n++;
    if (!units.contains(ReportsUnitFilter.all) && units.isNotEmpty) n++;
    if (sort != ReportsSort.highestValue) n++;
    if (stockStatus != ReportsStockStatusFilter.all) n++;
    if (categoryIds.isNotEmpty) n++;
    if (subcategoryIds.isNotEmpty) n++;
    if (supplierIds.isNotEmpty) n++;
    if (brokerIds.isNotEmpty) n++;
    if (minPurchaseValue != null || maxPurchaseValue != null) n++;
    return n;
  }

  ReportsFilterState copyWith({
    String? searchQuery,
    Set<ReportsUnitFilter>? units,
    ReportsSort? sort,
    ReportsStockStatusFilter? stockStatus,
    Set<String>? categoryIds,
    Set<String>? subcategoryIds,
    Set<String>? supplierIds,
    Set<String>? brokerIds,
    double? minPurchaseValue,
    double? maxPurchaseValue,
    String? activeViewId,
    bool clearMin = false,
    bool clearMax = false,
  }) {
    return ReportsFilterState(
      searchQuery: searchQuery ?? this.searchQuery,
      units: units ?? this.units,
      sort: sort ?? this.sort,
      stockStatus: stockStatus ?? this.stockStatus,
      categoryIds: categoryIds ?? this.categoryIds,
      subcategoryIds: subcategoryIds ?? this.subcategoryIds,
      supplierIds: supplierIds ?? this.supplierIds,
      brokerIds: brokerIds ?? this.brokerIds,
      minPurchaseValue:
          clearMin ? null : (minPurchaseValue ?? this.minPurchaseValue),
      maxPurchaseValue:
          clearMax ? null : (maxPurchaseValue ?? this.maxPurchaseValue),
      activeViewId: activeViewId ?? this.activeViewId,
    );
  }

  static const empty = ReportsFilterState();
}

class ReportsFilterNotifier extends Notifier<ReportsFilterState> {
  @override
  ReportsFilterState build() => ReportsFilterState.empty;

  void apply(ReportsFilterState next) => state = next;

  void reset() => state = ReportsFilterState.empty;

  void setSearch(String q) => state = state.copyWith(searchQuery: q);
}

final reportsFilterProvider =
    NotifierProvider<ReportsFilterNotifier, ReportsFilterState>(
  ReportsFilterNotifier.new,
);
