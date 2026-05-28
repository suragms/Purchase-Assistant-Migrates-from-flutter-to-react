import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/core/models/business_profile.dart';
import 'package:harisree_warehouse/core/models/trade_purchase_models.dart';
import 'package:harisree_warehouse/core/services/pdf_locale.dart';
import 'package:harisree_warehouse/core/services/pdf_purchase_fonts.dart';
import 'package:harisree_warehouse/core/services/purchase_invoice_pdf_layout.dart';
import 'package:harisree_warehouse/core/utils/trade_purchase_rate_display.dart';
import 'package:harisree_warehouse/shared/widgets/trade_intel_cards.dart';

void main() {
  setUpAll(() async {
    await ensurePdfLocalesInitialized();
  });

  test('kPurchaseOrderPdfTitle constant', () {
    expect(kPurchaseOrderPdfTitle, 'New Harisree Agency Purchase Order');
  });

  test('tradeIntelSearchCatalogSubtitle uses only confirmed purchase fields', () {
    expect(tradeIntelSearchCatalogSubtitle({}), '');
    expect(tradeIntelSearchCatalogSubtitle({'default_landing_cost': 99}), '');
    expect(tradeIntelSearchCatalogSubtitle({'default_selling_cost': 50}), '');
    expect(
      tradeIntelSearchCatalogSubtitle({'last_purchase_price': 100}),
      contains('Last buy'),
    );
    expect(
      tradeIntelSearchCatalogSubtitle({
        'last_purchase_price': 10,
        'last_selling_rate': 12,
      }),
      contains('Last sell'),
    );
  });

  testWidgets('professional purchase PDF builds with bundled Unicode fonts',
      (tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final p = TradePurchase(
      id: 't',
      humanId: 'PO-1',
      purchaseDate: DateTime(2026, 5, 1),
      paidAmount: 0,
      totalAmount: 110,
      storedStatus: 'confirmed',
      derivedStatus: 'confirmed',
      remaining: 110,
      discount: 0,
      commissionPercent: 0,
      freightType: 'separate',
      lines: [
        TradePurchaseLine(
          id: '1',
          itemName: '\u0D2A\u0D30\u0D40\u0D15\u0D4D\u0D37\u0D23\u0D02',
          qty: 1,
          unit: 'kg',
          landingCost: 100,
          taxPercent: 10,
        ),
      ],
    );
    const biz = BusinessProfile(
      legalName: 'T',
      displayTitle: 'Test Biz',
      phone: '999',
    );
    final theme = await loadPurchasePdfTheme();
    final doc = await buildProfessionalPurchaseInvoiceDoc(
      purchase: p,
      business: biz,
      pdfTheme: theme,
    );
    final bytes = await doc.save();
    expect(bytes.length, greaterThan(1000));
  });
}
