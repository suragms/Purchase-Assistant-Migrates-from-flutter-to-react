import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/catalog/presentation/widgets/quick_catalog_unit_setup_sheet.dart';
import '../api/fastapi_error.dart';
import '../auth/auth_error_messages.dart';
import '../auth/session_notifier.dart';
import '../models/trade_purchase_models.dart';
import '../providers/business_aggregates_invalidation.dart'
    show
        invalidateNotificationSurfaces,
        invalidateStaffDeliverySurfacesLight,
        syncPurchaseStockFromPurchaseJson;
import '../providers/catalog_providers.dart';
import '../providers/trade_purchases_provider.dart';
import '../router/navigation_ext.dart';
import '../utils/snack.dart';
import 'purchase_stock_commit_preflight.dart';

final _commitStockInFlight = <String>{};

Future<List<Map<String, dynamic>>> ensureCatalogRowsForCommitPreflight(
  WidgetRef ref,
) async {
  try {
    return await ref.read(catalogItemsListProvider.future);
  } catch (_) {
    return ref.read(catalogItemsListProvider).valueOrNull ?? const [];
  }
}

Future<Map<String, dynamic>?> catalogRowForCommitIssue(
  WidgetRef ref,
  PurchaseStockCommitIssue issue,
  List<Map<String, dynamic>> catalogRows,
) async {
  final cid = issue.catalogItemId?.trim();
  if (cid == null || cid.isEmpty) return null;
  for (final row in catalogRows) {
    if (row['id']?.toString() == cid) return row;
  }
  try {
    final session = ref.read(sessionProvider);
    if (session == null) return null;
    return await ref.read(hexaApiProvider).getCatalogItem(
          businessId: session.primaryBusiness.id,
          itemId: cid,
        );
  } catch (_) {
    return null;
  }
}

Future<List<PurchaseStockCommitIssue>> loadPurchaseStockCommitIssues(
  WidgetRef ref,
  TradePurchase purchase,
) async {
  final rows = await ensureCatalogRowsForCommitPreflight(ref);
  return findPurchaseStockCommitIssues(purchase, rows);
}

List<PurchaseStockCommitIssue> purchaseStockCommitIssues(
  WidgetRef ref,
  TradePurchase purchase,
) {
  return findPurchaseStockCommitIssues(
    purchase,
    ref.read(catalogItemsListProvider).valueOrNull ?? const [],
  );
}

/// Opens inline unit sheets for each blocked line. Returns true if any saved.
Future<bool> resolvePurchaseStockCommitUnitSetup(
  BuildContext context,
  WidgetRef ref,
  TradePurchase purchase,
  List<PurchaseStockCommitIssue> issues,
) async {
  if (issues.isEmpty || !context.mounted) return false;
  var rows = await ensureCatalogRowsForCommitPreflight(ref);
  var fixedAny = false;

  for (final issue in issues) {
    if (issue.kind == PurchaseStockCommitIssueKind.missingCatalogLink) {
      continue;
    }
    if (!context.mounted) break;
    final row = await catalogRowForCommitIssue(ref, issue, rows);
    final saved = await showQuickCatalogUnitSetupSheet(
      context,
      ref: ref,
      issue: issue,
      catalogRow: row,
    );
    if (!context.mounted) break;
    if (saved) {
      fixedAny = true;
      rows = await ensureCatalogRowsForCommitPreflight(ref);
    }
  }
  return fixedAny;
}

