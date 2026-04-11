import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/subscription_service.dart';

class LockedFeatureWidget extends StatelessWidget {
  final Widget child;
  final String featureName;

  const LockedFeatureWidget({
    super.key,
    required this.child,
    required this.featureName,
  });

  @override
  Widget build(BuildContext context) {
    // Access policy update: once users are inside the app, feature tabs should
    // not be hard-locked by subscription overlays.
    return child;
  }
}
