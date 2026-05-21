import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

/// Direct App Store / Google Play purchases (no RevenueCat).
class StorePurchaseService {
  StorePurchaseService._();

  static final StorePurchaseService instance = StorePurchaseService._();

  final InAppPurchase _iap = InAppPurchase.instance;
  final Map<String, ProductDetails> _products = {};
  bool? _available;

  static bool get isSupported =>
      !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  static String get storeName {
    if (Platform.isIOS) return 'App Store';
    if (Platform.isAndroid) return 'Google Play';
    return 'App Store';
  }

  Future<bool> ensureAvailable() async {
    if (!isSupported) return false;
    _available = await _iap.isAvailable();
    return _available == true;
  }

  Future<void> loadProducts(Set<String> productIds) async {
    if (productIds.isEmpty) return;
    final response = await _iap.queryProductDetails(productIds);
    if (response.error != null) {
      throw Exception(response.error!.message);
    }
    if (response.notFoundIDs.isNotEmpty) {
      throw Exception(
        'Products not found in ${storeName}: ${response.notFoundIDs.join(", ")}. '
        'Create subscriptions in App Store Connect / Play Console with these IDs.',
      );
    }
    _products
      ..clear()
      ..addEntries(response.productDetails.map((p) => MapEntry(p.id, p)));
  }

  ProductDetails? productDetails(String productId) => _products[productId];

  /// Buy a subscription / non-consumable by store product id.
  Future<StorePurchaseResult> purchaseProductId(String productId) async {
    if (!isSupported) {
      return const StorePurchaseResult(
        success: false,
        error: 'In-app purchase is only available on iOS and Android.',
      );
    }
    if (!await ensureAvailable()) {
      return StorePurchaseResult(
        success: false,
        error: '${storeName} billing is not available on this device.',
      );
    }

    if (!_products.containsKey(productId)) {
      await loadProducts({productId});
    }
    final details = _products[productId];
    if (details == null) {
      return StorePurchaseResult(
        success: false,
        error: 'Product $productId is not available in ${storeName}.',
      );
    }

    final completer = Completer<PurchaseDetails?>();
    late final StreamSubscription<List<PurchaseDetails>> sub;
    sub = _iap.purchaseStream.listen((purchases) async {
      for (final purchase in purchases) {
        if (purchase.productID != productId) continue;
        switch (purchase.status) {
          case PurchaseStatus.purchased:
          case PurchaseStatus.restored:
            if (!completer.isCompleted) completer.complete(purchase);
            break;
          case PurchaseStatus.error:
            if (!completer.isCompleted) {
              completer.completeError(
                Exception(purchase.error?.message ?? 'Purchase failed'),
              );
            }
            break;
          case PurchaseStatus.pending:
            break;
          case PurchaseStatus.canceled:
            if (!completer.isCompleted) {
              completer.completeError(Exception('Purchase canceled'));
            }
            break;
        }
        if (purchase.pendingCompletePurchase) {
          await _iap.completePurchase(purchase);
        }
      }
    });

    try {
      final param = PurchaseParam(productDetails: details);
      final started = await _iap.buyNonConsumable(purchaseParam: param);
      if (!started) {
        return const StorePurchaseResult(
          success: false,
          error: 'Could not start purchase',
        );
      }
      final purchase = await completer.future.timeout(
        const Duration(minutes: 5),
        onTimeout: () => throw TimeoutException('Purchase timed out'),
      );
      if (purchase == null) {
        return const StorePurchaseResult(success: false, error: 'No purchase returned');
      }
      return StorePurchaseResult(
        success: true,
        productId: purchase.productID,
        purchaseId: purchase.purchaseID ?? '',
        verificationData: purchase.verificationData.serverVerificationData,
        localVerificationData: purchase.verificationData.localVerificationData,
        transactionDate: purchase.transactionDate,
      );
    } on Exception catch (e) {
      return StorePurchaseResult(success: false, error: e.toString());
    } finally {
      await sub.cancel();
    }
  }

  /// Restore prior App Store / Play subscriptions.
  Future<List<StorePurchaseResult>> restorePurchases() async {
    if (!isSupported || !await ensureAvailable()) return [];
    final results = <StorePurchaseResult>[];
    final completer = Completer<void>();
    late final StreamSubscription<List<PurchaseDetails>> sub;
    var idleTimer = Timer(const Duration(seconds: 8), () {
      if (!completer.isCompleted) completer.complete();
    });

    sub = _iap.purchaseStream.listen((purchases) async {
      idleTimer.cancel();
      idleTimer = Timer(const Duration(seconds: 3), () {
        if (!completer.isCompleted) completer.complete();
      });
      for (final purchase in purchases) {
        if (purchase.status != PurchaseStatus.purchased &&
            purchase.status != PurchaseStatus.restored) {
          continue;
        }
        results.add(
          StorePurchaseResult(
            success: true,
            productId: purchase.productID,
            purchaseId: purchase.purchaseID ?? '',
            verificationData: purchase.verificationData.serverVerificationData,
            localVerificationData: purchase.verificationData.localVerificationData,
            transactionDate: purchase.transactionDate,
          ),
        );
        if (purchase.pendingCompletePurchase) {
          await _iap.completePurchase(purchase);
        }
      }
    });

    try {
      await _iap.restorePurchases();
      await completer.future;
    } finally {
      idleTimer.cancel();
      await sub.cancel();
    }
    return results;
  }
}

class StorePurchaseResult {
  const StorePurchaseResult({
    required this.success,
    this.error,
    this.productId = '',
    this.purchaseId = '',
    this.verificationData = '',
    this.localVerificationData = '',
    this.transactionDate,
  });

  final bool success;
  final String? error;
  final String productId;
  final String purchaseId;
  final String verificationData;
  final String localVerificationData;
  final String? transactionDate;
}