Future<void> showPurchaseStockCommitBlockedDialog(
  BuildContext context,
  WidgetRef ref,
  TradePurchase purchase,
  List<PurchaseStockCommitIssue> issues,
) async {
  if (issues.isEmpty || !context.mounted) return;
  String? firstCatalogId;
  for (final issue in issues) {
    final id = issue.catalogItemId?.trim();
    if (id != null && id.isNotEmpty) {
      firstCatalogId = id;
      break;
    }
  }
  final hasUnitSetup = issues.any(
    (i) => i.kind == PurchaseStockCommitIssueKind.needsUnitSetup,
  );
  try {
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Set up units before commit'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Stock cannot be added until each line converts to the catalog stock unit.',
              ),
              const SizedBox(height: 12),
              ...issues.map(
                (issue) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        issue.headline,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        issue.detail,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              context.push('/purchase/edit/${purchase.id}');
            },
            child: const Text('Edit purchase'),
          ),
          if (hasUnitSetup)
            FilledButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                await resolvePurchaseStockCommitUnitSetup(
                  context,
                  ref,
                  purchase,
                  issues,
                );
              },
              child: const Text('Set up units'),
            )
          else if (firstCatalogId != null)
            FilledButton(
              onPressed: () {
                final catalogId = firstCatalogId!;
                Navigator.of(dialogContext).pop();
                pushCatalogItemEdit(context, catalogId);
              },
              child: const Text('Edit catalog item'),
            ),
        ],
      ),
    );
  } catch (_) {
    // Dialog can fail on web if route context lost.
  }
}

List<PurchaseStockCommitIssue> _issuesFromCommitStock400(
  WidgetRef ref,
  TradePurchase purchase,
  DioException e,
) {
  final data = e.response?.data;
  if (data is! Map) return purchaseStockCommitIssues(ref, purchase);
  final nested = data['detail'];
  if (nested is Map && nested['code']?.toString() == 'UNIT_SETUP_REQUIRED') {
    final names = nested['items_needing_setup'];
    if (names is List && names.isNotEmpty) {
      final rows = ref.read(catalogItemsListProvider).valueOrNull ?? const [];
      final fromApi = issuesFromUnitSetupItemNames(purchase, names, rows);
      if (fromApi.isNotEmpty) return fromApi;
    }
  }
  return purchaseStockCommitIssues(ref, purchase);
}

Future<bool> _performCommitStock(
  BuildContext context,
  WidgetRef ref,
  TradePurchase purchase,
) async {
  final session = ref.read(sessionProvider);
  if (session == null) return false;
  final updated = await ref.read(hexaApiProvider).commitPurchaseDelivery(
        businessId: session.primaryBusiness.id,
        purchaseId: purchase.id,
      );
  syncPurchaseStockFromPurchaseJson(
    ref,
    purchaseId: purchase.id,
    body: updated,
  );
  invalidateNotificationSurfaces(ref);
  invalidateStaffDeliverySurfacesLight(ref);
  try {
    await ref.read(tradePurchasesListProvider.future);
  } catch (_) {}
  if (context.mounted) {
    showTopSnack(context, 'Stock added to warehouse');
  }
  return true;
}

