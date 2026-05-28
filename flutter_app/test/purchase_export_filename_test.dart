import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/core/models/trade_purchase_models.dart';
import 'package:harisree_warehouse/core/services/pdf_locale.dart';
import 'package:harisree_warehouse/core/services/purchase_pdf.dart';

void main() {
  setUpAll(() async {
    await ensurePdfLocalesInitialized();
  });

  TradePurchase purchase({String? supplier}) {
    return TradePurchase(
      id: 'id',
      humanId: 'PO-99',
      purchaseDate: DateTime(2026, 5, 25),
      paidAmount: 0,
      totalAmount: 100,
      storedStatus: 'confirmed',
      derivedStatus: 'confirmed',
      remaining: 100,
      discount: 0,
      commissionPercent: 0,
      freightType: 'separate',
      supplierName: supplier,
      lines: [
        TradePurchaseLine(
          id: 'l1',
          itemName: 'Rice',
          qty: 1,
          unit: 'bag',
          landingCost: 100,
        ),
      ],
    );
  }

  test('filename uses PO_SUPPLIER_DD_MMM_YYYY pattern', () {
    final name = buildPurchaseSharePdfFileName(
      purchase(supplier: 'Ambal Modern Rice Mill'),
    );
    expect(name, 'PO_AMBAL_MODERN_RICE_MILL_25_MAY_2026.pdf');
  });

  test('filename fallback when supplier missing', () {
    final name = buildPurchaseSharePdfFileName(purchase(supplier: null));
    expect(name, startsWith('PO_PO-99_'));
    expect(name, endsWith('.pdf'));
  });
}
