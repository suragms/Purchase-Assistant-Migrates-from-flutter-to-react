import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import 'quick_stock_action_sheet.dart';
import 'widgets/stock_update_mode_toggle.dart';

/// Loads authoritative stock row from API, then opens the quick stock sheet.
Future<bool> openQuickStockWithFreshItem({
  required BuildContext context,
  required WidgetRef ref,
  required String itemId,
  required String itemName,
  Map<String, dynamic>? fallbackRow,
  StockUpdateMode initialMode = StockUpdateMode.physical,
  bool skipFreshFetch = false,
}) async {
  final session = ref.read(sessionProvider);
  if (session == null) return false;

  Map<String, dynamic> item;
  final canUseFallback = fallbackRow != null &&
      fallbackRow.isNotEmpty &&
      fallbackRow['current_stock'] != null;
  if (skipFreshFetch && canUseFallback) {
    item = Map<String, dynamic>.from(fallbackRow);
  } else {
    try {
      item = await ref.read(hexaApiProvider).getStockItem(
            businessId: session.primaryBusiness.id,
            itemId: itemId,
          );
    } on DioException catch (e) {
      if (canUseFallback) {
        item = Map<String, dynamic>.from(fallbackRow);
      } else {
        if (context.mounted) {
          final msg = e.response?.statusCode == 404
              ? 'Item not found in stock.'
              : friendlyApiError(e);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg)),
          );
        }
        return false;
      }
    }
  }

  if (!context.mounted) return false;
  if (!item.containsKey('id') || (item['id']?.toString() ?? '').isEmpty) {
    item['id'] = itemId;
  }
  if (!item.containsKey('name') || (item['name']?.toString() ?? '').isEmpty) {
    item['name'] = itemName;
  }

  return showQuickStockActionSheet(
    context: context,
    ref: ref,
    item: item,
    initialMode: initialMode,
    skipInitialRefresh: true,
  );
}
