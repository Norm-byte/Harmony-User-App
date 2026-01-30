import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SubscriptionService extends ChangeNotifier {
  static final SubscriptionService _instance = SubscriptionService._internal();
  factory SubscriptionService() => _instance;
  SubscriptionService._internal();

  bool _isSubscribed = false;
  bool _isVipOverride = false; // Add VIP Override

  bool get isSubscribed {
    return _isSubscribed || _isVipOverride; 
  }

  // Prevent disposal of the singleton instance
  @override
  void dispose() {
    // Do nothing. This is a singleton.
  }

  CustomerInfo? _customerInfo;
  CustomerInfo? get customerInfo => _customerInfo;
  
  Offerings? _offerings;
  Offerings? get offerings => _offerings;

  // Configuration
  final String _apiKey = 'test_VNgSNIfuNujYsdVozVnbGQaadOn'; 
  final String _entitlementId = 'Harmony by Intent Pro';

  Future<void> init() async {
    await Purchases.setLogLevel(LogLevel.debug);

    // Resume VIP status
    try {
      final prefs = await SharedPreferences.getInstance();
      _isVipOverride = prefs.getBool('is_vip_override') ?? false;
      debugPrint("HARMONY_VIP_INIT: Loaded VIP Status from Disk: $_isVipOverride");
    } catch (e) {
      debugPrint("HARMONY_VIP_ERROR: Could not load prefs: $e");
    }
    notifyListeners();
    
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

  Future<void> setVipStatus(bool status) async {
    debugPrint("HARMONY_VIP_SET: Setting VIP status to $status");
    _isVipOverride = status;
    notifyListeners();
    
    // Persist
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_vip_override', status);
      debugPrint("HARMONY_VIP_SAVED: VIP status saved to disk.");
    } catch (e) {
      debugPrint("HARMONY_VIP_SAVE_ERROR: $e");
    }

    // Re-sync with correct status
    if (_customerInfo != null) {
       _syncBillingStatus(_customerInfo!);
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
    
    // Sync critical billing info to Firestore for Admin Visibility
    _syncBillingStatus(customerInfo);

    notifyListeners();
  }

  Future<void> _syncBillingStatus(CustomerInfo info) async {
    try {
      final entitlement = info.entitlements.all[_entitlementId];
      final willRenew = entitlement?.willRenew ?? false;
      final expirationDate = entitlement?.expirationDate;
      
      final userId = info.originalAppUserId;
      if (userId.isNotEmpty) {
          await FirebaseFirestore.instance.collection('users').doc(userId).set({
            'willRenew': _isVipOverride ? true : willRenew, // VIP always renews
            'subscriptionPlan': (_isSubscribed || _isVipOverride) ? 'Premium' : 'Free', // True status
            'renewalDate': _isVipOverride ? DateTime.now().add(const Duration(days: 3650)) : expirationDate, // VIP = 10 years
            'status': (_isSubscribed || _isVipOverride) ? 'active' : 'trial', // Simplified status logic
            'isVip': _isVipOverride,
          }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint("Error syncing billing status: $e");
    }
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
      var result = await Purchases.purchasePackage(package);
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
  
  Future<bool> showPaywall() async {
    try {
      if (_offerings == null || _offerings!.current == null) {
         debugPrint("HARMONY_RC: Offerings missing, fetching now...");
         await _fetchOfferings();
      }
      
      if (_offerings?.current == null) {
        throw PlatformException(
          code: 'NO_OFFERINGS', 
          message: 'No subscription offerings found. Please check configuration.'
        );
      }

      if (_offerings!.current!.availablePackages.isEmpty) {
         throw PlatformException(
          code: 'NO_PACKAGES', 
          message: 'Offering has no packages available.'
        );
      }
      
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
      rethrow;
    }
  }

  Future<void> showCustomerCenter() async {
    try {
       await RevenueCatUI.presentCustomerCenter();
    } catch (e) {
       debugPrint("Error showing customer center: $e");
    }
  }
}
