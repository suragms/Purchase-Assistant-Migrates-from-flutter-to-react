import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/json_coerce.dart';
import '../../../../core/utils/unit_utils.dart';

/// Export selected low-stock rows as CSV (download/share).
Future<void> exportLowStockSelectionCsv(
  BuildContext context, {
  required List<Map<String, dynamic>> items,
}) async {
  if (items.isEmpty) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No items in this view to export')),
    );
    return;
  }

  final buf = StringBuffer(
    'name,subcategory,unit,system_stock,physical_stock,reorder,purchased,status,supplier\n',
  );
  for (final item in items) {
    final unit = (item['stock_unit'] ?? item['unit'])?.toString() ?? '';
    final cols = [
      item['name'],
      item['subcategory_name'] ?? item['category_name'],
      unit,
      formatStockQtyNumber(coerceToDouble(item['current_stock'])),
      item['physical_stock_qty'] != null
          ? formatStockQtyNumber(coerceToDouble(item['physical_stock_qty']))
          : '',
      coerceToDouble(item['reorder_level']) > 0
          ? formatStockQtyNumber(coerceToDouble(item['reorder_level']))
          : '',
      coerceToDouble(item['period_purchased_qty']) > 0
          ? formatStockQtyNumber(coerceToDouble(item['period_purchased_qty']))
          : '',
      item['stock_status'],
      item['supplier_name'],
    ];
    buf.writeln(cols.map(_csvEscape).join(','));
  }

  final csv = buf.toString();
  if (kIsWeb) {
    await Clipboard.setData(ClipboardData(text: csv));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied ${items.length} rows to clipboard')),
    );
    return;
  }

  try {
    final bytes = utf8.encode(csv);
    await Share.shareXFiles(
      [
        XFile.fromData(
          bytes,
          mimeType: 'text/csv',
          name: 'harisree_low_stock.csv',
        ),
      ],
      subject: 'Low stock export',
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Exported ${items.length} low-stock rows')),
    );
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not share CSV. Try again.')),
    );
  }
}

String _csvEscape(Object? v) {
  final s = (v ?? '').toString().replaceAll('"', '""');
  if (s.contains(',') || s.contains('\n')) return '"$s"';
  return s;
}
