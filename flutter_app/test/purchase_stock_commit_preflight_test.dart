import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/core/models/trade_purchase_models.dart';
import 'package:harisree_warehouse/core/purchase/purchase_stock_commit_preflight.dart';

TradePurchaseLine _line({
  String unit = 'bag',
  double qty = 10,
  String? catalogItemId = 'item-1',
  String? defaultUnit,
  double? defaultKgPerBag,
  double? kgPerUnit,
  String itemName = 'Loose Sugar',
}) {
  return TradePurchaseLine(
    id: 'line-1',
    itemName: itemName,
    qty: qty,
    unit: unit,
    landingCost: 100,
    catalogItemId: catalogItemId,
    defaultUnit: defaultUnit,
    defaultKgPerBag: defaultKgPerBag,
    kgPerUnit: kgPerUnit,
  );
}

void main() {
  group('estimateLineQtyInStockUnit', () {
    test('kg stock + bag line without kg_per_bag → 0', () {
      final line = _line(unit: 'bag', qty: 10);
      final row = {
        'id': 'item-1',
        'default_unit': 'kg',
        'unit_resolution': {'stock_unit': 'KG', 'package_type': 'LOOSE_KG'},
      };
      expect(estimateLineQtyInStockUnit(line, row), 0);
    });

    test('bag stock + bag line with kg_per_bag passes qty through', () {
      final line = _line(unit: 'bag', qty: 2, kgPerUnit: 50);
      final row = {
        'id': 'item-1',
        'default_unit': 'bag',
        'default_kg_per_bag': 50,
        'unit_resolution': {
          'stock_unit': 'KG',
          'package_type': 'SACK',
          'kg_per_bag': 50,
        },
      };
      expect(estimateLineQtyInStockUnit(line, row), 2);
    });

    test('kg stock + bag line with kg_per_bag converts to kg', () {
      final line = _line(unit: 'bag', qty: 2, kgPerUnit: 50);
      final row = {
        'id': 'item-1',
        'default_unit': 'kg',
        'default_kg_per_bag': 50,
        'unit_resolution': {'stock_unit': 'KG', 'package_type': 'LOOSE_KG'},
      };
      expect(estimateLineQtyInStockUnit(line, row), 100);
    });

    test('box stock + box line passes through', () {
      final line = _line(unit: 'box', qty: 1);
      final row = {
        'id': 'item-1',
        'default_unit': 'box',
        'unit_resolution': {'package_type': 'BOX', 'stock_unit': 'BOX'},
      };
      expect(estimateLineQtyInStockUnit(line, row), 1);
    });

    test('kg stock + box line without mapping → 0', () {
      final line = _line(unit: 'box', qty: 1, itemName: 'Soap Carton');
      final row = {
        'id': 'item-1',
        'default_unit': 'kg',
        'unit_resolution': {'stock_unit': 'KG', 'package_type': 'LOOSE_KG'},
      };
      expect(estimateLineQtyInStockUnit(line, row), 0);
    });

    test('piece profile + box purchase line → 0', () {
      final line = _line(unit: 'box', qty: 2);
      final row = {
        'id': 'item-1',
        'default_unit': 'piece',
        'unit_resolution': {'package_type': 'RETAIL_PACKET', 'stock_unit': 'PIECE'},
      };
      expect(estimateLineQtyInStockUnit(line, row), 0);
    });

    test('piece profile + box purchase line with BOX in name → 1:1', () {
      final line = _line(unit: 'box', qty: 2, itemName: 'SUNRICH 400GM BOX');
      final row = {
        'id': 'item-1',
        'default_unit': 'piece',
        'name': 'SUNRICH 400GM BOX',
        'unit_resolution': {'package_type': 'RETAIL_PACKET', 'stock_unit': 'PIECE'},
      };
      expect(catalogStockUnit(row, line), 'box');
      expect(estimateLineQtyForStockCommit(line, row), 2);
    });

    test('zero qty_in_stock_unit snap falls through to conversion', () {
      final line = TradePurchaseLine(
        id: 'line-1',
        itemName: 'SUNRICH 400GM BOX',
        qty: 2,
        unit: 'box',
        landingCost: 80,
        catalogItemId: 'item-1',
        receivedQty: 2,
        qtyInStockUnit: 0,
      );
      final row = {
        'id': 'item-1',
        'default_unit': 'box',
        'name': 'SUNRICH 400GM BOX',
      };
      expect(estimateLineQtyForStockCommit(line, row), 2);
    });

    test('suggest box unit for BOX line on piece catalog', () {
      final issue = PurchaseStockCommitIssue(
        kind: PurchaseStockCommitIssueKind.needsUnitSetup,
        lineId: 'l1',
        itemName: 'SUNRICH 400GM BOX',
        catalogItemId: 'item-1',
        qty: 1,
        lineUnit: 'box',
        stockUnit: 'piece',
      );
      expect(
        suggestCatalogUnitForStockCommitIssue(issue, const {
          'default_unit': 'piece',
          'name': 'SUNRICH 400GM BOX',
        }),
        'box',
      );
    });

    test('owner box unit + RETAIL_PACKET package → box line passes', () {
      final line = _line(unit: 'box', qty: 1, itemName: 'SUNRICH 400GM BOX');
      final row = {
        'id': 'item-1',
        'default_unit': 'box',
        'default_items_per_box': 1,
        'package_type': 'RETAIL_PACKET',
        'unit_resolution': {
          'package_type': 'RETAIL_PACKET',
          'stock_unit': 'PIECE',
          'package_size': 400,
          'package_measurement': 'GM',
        },
      };
      expect(catalogStockUnit(row, line), 'box');
      expect(estimateLineQtyInStockUnit(line, row), 1);
    });
  });

  group('findPurchaseStockCommitIssues', () {
    test('flags missing catalog link', () {
      final purchase = TradePurchase(
        id: 'p1',
        humanId: 'P-1',
        purchaseDate: DateTime(2026, 6, 6),
        paidAmount: 0,
        totalAmount: 100,
        storedStatus: 'confirmed',
        derivedStatus: 'confirmed',
        remaining: 100,
        lines: [_line(catalogItemId: null)],
      );
      final issues = findPurchaseStockCommitIssues(purchase, const []);
      expect(issues, hasLength(1));
      expect(issues.first.kind, PurchaseStockCommitIssueKind.missingCatalogLink);
    });

    test('flags unit setup when conversion is zero', () {
      final purchase = TradePurchase(
        id: 'p1',
        humanId: 'P-1',
        purchaseDate: DateTime(2026, 6, 6),
        paidAmount: 0,
        totalAmount: 100,
        storedStatus: 'confirmed',
        derivedStatus: 'confirmed',
        remaining: 100,
        lines: [_line(unit: 'box', qty: 1)],
      );
      final catalog = [
        {
          'id': 'item-1',
          'default_unit': 'kg',
          'unit_resolution': {'stock_unit': 'KG', 'package_type': 'LOOSE_KG'},
        },
      ];
      final issues = findPurchaseStockCommitIssues(purchase, catalog);
      expect(issues, hasLength(1));
      expect(issues.first.kind, PurchaseStockCommitIssueKind.needsUnitSetup);
      expect(issues.first.stockUnit, 'kg');
    });
  });
}
