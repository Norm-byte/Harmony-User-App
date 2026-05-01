import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/models/customer_info_wrapper.dart';
import 'subscription_service.dart';

class UsageService extends ChangeNotifier {
  final SubscriptionService _subscriptionService;
  
  // Default Limits (Fallback)
  static const int _defaultMaxDailySends = 5;
  static const int _defaultMaxActiveForums = 2;
  static const int _defaultMaxMediaStorageMb = 100;
  static const bool _defaultAllowVideoUploads = false;

  int _maxDailySends = _defaultMaxDailySends;
  int _maxActiveForums = _defaultMaxActiveForums;
  int _maxMediaStorageMb = _defaultMaxMediaStorageMb;
  bool _allowVideoUploads = _defaultAllowVideoUploads;

  StreamSubscription? _tiersSubscription;
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userDocSubscription;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _latestDocs = [];
  Map<String, dynamic>? _currentUserData;

  UsageService(this._subscriptionService) {
    _init();
  }

  int get maxDailySends => _maxDailySends;
  int get maxActiveForums => _maxActiveForums;
  int get maxMediaStorageMb => _maxMediaStorageMb;
  bool get allowVideoUploads => _allowVideoUploads;

  @override
  void dispose() {
    _tiersSubscription?.cancel();
    _authSubscription?.cancel();
    _userDocSubscription?.cancel();
    _subscriptionService.removeListener(_evaluateLimits);
    super.dispose();
  }

