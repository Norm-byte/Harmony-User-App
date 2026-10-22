import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import '../firebase_options.dart';

class IosFirestoreClient {
  IosFirestoreClient._();

  static final instance = IosFirestoreClient._();
  Future<FirebaseFirestore>? _counterClientFuture;

  Future<FirebaseFirestore> counterClient() {
    if (!Platform.isIOS) return Future.value(FirebaseFirestore.instance);
    return _counterClientFuture ??= _createCounterClient();
  }

  Future<FirebaseFirestore> _createCounterClient() async {
    const appName = 'HarmonyLiveCounterReadOnly';
    final app = Firebase.apps.any((item) => item.name == appName)
        ? Firebase.app(appName)
        : await Firebase.initializeApp(
            name: appName,
            options: DefaultFirebaseOptions.ios,
          ).timeout(const Duration(seconds: 8));
    final firestore = FirebaseFirestore.instanceFor(app: app);
    firestore.settings = const Settings(persistenceEnabled: false);
    return firestore;
  }
}