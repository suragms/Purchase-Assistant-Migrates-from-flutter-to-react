import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/core/models/business_profile.dart';
import 'package:harisree_warehouse/core/models/trade_purchase_models.dart';
import 'package:harisree_warehouse/core/services/purchase_accounts_share.dart';

void main() {
  group('normalizeAccountsWhatsappPhone', () {
    test('India 10 digit', () {
      final n = normalizeAccountsWhatsappPhone('9876543210');
      expect(n?.storageDigits, '9876543210');
      expect(n?.waMeDigits, '919876543210');
    });

    test('India +91 prefix', () {
      final n = normalizeAccountsWhatsappPhone('+91 98765 43210');
      expect(n?.storageDigits, '9876543210');
      expect(n?.waMeDigits, '919876543210');
    });

    test('UAE international', () {
      final n = normalizeAccountsWhatsappPhone('+971 50 123 4567');
      expect(n?.storageDigits, '971501234567');
      expect(n?.waMeDigits, '971501234567');
    });

    test('UAE local 9 digits', () {
      final n = normalizeGulfMobile('501234567');
      expect(n?.storageDigits, '971501234567');
    });

    test('Oman 8 digit national with prefix', () {
      final n = normalizeAccountsWhatsappPhone('96891234567');
      expect(n?.storageDigits, '96891234567');
    });

    test('rejects invalid', () {
      expect(normalizeAccountsWhatsappPhone('12345'), isNull);
    });
  });

  group('normalizedFromStoredAccountsWhatsapp', () {
    test('stored India 10 builds wa.me 91', () {
      final n = normalizedFromStoredAccountsWhatsapp('9876543210');
      expect(n?.waMeDigits, '919876543210');
    });

    test('stored Gulf intl unchanged', () {
      final n = normalizedFromStoredAccountsWhatsapp('971501234567');
      expect(n?.waMeDigits, '971501234567');
    });
  });

  group('buildAccountsWhatsAppSummary', () {
    test('includes business, lines, grand total', () {
      final p = TradePurchase(
        id: 'uuid-1',
        humanId: 'PO-99',
        purchaseDate: DateTime(2026, 6, 3),
        paidAmount: 0,
        totalAmount: 21400,
        storedStatus: 'saved',
        derivedStatus: 'saved',
        remaining: 21400,
        supplierName: 'ABC Traders',
        itemsCount: 1,
        lines: [
          TradePurchaseLine(
            id: 'l1',
            itemName: 'Rice 25kg',
            qty: 10,
            unit: 'bag',
            landingCost: 2100,
            lineTotal: 21000,
          ),
        ],
      );
      const biz = BusinessProfile(
        legalName: 'NEW HARISREE AGENCY',
        displayTitle: 'HARISREE AGENCY',
      );
      final text = buildAccountsWhatsAppSummary(p, biz);
      expect(text, contains('HARISREE AGENCY'));
      expect(text, contains('Purchase date: 03/06/2026'));
      expect(text, contains('Supplier: ABC Traders'));
      expect(text, contains('Ref: PO-99'));
      expect(text, contains('Rice 25kg'));
      expect(text, contains('Grand total:'));
      expect(text, isNot(contains('*')));
    });
  });
}
