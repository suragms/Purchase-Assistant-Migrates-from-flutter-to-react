import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/features/barcode/presentation/bulk_barcode_print_toolbar.dart';
import 'package:harisree_warehouse/features/barcode/services/bulk_pdf_chunks.dart';
import 'package:harisree_warehouse/features/stock/presentation/widgets/stock_table_row.dart';

import 'responsive_test_utils.dart';

void main() {
  testWidgets('stock table row stays within audited viewport widths',
      (tester) async {
    final widget = MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: double.infinity,
          child: StockTableRow(
            item: const {
              'id': 'item-1',
              'name': '916 RAVA 50KG SUPER LONG WAREHOUSE ITEM NAME',
              'item_code': 'SL-00000051',
              'subcategory_name': 'Wholesale Rava',
              'current_stock': 101.0,
              'stock_unit': 'bag',
              'stock_status': 'low',
              'missing_barcode': true,
              'period_purchased_qty': 125,
              'physical_stock_difference_qty': -24,
            },
            onTap: () {},
          ),
        ),
      ),
    );

    await expectNoResponsiveOverflow(tester, widget, height: 220);
  });

  testWidgets('bulk barcode toolbar adapts at phone and desktop widths',
      (tester) async {
    final widget = MaterialApp(
      home: Scaffold(
        bottomNavigationBar: BulkBarcodePrintToolbar(
          selectedCount: 534,
          busy: false,
          denseA4: true,
          useQr: false,
          copies: 3,
          labelsPerPdfFile: BulkLabelsPerPdfFile.n50,
          progress: null,
          statusText: 'Ready to download selected labels',
          onDenseA4Changed: (_) {},
          onQrChanged: (_) {},
          onCopiesChanged: (_) {},
          onLabelsPerPdfFileChanged: (_) {},
          onPreview: () async {},
          onPdf: () async {},
          onPrint: () async {},
          pdfButtonLabel: 'Download (6 batches)',
        ),
      ),
    );

    await expectNoResponsiveOverflow(
      tester,
      widget,
      widths: const [320, 375, 768, 1440, 1920],
      height: 360,
    );
  });
}
