import 'package:dio/dio.dart';

import '../api/hexa_api.dart';
import '../auth/auth_error_messages.dart';
import '../json_coerce.dart';

/// True when [fresh] row already reflects [expectedQty] for system or physical save.
bool stockSaveMatchesServerRow(
  Map<String, dynamic> fresh,
  num expectedQty, {
  required bool systemLedger,
}) {
  final target = expectedQty.toDouble();
  if (systemLedger) {
    final cur = coerceToDouble(fresh['current_stock']);
    return cur.isFinite && (cur - target).abs() <= 0.001;
  }
  final phys = coerceToDoubleNullable(fresh['physical_stock_qty']);
  if (phys == null || !phys.isFinite) return false;
  return (phys - target).abs() <= 0.001;
}

/// After a timeout/transport error, confirm whether the write actually landed.
Future<Map<String, dynamic>?> verifyStockSaveApplied({
  required HexaApi api,
  required String businessId,
  required String itemId,
  required num expectedQty,
  required bool systemLedger,
}) async {
  final fresh = await api.getStockItem(
    businessId: businessId,
    itemId: itemId,
  );
  if (!stockSaveMatchesServerRow(
    fresh,
    expectedQty,
    systemLedger: systemLedger,
  )) {
    return null;
  }
  return fresh;
}

bool stockSaveErrorWorthServerVerify(Object error) {
  if (error is StateError) return true;
  if (error is! DioException) return false;
  return dioIsNetworkError(error) ||
      error.type == DioExceptionType.receiveTimeout ||
      error.type == DioExceptionType.sendTimeout;
}
