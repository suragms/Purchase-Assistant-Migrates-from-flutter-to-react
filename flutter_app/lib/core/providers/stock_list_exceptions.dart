/// Thrown when stock list must not return an empty success payload (auth gate / no session).
class StockListFetchBlockedException implements Exception {
  const StockListFetchBlockedException([this.reason]);

  final String? reason;

  @override
  String toString() => 'StockListFetchBlockedException(${reason ?? 'blocked'})';
}

bool isStockListAuthFailure(Object? error) {
  if (error is! StockListFetchBlockedException) return false;
  switch (error.reason) {
    case 'no_session':
    case 'api_gate':
    case 'business_mismatch':
      return true;
    case 'tab_not_visible':
      return false;
    default:
      return false;
  }
}