  void _init() {
    _subscriptionService.addListener(_evaluateLimits);

    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      _bindUserDocListener(user?.uid);
    });
    _bindUserDocListener(FirebaseAuth.instance.currentUser?.uid);
    
    // Listen to real-time changes in Product Tiers
    _tiersSubscription = FirebaseFirestore.instance
        .collection('product_tiers')
        .snapshots()
        .listen((snapshot) {
      _latestDocs = snapshot.docs;
      _evaluateLimits();
    }, onError: (e) {
      debugPrint("Error listening to product_tiers: $e");
    });
  }

  void _bindUserDocListener(String? uid) {
    _userDocSubscription?.cancel();
    if (uid == null || uid.isEmpty) {
      _currentUserData = null;
      _evaluateLimits();
      return;
    }

    _userDocSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((doc) {
      _currentUserData = doc.data();
      _evaluateLimits();
    }, onError: (e) {
      debugPrint('Error listening to users/$uid for quota overrides: $e');
    });
  }

  void _evaluateLimits() {
    try {
      if (_latestDocs.isEmpty) {
        // If we haven't received data yet, we might want to wait or keep defaults.
        // But usually snapshots emit immediately.
        // We can just return and wait for the first snapshot.
        // Or check if we should fetch once? The listener handles it.
        return;
      }

      // Convert to map for lookup
      final tierDocs = { for (var doc in _latestDocs) doc.id : doc.data() };
      
      Map<String, dynamic> limitsToApply = {};
      bool limitsFound = false;
      final hasElevatedAccess =
          _subscriptionService.isVip || (_currentUserData?['isSuperAdmin'] == true);

      final vipQuotaTier = (_currentUserData?['vipQuotaTier'] as String?)
          ?.trim();
      if (hasElevatedAccess && vipQuotaTier != null && vipQuotaTier.isNotEmpty) {
        if (tierDocs.containsKey(vipQuotaTier)) {
          limitsToApply = tierDocs[vipQuotaTier]?['limits'] ?? {};
          limitsFound = true;
        } else {
          for (var doc in _latestDocs) {
            final data = doc.data();
            if (data['revenueCatOfferingId'] == vipQuotaTier) {
              limitsToApply = data['limits'] ?? {};
              limitsFound = true;
              break;
            }
          }
        }
      }

      // Safety fallback: VIP users without a mapped tier should never drop to free limits.
      if (!limitsFound && hasElevatedAccess) {
        limitsToApply = {
          'maxDailySends': 100,
          'maxMonthlySends': 3000,
          'maxActiveForums': 1,
        };
        limitsFound = true;
      }

      if (limitsFound && hasElevatedAccess) {
        final currentDaily = (limitsToApply['maxDailySends'] as num?)?.toInt() ?? 0;
        if (currentDaily < 100) {
          limitsToApply['maxDailySends'] = 100;
        }
        final currentMonthly = (limitsToApply['maxMonthlySends'] as num?)?.toInt() ?? 0;
        if (currentMonthly > 0 && currentMonthly < 3000) {
          limitsToApply['maxMonthlySends'] = 3000;
        }
      }

      // Logic to determine which Tier applies
      if (!limitsFound && !_subscriptionService.isSubscribed) {
        // CASE A: User is NOT subscribed -> Use 'tier_free' configuration
        if (tierDocs.containsKey('tier_free')) {
          limitsToApply = tierDocs['tier_free']?['limits'] ?? {};
          limitsFound = true;
        }
      } else if (!limitsFound) {
        // CASE B: User IS subscribed -> Find matching Tier based on RevenueCat Offering ID
        final customerInfo = _subscriptionService.customerInfo;
        
        if (customerInfo != null) {
          // Iterate through current docs
          for (var doc in _latestDocs) {
            final data = doc.data();
            final rcOfferingId = data['revenueCatOfferingId'] as String?;
            
            if (rcOfferingId != null &&
                rcOfferingId.isNotEmpty &&
                _matchesAnyConfiguredRevenueCatId(customerInfo, rcOfferingId)) {
              
              limitsToApply = data['limits'] ?? {};
              limitsFound = true;
              break; 
            }
          }
        }

        // Fallback: If subscribed but no RC match found
          if (!limitsFound && tierDocs.containsKey('tier_free')) {
           limitsToApply = tierDocs['tier_free']?['limits'] ?? {};
           limitsFound = true;
        }
      }

      if (limitsFound) {
        _applyLimitsFromMap(limitsToApply);
      } else {
        _setDefaults();
      }

    } catch (e) {
      debugPrint("Error evaluating usage limits: $e");
      _setDefaults();
    }
  }

  bool _matchesAnyConfiguredRevenueCatId(CustomerInfo info, String configuredIds) {
    final candidates = configuredIds
        .split(RegExp(r'[,|\s]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    for (final id in candidates) {
      if (_matchesRevenueCatId(info, id)) {
        return true;
      }
    }
    return false;
  }

  bool _matchesRevenueCatId(CustomerInfo info, String configuredId) {
    // Entitlement-based match (preferred)
    if (info.entitlements.all[configuredId]?.isActive == true) {
      return true;
    }

    // Product-based match (fallback if admin entered Store Product ID)
    if (info.activeSubscriptions.contains(configuredId)) {
      return true;
    }
    if (info.allPurchasedProductIdentifiers.contains(configuredId)) {
      return true;
    }

    return false;
  }

  void _setDefaults() {
    _maxDailySends = _defaultMaxDailySends;
    _maxActiveForums = _defaultMaxActiveForums;
    _maxMediaStorageMb = _defaultMaxMediaStorageMb;
    _allowVideoUploads = _defaultAllowVideoUploads;
    notifyListeners();
  }

  void _applyLimitsFromMap(Map<String, dynamic> limits) {
    // Prefer 'maxDailySends', support legacy 'maxMonthlySends'
    int newMaxDailySends = _defaultMaxDailySends;

    if (limits.containsKey('maxDailySends')) {
      newMaxDailySends = limits['maxDailySends'] as int;
    } else if (limits.containsKey('maxMonthlySends')) {
       newMaxDailySends = (limits['maxMonthlySends'] as int) ~/ 30; 
    }

    // Only notify if something changed
    if (_maxDailySends != newMaxDailySends) {
      _maxDailySends = newMaxDailySends;
    }
    
    if (limits.containsKey('maxActiveForums') && _maxActiveForums != limits['maxActiveForums']) {
      _maxActiveForums = limits['maxActiveForums'];
    }
    
    // ... ignoring others for brevity unless easy
    // Actually better to just set them and let notifyListeners handle it (if we optimized)
    // But basic check is fine.
    
    _maxMediaStorageMb = limits['maxMediaStorageMb'] ?? _defaultMaxMediaStorageMb;
    _allowVideoUploads = limits['allowVideoUploads'] ?? _defaultAllowVideoUploads;
    
    // Always notify if we are reapplying limits, UI might need refresh
    notifyListeners();
  }
}
