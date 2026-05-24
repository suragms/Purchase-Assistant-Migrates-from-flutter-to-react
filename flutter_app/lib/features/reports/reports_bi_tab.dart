/// Reports BI shell tabs (query param: `tab`).
enum ReportsBiTab {
  overview,
  categories,
  subcategories,
  items,
  suppliers,
  brokers,
  slowMoving,
  deadStock,
  usage,
  stockMovement,
}

extension ReportsBiTabX on ReportsBiTab {
  String get queryValue => switch (this) {
        ReportsBiTab.overview => 'overview',
        ReportsBiTab.categories => 'categories',
        ReportsBiTab.subcategories => 'subcategories',
        ReportsBiTab.items => 'items',
        ReportsBiTab.suppliers => 'suppliers',
        ReportsBiTab.brokers => 'brokers',
        ReportsBiTab.slowMoving => 'slow',
        ReportsBiTab.deadStock => 'dead',
        ReportsBiTab.usage => 'usage',
        ReportsBiTab.stockMovement => 'movement',
      };

  String get shortLabel => switch (this) {
        ReportsBiTab.overview => 'Overview',
        ReportsBiTab.categories => 'Categories',
        ReportsBiTab.subcategories => 'Subcat',
        ReportsBiTab.items => 'Items',
        ReportsBiTab.suppliers => 'Suppliers',
        ReportsBiTab.brokers => 'Brokers',
        ReportsBiTab.slowMoving => 'Slow',
        ReportsBiTab.deadStock => 'Dead',
        ReportsBiTab.usage => 'Usage',
        ReportsBiTab.stockMovement => 'Stock mvmt',
      };

  static ReportsBiTab? fromQuery(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final k = raw.trim().toLowerCase();
    return switch (k) {
      'overview' || 'ring' => ReportsBiTab.overview,
      'categories' || 'category' => ReportsBiTab.categories,
      'subcategories' || 'subcategory' || 'types' => ReportsBiTab.subcategories,
      'items' || 'item' => ReportsBiTab.items,
      'suppliers' || 'supplier' || 'supp' => ReportsBiTab.suppliers,
      'brokers' || 'broker' => ReportsBiTab.brokers,
      'slow' || 'slow_moving' || 'slowmoving' => ReportsBiTab.slowMoving,
      'dead' || 'dead_stock' || 'deadstock' => ReportsBiTab.deadStock,
      'usage' => ReportsBiTab.usage,
      'movement' || 'stock_movement' => ReportsBiTab.stockMovement,
      _ => null,
    };
  }

  /// Primary row on phone; rest open via More sheet.
  static const primaryRow = [
    ReportsBiTab.overview,
    ReportsBiTab.categories,
    ReportsBiTab.subcategories,
    ReportsBiTab.items,
    ReportsBiTab.suppliers,
  ];

  static const moreSheet = [
    ReportsBiTab.brokers,
    ReportsBiTab.slowMoving,
    ReportsBiTab.deadStock,
    ReportsBiTab.usage,
    ReportsBiTab.stockMovement,
  ];
}
