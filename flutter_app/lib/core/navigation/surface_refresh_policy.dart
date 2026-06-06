/// When to refetch shell tab data on return (avoid reload loops).
const Duration kShellTabReturnMinInterval = Duration(seconds: 45);

/// Lightweight home surfaces (activity + inventory) may refresh more often.
const Duration kHomeSoftRefreshMinInterval = Duration(seconds: 30);

const Duration kStockListCacheTtl = Duration(minutes: 3);

bool shouldRefreshOnShellTabReturn(DateTime? lastRefreshedAt) {
  if (lastRefreshedAt == null) return true;
  return DateTime.now().difference(lastRefreshedAt) >= kShellTabReturnMinInterval;
}

bool shouldSoftRefreshHomeSurfaces(DateTime? lastRefreshedAt) {
  if (lastRefreshedAt == null) return true;
  return DateTime.now().difference(lastRefreshedAt) >= kHomeSoftRefreshMinInterval;
}
