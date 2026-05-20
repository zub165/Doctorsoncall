import 'package:purchases_flutter/purchases_flutter.dart';

class RevenueCatService {
  static const String _apiKey = 'goog_REPLACE_WITH_YOUR_REVENUECAT_API_KEY';

  static RevenueCatService? _instance;
  CustomerInfo? _customerInfo;
  bool _isInitialized = false;

  RevenueCatService._();

  static RevenueCatService get instance {
    _instance ??= RevenueCatService._();
    return _instance!;
  }

  Future<void> initialize({String? userId}) async {
    if (_isInitialized) return;
    await Purchases.setLogLevel(LogLevel.debug);
    await Purchases.configure(PurchasesConfiguration(_apiKey));
    if (userId != null && userId.isNotEmpty) {
      await Purchases.logIn(userId);
    }
    _customerInfo = await Purchases.getCustomerInfo();
    _isInitialized = true;
  }

  Future<void> setUserId(String userId) async {
    await Purchases.logIn(userId);
    _customerInfo = await Purchases.getCustomerInfo();
  }

  Future<List<Package>> getPackages() async {
    final offerings = await Purchases.getOfferings();
    final current = offerings.current;
    if (current == null) return [];
    return current.availablePackages;
  }

  Future<RevenueCatPurchaseResult> purchasePackage(Package package) async {
    try {
      final result = await Purchases.purchase(PurchaseParams.package(package));
      _customerInfo = result.customerInfo;
      return RevenueCatPurchaseResult(
        success: true,
        customerInfo: result.customerInfo,
        transactionIdentifier: result.storeTransaction.transactionIdentifier,
      );
    } on PurchasesError catch (e) {
      return RevenueCatPurchaseResult(
        success: false,
        error: e.message,
      );
    }
  }

  Future<void> restorePurchases() async {
    _customerInfo = await Purchases.restorePurchases();
  }

  Future<bool> checkEntitlement(String entitlementId) async {
    final info = _customerInfo ?? await Purchases.getCustomerInfo();
    return info.entitlements.all[entitlementId]?.isActive == true;
  }

  Future<List<String>> getActiveEntitlements() async {
    final info = _customerInfo ?? await Purchases.getCustomerInfo();
    return info.entitlements.all.values
        .where((e) => e.isActive)
        .map((e) => e.identifier)
        .toList();
  }

  Future<void> logout() async {
    await Purchases.logOut();
    _customerInfo = null;
  }
}

class RevenueCatPurchaseResult {
  final bool success;
  final CustomerInfo? customerInfo;
  final String? transactionIdentifier;
  final String? error;

  RevenueCatPurchaseResult({
    required this.success,
    this.customerInfo,
    this.transactionIdentifier,
    this.error,
  });
}
