import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
  
  bool get isVip => _isVipOverride; // Expose VIP status

  // Prevent disposal of the singleton instance
  @override
  // ignore: must_call_super
  void dispose() {
    // Intentionally empty — this is a singleton that must not be disposed.
  }

  CustomerInfo? _customerInfo;
  CustomerInfo? get customerInfo => _customerInfo;
  
  Offerings? _offerings;
  Offerings? get offerings => _offerings;

  // Configuration
  final String _androidApiKey = const String.fromEnvironment(
    'RC_ANDROID_API_KEY',
    defaultValue: 'goog_ObzZGAhZOHyXwpOTXHfBhTWBvuo',
  );
  final String _iosApiKey = const String.fromEnvironment(
    'RC_IOS_API_KEY',
    defaultValue: '',
  );
  final String _starterEntitlement = 'starter_access';
  final String _unlimitedEntitlement = 'unlimited_access';

  Future<void> _syncVipFromFirestoreAuthUser() async {
    try {
      final firebaseUser = FirebaseAuth.instance.currentUser;
      if (firebaseUser == null) return;

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(firebaseUser.uid)
          .get();
      if (!doc.exists) return;

      final remoteVip = doc.data()?['isVip'] as bool?;
      if (remoteVip != null && remoteVip != _isVipOverride) {
        debugPrint(
          "HARMONY_VIP_SYNC: Updating local VIP to $remoteVip from Firestore auth user",
        );
        await setVipStatus(remoteVip);
      }
    } catch (e) {
      debugPrint("HARMONY_VIP_SYNC_ERROR: $e");
    }
  }

  Future<void> refreshVipFromAuthUser() async {
    await _syncVipFromFirestoreAuthUser();
  }

  Future<void> init() async {
    await Purchases.setLogLevel(LogLevel.debug);

    // Resume VIP status
    try {
      final prefs = await SharedPreferences.getInstance();
      _isVipOverride = prefs.getBool('is_vip_override') ?? false;

      // SYNC: Check Firestore for latest status using authenticated Firebase user.
      await _syncVipFromFirestoreAuthUser();

      debugPrint("HARMONY_VIP_INIT: Loaded VIP Status from Disk: $_isVipOverride");
    } catch (e) {
      debugPrint("HARMONY_VIP_ERROR: Could not load prefs: $e");
    }
    notifyListeners();

    String? selectedApiKey;
    if (Platform.isAndroid) {
      selectedApiKey = _androidApiKey;
    } else if (Platform.isIOS) {
      if (_iosApiKey.isEmpty || !_iosApiKey.startsWith('appl_')) {
        debugPrint(
          'HARMONY_RC: Missing/invalid iOS RevenueCat key. Set RC_IOS_API_KEY with an appl_ key to enable purchases.',
        );
        return;
      }
      selectedApiKey = _iosApiKey;
    } else {
      // Purchases plugin is only configured on mobile platforms.
      return;
    }

    final configuration = PurchasesConfiguration(selectedApiKey);

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
    if (!status) {
      debugPrint('HARMONY_VIP_SET_FALSE_STACK: ${StackTrace.current}');
    }
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

  // Public wrapper to force refresh
  Future<void> refreshSubscriptionStatus() async {
    await _checkSubscriptionStatus();
  }

  void _updateSubscriptionStatus(CustomerInfo? customerInfo) {
    if (customerInfo == null) return;
    _customerInfo = customerInfo;
    
    final starter = customerInfo.entitlements.all[_starterEntitlement];
    final unlimited = customerInfo.entitlements.all[_unlimitedEntitlement];
    
    _isSubscribed = (starter?.isActive ?? false) || (unlimited?.isActive ?? false);
    
    // Sync critical billing info to Firestore for Admin Visibility
    _syncBillingStatus(customerInfo);

    notifyListeners();
  }

  Future<void> _syncBillingStatus(CustomerInfo info) async {
    try {
      // Determine active plan
      EntitlementInfo? activeEntitlement;
      String planName = 'Free';
      
      if (info.entitlements.all[_unlimitedEntitlement]?.isActive == true) {
        activeEntitlement = info.entitlements.all[_unlimitedEntitlement];
        planName = 'Harmony 100';
      } else if (info.entitlements.all[_starterEntitlement]?.isActive == true) {
        activeEntitlement = info.entitlements.all[_starterEntitlement];
        planName = 'Starter';
      }
      
      final willRenew = activeEntitlement?.willRenew ?? false;
      final expirationDate = activeEntitlement?.expirationDate;
      
      final userId = info.originalAppUserId;
      if (userId.isNotEmpty) {
          await FirebaseFirestore.instance.collection('users').doc(userId).set({
            'willRenew': _isVipOverride ? true : willRenew, // VIP always renews
            'subscriptionPlan': (_isSubscribed || _isVipOverride) ? (_isVipOverride ? 'VIP' : planName) : 'Free', // True status
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
      final result = await Purchases.purchase(PurchaseParams.package(package));
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
          message: 'No subscription offerings found. Please check configuration.',
        );
      }

      if (_offerings!.current!.availablePackages.isEmpty) {
        throw PlatformException(
          code: 'NO_PACKAGES',
          message: 'Offering has no packages available.',
        );
      }

      final paywallResult = await RevenueCatUI.presentPaywall(
        offering: _offerings!.current,
      );

      if (paywallResult == PaywallResult.purchased ||
          paywallResult == PaywallResult.restored) {
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
