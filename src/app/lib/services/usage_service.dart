import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'subscription_service.dart';

class UsageService extends ChangeNotifier {
  final SubscriptionService _subscriptionService;
  
  // Default Limits (Free Tier)
  static const int _defaultMaxMonthlySends = 50;
  static const int _defaultMaxActiveForums = 2;
  static const int _defaultMaxMediaStorageMb = 100;
  static const bool _defaultAllowVideoUploads = false;

  int _maxMonthlySends = _defaultMaxMonthlySends;
  int _maxActiveForums = _defaultMaxActiveForums;
  int _maxMediaStorageMb = _defaultMaxMediaStorageMb;
  bool _allowVideoUploads = _defaultAllowVideoUploads;

  UsageService(this._subscriptionService) {
    _init();
  }

  int get maxMonthlySends => _maxMonthlySends;
  int get maxActiveForums => _maxActiveForums;
  int get maxMediaStorageMb => _maxMediaStorageMb;
  bool get allowVideoUploads => _allowVideoUploads;

  void _init() {
    _subscriptionService.addListener(_updateLimits);
    _updateLimits(); // Initial check
  }

  Future<void> _updateLimits() async {
    // 1. If not subscribed, use defaults
    if (!_subscriptionService.isSubscribed) {
      _setDefaults();
      return;
    }

    // 2. If subscribed, find the matching offer in Firestore
    final customerInfo = _subscriptionService.customerInfo;
    if (customerInfo == null) {
      _setDefaults();
      return;
    }
    
    // Check active entitlements to find the product/offering ID
    // Note: This logic depends on how RevenueCat maps entitlements.
    // simpler approach: fetch ALL active offers from Firestore and match against entitlements
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('monetization_offers')
          .where('isActive', isEqualTo: true)
          .get();

      bool foundMatch = false;

      // Iterate through our defined offers to see if the user has a matching active entitlement
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final rcOfferingId = data['revenueCatOfferingId'] as String?;
        
        // We assume the Entitlement ID or Product Identifier might match or be related.
        // For simplicity in this v2 phase, we'll assume if they have ANY active entitlement
        // and we find a matching limit config for "Standard" or "Premium", we use it.
        // A more robust way is to store the 'tier' in the User object or check specific entitlement names.
        
        // CHECK: Does the user have an entitlement that matches this offer's logic?
        // For now, we will perform a simple check: 
        // If the user is subscribed, we look for the "Premium" offer in Firestore.
        if (rcOfferingId != null && customerInfo.entitlements.all[rcOfferingId]?.isActive == true) {
             _applyLimitsFromMap(data['limits'] ?? {});
             foundMatch = true;
             break;
        }
      }

      // Fallback: If subscribed but no specific match found (e.g. legacy), apply a generous default?
      // Or just keep free tier? Let's keep free tier to be safe, or a "Generic Premium" if you prefer.
      if (!foundMatch) {
         // Try to find a 'default' premium offer or just stick to defaults
         _setDefaults(); 
      }

    } catch (e) {
      debugPrint("Error fetching usage limits: $e");
      _setDefaults();
    }
  }

  void _setDefaults() {
    _maxMonthlySends = _defaultMaxMonthlySends;
    _maxActiveForums = _defaultMaxActiveForums;
    _maxMediaStorageMb = _defaultMaxMediaStorageMb;
    _allowVideoUploads = _defaultAllowVideoUploads;
    notifyListeners();
  }

  void _applyLimitsFromMap(Map<String, dynamic> limits) {
    _maxMonthlySends = limits['maxMonthlySends'] ?? _defaultMaxMonthlySends;
    _maxActiveForums = limits['maxActiveForums'] ?? _defaultMaxActiveForums;
    _maxMediaStorageMb = limits['maxMediaStorageMb'] ?? _defaultMaxMediaStorageMb;
    _allowVideoUploads = limits['allowVideoUploads'] ?? _defaultAllowVideoUploads;
    notifyListeners();
  }
}
