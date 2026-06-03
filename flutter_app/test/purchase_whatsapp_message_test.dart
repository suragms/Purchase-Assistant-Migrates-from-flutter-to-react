import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/core/models/business_profile.dart';
import 'package:harisree_warehouse/core/models/trade_purchase_models.dart';
import 'package:harisree_warehouse/core/services/purchase_accounts_share.dart';

void main() {
  final biz = const BusinessProfile(
    legalName: 'NEW HARISREE AGENCY',
    displayTitle: 'Harisree',
  );

  TradePurchase sample({String? brokerName, DateTime? dueDate}) {
    return TradePurchase.fromJson({
      'id': 'tp-1',
      'human_id': 'PO-2026-00125',
      'purchase_date': '2026-06-01',
      'supplier_name': 'ABC Traders',
      if (brokerName != null) 'broker_name': brokerName,
      'total_amount': 125000,
      if (dueDate != null)
        'due_date': dueDate.toIso8601String().split('T').first,
      'lines': [
        {
          'item_name': 'Rice',
          'qty': 100,
          'unit': 'bag',
          'landing_cost': 500,
        },
        {
          'item_name': 'Dal',
          'qty': 150,
          'unit': 'bag',
          'landing_cost': 300,
        },
      ],
    });
  }

  test('buildPurchaseOrderWhatsAppMessage includes PO supplier and delivery', () {
    final msg = buildPurchaseOrderWhatsAppMessage(
      sample(dueDate: DateTime(2026, 6, 5)),
      biz,
    );
    expect(msg, contains('PO-2026-00125'));
    expect(msg, contains('ABC Traders'));
    expect(msg, contains('Items:'));
    expect(msg, contains('2'));
    expect(msg, contains('Expected Delivery:'));
    expect(msg, contains('05-Jun-2026'));
    expect(msg, contains('Please verify when goods arrive.'));
    expect(msg, contains('PDF attached'));
  });

  test('buildPurchaseOrderWhatsAppMessage includes broker when set', () {
    final msg = buildPurchaseOrderWhatsAppMessage(
      sample(brokerName: 'Ravi Broker'),
      biz,
    );
    expect(msg, contains('Broker:'));
    expect(msg, contains('Ravi Broker'));
  });

  test('maskWhatsappRecipient hides middle digits', () {
    expect(maskWhatsappRecipient('919876543210'), '***3210');
  });
}
