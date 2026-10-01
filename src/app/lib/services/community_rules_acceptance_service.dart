import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'user_service.dart';

/// Stores Poetry-specific rules acceptance separately from profile data.
class CommunityRulesAcceptanceService {
  CommunityRulesAcceptanceService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    String? Function()? authUidProvider,
    String Function()? localUserIdProvider,
  }) : _firestore = firestore,
       _auth = auth,
       _authUidProvider = authUidProvider,
       _localUserIdProvider = localUserIdProvider;

  final FirebaseFirestore? _firestore;
  final FirebaseAuth? _auth;
  final String? Function()? _authUidProvider;
  final String Function()? _localUserIdProvider;

  static bool isCurrentVersionAccepted(String? acceptedVersion, String currentVersion) =>
      currentVersion.trim().isNotEmpty && acceptedVersion == currentVersion.trim();

  String get _localKey {
    final localUserId =
        (_localUserIdProvider?.call() ?? UserService().userId).trim();
    return 'community_rules_accepted_v1_$localUserId';
  }

  DocumentReference<Map<String, dynamic>>? get _accountAcceptance {
    final suppliedUid = _authUidProvider == null
        ? (_auth ?? FirebaseAuth.instance).currentUser?.uid
        : _authUidProvider();
    final uid = suppliedUid?.trim() ?? '';
    if (uid.isEmpty) return null;
    return (_firestore ?? FirebaseFirestore.instance)
        .collection('community_rules_acceptances')
        .doc(uid);
  }

  Future<bool> hasAccepted(String rulesVersion) async {
    final version = rulesVersion.trim();
    if (version.isEmpty) return false;
    final accountAcceptance = _accountAcceptance;
    if (accountAcceptance != null) {
      final snapshot = await accountAcceptance.get();
      return isCurrentVersionAccepted(
        snapshot.data()?['rulesVersion']?.toString(),
        version,
      );
    }
    final preferences = await SharedPreferences.getInstance();
    return isCurrentVersionAccepted(preferences.getString(_localKey), version);
  }

  Future<void> recordAcceptance(String rulesVersion) async {
    final version = rulesVersion.trim();
    if (version.isEmpty) {
      throw ArgumentError.value(rulesVersion, 'rulesVersion', 'Must not be empty.');
    }
    final accountAcceptance = _accountAcceptance;
    if (accountAcceptance != null) {
      await accountAcceptance.set({
        'rulesVersion': version,
        'acceptedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return;
    }
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_localKey, version);
    await preferences.setInt(
      '${_localKey}_accepted_at',
      DateTime.now().millisecondsSinceEpoch,
    );
  }
}
