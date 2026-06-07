import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/fastapi_error.dart';
import '../auth/auth_error_messages.dart';
import '../auth/session_notifier.dart';
import '../models/trade_purchase_models.dart';
import '../providers/business_aggregates_invalidation.dart';
import '../providers/catalog_providers.dart';
import '../providers/trade_purchases_provider.dart';
import '../utils/snack.dart';
import '../router/navigation_ext.dart';
import 'purchase_stock_commit_preflight.dart';

final _commitStockInFlight = <String>{};

List<Map<String, dynamic>> catalogRowsForCommitPreflight(WidgetRef ref) {
  return ref.read(catalogItemsListProvider).valueOrNull ?? const [];
}

List<PurchaseStockCommitIssue> purchaseStockCommitIssues(
  WidgetRef ref,
  TradePurchase purchase,
) {
  return findPurchaseStockCommitIssues(
    purchase,
    catalogRowsForCommitPreflight(ref),
  );
}

Future<void> showPurchaseStockCommitBlockedDialog(
  BuildContext context,
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
          if (firstCatalogId != null)
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

  final issues = purchaseStockCommitIssues(ref, purchase);
  if (issues.isNotEmpty) {
    if (context.mounted) {
      showTopSnack(
        context,
        'Unit setup needed before stock can be added.',
        isError: true,
        duration: const Duration(seconds: 5),
      );
      await showPurchaseStockCommitBlockedDialog(context, purchase, issues);
    }
    return;
  }

  _commitStockInFlight.add(purchase.id);
  try {
    final updated = await ref.read(hexaApiProvider).commitPurchaseDelivery(
          businessId: session.primaryBusiness.id,
          purchaseId: purchase.id,
        );
    syncPurchaseStockFromPurchaseJson(
      ref,
      purchaseId: purchase.id,
      body: updated,
    );
    try {
      await ref.read(tradePurchasesListProvider.future);
    } catch (_) {}
    if (context.mounted) {
      showTopSnack(context, 'Stock added to warehouse');
    }
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
    if (e is DioException && e.response?.statusCode == 400) {
      final detail =
          (fastApiDetailString(e.response?.data) ?? '').toLowerCase();
      if (detail.contains('no stock was added') ||
          detail.contains('unit setup')) {
        final retryIssues = purchaseStockCommitIssues(ref, purchase);
        if (retryIssues.isNotEmpty && context.mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (!context.mounted) return;
            await showPurchaseStockCommitBlockedDialog(
              context,
              purchase,
              retryIssues,
            );
          });
        }
      }
    }
  } finally {
    _commitStockInFlight.remove(purchase.id);
  }
}