/// Owner commit from purchase list / quick actions — preflight + single in-flight guard.
Future<void> commitPurchaseStockFromList(
  BuildContext context,
  WidgetRef ref,
  TradePurchase purchase,
) async {
  if (!purchase.deliveryStatusEnum.readyForOwnerCommit) return;
  if (_commitStockInFlight.contains(purchase.id)) return;
  final session = ref.read(sessionProvider);
  if (session == null) return;

  var issues = await loadPurchaseStockCommitIssues(ref, purchase);
  if (issues.isNotEmpty) {
    if (!context.mounted) return;
    showTopSnack(
      context,
      'Unit setup needed before stock can be added.',
      isError: true,
      duration: const Duration(seconds: 5),
    );
    final fixed = await resolvePurchaseStockCommitUnitSetup(
      context,
      ref,
      purchase,
      issues,
    );
    if (!context.mounted) return;
    if (fixed) {
      issues = await loadPurchaseStockCommitIssues(ref, purchase);
    }
    if (issues.isNotEmpty) {
      await showPurchaseStockCommitBlockedDialog(
        context,
        ref,
        purchase,
        issues,
      );
      return;
    }
  }

  _commitStockInFlight.add(purchase.id);
  try {
    await _performCommitStock(context, ref, purchase);
  } catch (e) {
    if (!context.mounted) return;
    showTopSnack(
      context,
      e is DioException
          ? friendlyApiError(e)
          : 'Could not commit to stock. Try again.',
      isError: true,
      duration: const Duration(seconds: 6),
    );
    if (e is! DioException || e.response?.statusCode != 400) return;

    var retryIssues = _issuesFromCommitStock400(ref, purchase, e);
    if (retryIssues.isEmpty) {
      final detail =
          (fastApiDetailString(e.response?.data) ?? '').toLowerCase();
      if (detail.contains('no stock was added') ||
          detail.contains('unit setup')) {
        retryIssues = await loadPurchaseStockCommitIssues(ref, purchase);
      }
    }
    if (retryIssues.isEmpty || !context.mounted) return;

    final fixed = await resolvePurchaseStockCommitUnitSetup(
      context,
      ref,
      purchase,
      retryIssues,
    );
    if (!context.mounted) return;
    if (!fixed) {
      await showPurchaseStockCommitBlockedDialog(
        context,
        ref,
        purchase,
        retryIssues,
      );
      return;
    }

    final afterFix = await loadPurchaseStockCommitIssues(ref, purchase);
    if (afterFix.isNotEmpty || !context.mounted) {
      if (afterFix.isNotEmpty) {
        await showPurchaseStockCommitBlockedDialog(
          context,
          ref,
          purchase,
          afterFix,
        );
      }
      return;
    }

    try {
      await _performCommitStock(context, ref, purchase);
    } catch (retryErr) {
      if (!context.mounted) return;
      showTopSnack(
        context,
        retryErr is DioException
            ? friendlyApiError(retryErr)
            : 'Could not commit to stock. Try again.',
        isError: true,
        duration: const Duration(seconds: 6),
      );
    }
  } finally {
    _commitStockInFlight.remove(purchase.id);
  }
}

/// Shared commit implementation for purchase detail (after confirm dialog).
Future<void> commitPurchaseStockAfterConfirm(
  BuildContext context,
  WidgetRef ref,
  TradePurchase purchase,
) async {
  if (_commitStockInFlight.contains(purchase.id)) return;
  _commitStockInFlight.add(purchase.id);
  try {
    await _performCommitStock(context, ref, purchase);
  } catch (e) {
    if (!context.mounted) return;
    showTopSnack(
      context,
      e is DioException
          ? friendlyApiError(e)
          : 'Could not commit to stock. Try again.',
      isError: true,
      duration: const Duration(seconds: 6),
    );
    if (e is! DioException || e.response?.statusCode != 400) return;

    var retryIssues = _issuesFromCommitStock400(ref, purchase, e);
    if (retryIssues.isEmpty) {
      retryIssues = await loadPurchaseStockCommitIssues(ref, purchase);
    }
    if (retryIssues.isEmpty || !context.mounted) return;

    final fixed = await resolvePurchaseStockCommitUnitSetup(
      context,
      ref,
      purchase,
      retryIssues,
    );
    if (!context.mounted || !fixed) {
      if (context.mounted) {
        await showPurchaseStockCommitBlockedDialog(
          context,
          ref,
          purchase,
          retryIssues,
        );
      }
      return;
    }

    final afterFix = await loadPurchaseStockCommitIssues(ref, purchase);
    if (afterFix.isNotEmpty) {
      if (context.mounted) {
        await showPurchaseStockCommitBlockedDialog(
          context,
          ref,
          purchase,
          afterFix,
        );
      }
      return;
    }

    try {
      await _performCommitStock(context, ref, purchase);
    } catch (retryErr) {
      if (!context.mounted) return;
      showTopSnack(
        context,
        retryErr is DioException
            ? friendlyApiError(retryErr)
            : 'Could not commit to stock. Try again.',
        isError: true,
      );
    }
  } finally {
    _commitStockInFlight.remove(purchase.id);
  }
}
