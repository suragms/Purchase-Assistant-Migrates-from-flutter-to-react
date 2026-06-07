import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/core/router/shell_navigation.dart';
import 'package:harisree_warehouse/features/shell/shell_branch_provider.dart';

void main() {
  group('shellIsPrimaryTabLocation', () {
    test('matches shell tab roots only', () {
      expect(shellIsPrimaryTabLocation('/home'), isTrue);
      expect(shellIsPrimaryTabLocation('/home/activity'), isTrue);
      expect(shellIsPrimaryTabLocation('/stock'), isTrue);
      expect(shellIsPrimaryTabLocation('/purchase'), isTrue);
      expect(shellIsPrimaryTabLocation('/reports'), isTrue);
      expect(shellIsPrimaryTabLocation('/search'), isTrue);
    });

    test('rejects overlay routes', () {
      expect(shellIsPrimaryTabLocation('/catalog/quick-add'), isFalse);
      expect(shellIsPrimaryTabLocation('/catalog/item/abc/edit'), isFalse);
      expect(shellIsPrimaryTabLocation('/purchase/edit/p1'), isFalse);
      expect(shellIsPrimaryTabLocation('/stock/reorder'), isFalse);
      expect(shellIsPrimaryTabLocation('/reports/sales-comparison'), isFalse);
    });
  });

  group('shellIsPushedModalPath', () {
    test('catalog and purchase overlays are pushed modals', () {
      expect(shellIsPushedModalPath('/catalog/quick-add'), isTrue);
      expect(shellIsPushedModalPath('/catalog/item/x/edit'), isTrue);
      expect(shellIsPushedModalPath('/purchase/new'), isTrue);
      expect(shellIsPushedModalPath('/stock/low-stock'), isTrue);
    });

    test('shell tab roots are not pushed modals', () {
      expect(shellIsPushedModalPath('/home'), isFalse);
      expect(shellIsPushedModalPath('/stock'), isFalse);
      expect(shellIsPushedModalPath('/purchase'), isFalse);
    });
  });

  group('shellBranchIndexForPath', () {
    test('catalog overlays do not map to a shell branch', () {
      expect(shellBranchIndexForPath('/catalog/quick-add'), isNull);
      expect(shellBranchIndexForPath('/catalog/item/x/edit'), isNull);
    });

    test('stock tab root maps to stock branch', () {
      expect(shellBranchIndexForPath('/stock'), ShellBranch.stock);
    });

    test('purchase entry does not auto-switch shell to history list', () {
      expect(shellBranchIndexForPath('/purchase/new'), isNull);
      expect(shellIsPrimaryTabLocation('/purchase/new'), isFalse);
    });

    test('low stock dashboard does not auto-switch shell', () {
      expect(shellBranchIndexForPath('/stock/low-stock'), isNull);
      expect(shellIsPushedModalPath('/stock/low-stock'), isTrue);
    });

    test('barcode overlays do not auto-switch shell', () {
      expect(shellBranchIndexForPath('/barcode/scan'), isNull);
    });

    test('stock sub-routes do not auto-switch shell', () {
      expect(shellBranchIndexForPath('/stock/reorder'), isNull);
    });
  });
}
