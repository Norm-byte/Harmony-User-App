import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';

class SubscriptionService extends ChangeNotifier {
  static final SubscriptionService _instance = SubscriptionService._internal();
  factory SubscriptionService() => _instance;
  SubscriptionService._internal();

  bool _isSubscribed = false;
  bool get isSubscribed => _isSubscribed;

  CustomerInfo? _customerInfo;
  CustomerInfo? get customerInfo => _customerInfo;
  
  Offerings? _offerings;
  Offerings? get offerings => _offerings;

  // Configuration
  final String _apiKey = 'test_VNgSNIfuNujYsdVozVnbGQaadOn'; 
  final String _entitlementId = 'Harmony by Intent Pro';

  Future<void> init() async {
    await Purchases.setLogLevel(LogLevel.debug);

    PurchasesConfiguration configuration;
    if (Platform.isAndroid) {
      configuration = PurchasesConfiguration(_apiKey);
    } else if (Platform.isIOS) {
      configuration = PurchasesConfiguration(_apiKey);
    } else {
        // Fallback or specific key for other platforms if needed
        return;
    }

    try {
      await Purchases.configure(configuration);
      // Listen to customer info updates
      Purchases.addCustomerInfoUpdateListener((customerInfo) {
        _updateSubscriptionStatus(customerInfo);
      });

      await _checkSubscriptionStatus();
      await _fetchOfferings();
    } catch (e) {
      debugPrint('Error initializing RevenueCat: $e');
    }
  }

  Future<void> _checkSubscriptionStatus() async {
    try {
      _customerInfo = await Purchases.getCustomerInfo();
      _updateSubscriptionStatus(_customerInfo);
    } catch (e) {
      debugPrint('Error checking subscription status: $e');
    }
  }

  void _updateSubscriptionStatus(CustomerInfo? customerInfo) {
    if (customerInfo == null) return;
    _customerInfo = customerInfo;
    
    final entitlement = customerInfo.entitlements.all[_entitlementId];
    _isSubscribed = entitlement?.isActive ?? false;
    
    notifyListeners();
  }

  Future<void> _fetchOfferings() async {
    try {
      _offerings = await Purchases.getOfferings();
      if (_offerings?.current == null) {
        debugPrint('HARMONY_RC: No current offering found. Check RevenueCat Dashboard > Offerings.');
      } else {
        debugPrint('HARMONY_RC: Found offering: ${_offerings!.current!.identifier}');
        debugPrint('HARMONY_RC: Available packages: ${_offerings!.current!.availablePackages.length}');
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error fetching offerings: $e');
    }
  }

  Future<bool> purchasePackage(Package package) async {
    try {
      // purchasePackage returns PurchaseResult in newer versions, which wraps customerInfo
      var result = await Purchases.purchasePackage(package);
      // We access the customerInfo property from the result
      _updateSubscriptionStatus(result.customerInfo);
      return _isSubscribed;
    } on PlatformException catch (e) {
      var errorCode = PurchasesErrorHelper.getErrorCode(e);
      if (errorCode != PurchasesErrorCode.purchaseCancelledError) {
        debugPrint('Error purchasing package: $e');
      }
      return false;
    }
  }

  Future<bool> restorePurchases() async {
    try {
      CustomerInfo customerInfo = await Purchases.restorePurchases();
      _updateSubscriptionStatus(customerInfo);
      return _isSubscribed;
    } catch (e) {
      debugPrint('Error restoring purchases: $e');
      return false;
    }
  }
  
  /// Presents the Paywall to the user. 
  /// Returns [true] if the user purchased or restored a subscription (is subscribed).
  /// Returns [false] if they closed the paywall without subscribing.
  Future<bool> showPaywall() async {
    try {
      // Ensure offerings are loaded
      if (_offerings == null || _offerings!.current == null) {
         debugPrint("HARMONY_RC: Offerings missing, fetching now...");
         await _fetchOfferings();
      }
      
      if (_offerings?.current == null) {
        // Throwing here allows the UI to catch it and show a SnackBar
        throw PlatformException(
          code: 'NO_OFFERINGS', 
          message: 'No subscription offerings found. Please check configuration.'
        );
      }

      // Check for available packages in the current offering
      if (_offerings!.current!.availablePackages.isEmpty) {
         throw PlatformException(
          code: 'NO_PACKAGES', 
          message: 'Offering has no packages available.'
        );
      }
      
      // Explicitly pass the offering to ensure the UI knows what to show
      final paywallResult = await RevenueCatUI.presentPaywall(
        offering: _offerings!.current
      );
      
      if (paywallResult == PaywallResult.purchased || paywallResult == PaywallResult.restored) {
        await _checkSubscriptionStatus(); 
        return true;
      }
      
      return _isSubscribed;
      
    } catch (e) {
      debugPrint("Error displaying paywall: $e");
      // Rethrow so the UI knows something went wrong
      rethrow;
    }
  }

  /// Presents the Customer Center
  Future<void> showCustomerCenter() async {
    try {
       await RevenueCatUI.presentCustomerCenter();
    } catch (e) {
       debugPrint("Error showing customer center: $e");
    }
  }
}
