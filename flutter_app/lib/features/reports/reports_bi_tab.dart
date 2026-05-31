/// Reports BI shell tabs (query param: `tab`).
enum ReportsBiTab {
  overview,
  categories,
  subcategories,
  items,
  purchases,
  stock,
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
        ReportsBiTab.purchases => 'purchase',
        ReportsBiTab.stock => 'stock',
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
        ReportsBiTab.purchases => 'Purchases',
        ReportsBiTab.stock => 'Stock',
        ReportsBiTab.suppliers => 'Suppliers',
        ReportsBiTab.brokers => 'Brokers',
        ReportsBiTab.slowMoving => 'Stock intel',
        ReportsBiTab.deadStock => 'Dead',
        ReportsBiTab.usage => 'Usage',
        ReportsBiTab.stockMovement => 'Activity',
      };

  static ReportsBiTab? fromQuery(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final k = raw.trim().toLowerCase();
    return switch (k) {
      'overview' || 'ring' => ReportsBiTab.overview,
      'categories' || 'category' => ReportsBiTab.categories,
      'subcategories' || 'subcategory' || 'types' => ReportsBiTab.subcategories,
      'items' || 'item' => ReportsBiTab.items,
      'purchase' || 'purchases' => ReportsBiTab.purchases,
      'stock' || 'stock_intel' => ReportsBiTab.stock,
      'suppliers' || 'supplier' || 'supp' => ReportsBiTab.suppliers,
      'brokers' || 'broker' => ReportsBiTab.brokers,
      'slow' || 'slow_moving' || 'slowmoving' => ReportsBiTab.slowMoving,
      'dead' || 'dead_stock' || 'deadstock' => ReportsBiTab.deadStock,
      'usage' => ReportsBiTab.usage,
      'movement' || 'stock_movement' || 'activity' => ReportsBiTab.stockMovement,
      _ => null,
    };
  }

  /// Primary sticky row — no wrap; horizontal scroll on narrow screens.
  static const primaryRow = [
    ReportsBiTab.overview,
    ReportsBiTab.items,
    ReportsBiTab.purchases,
    ReportsBiTab.stock,
    ReportsBiTab.stockMovement,
  ];

  static const moreSheet = [
    ReportsBiTab.categories,
    ReportsBiTab.subcategories,
    ReportsBiTab.suppliers,
    ReportsBiTab.brokers,
    ReportsBiTab.usage,
  ];
}
