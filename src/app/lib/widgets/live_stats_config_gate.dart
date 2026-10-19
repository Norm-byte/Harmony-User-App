import 'dart:async';
import 'package:flutter/material.dart';

class LiveStatsConfigGate extends StatefulWidget {
  final Stream<Map<String, dynamic>?> settings;
  final Widget Function(BuildContext, Map<String, dynamic>) builder;
  final void Function(Object)? onError;

  const LiveStatsConfigGate({
    super.key,
    required this.settings,
    required this.builder,
    this.onError,
  });

  @override
  State<LiveStatsConfigGate> createState() => _LiveStatsConfigGateState();
}

class _LiveStatsConfigGateState extends State<LiveStatsConfigGate> {
  StreamSubscription<Map<String, dynamic>?>? _subscription;
  Map<String, dynamic>? _lastSettings;

  void _listen() {
    _subscription = widget.settings.listen((settings) {
      if (!mounted || settings == null) return;
      setState(() => _lastSettings = settings);
    }, onError: (Object error) => widget.onError?.call(error));
  }

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(covariant LiveStatsConfigGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings != widget.settings) {
      _subscription?.cancel();
      _listen();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = _lastSettings;
    if (settings == null) {
      return const Align(
        alignment: Alignment.bottomLeft,
        child: Text('Connecting live stats…', style: TextStyle(color: Colors.white70, fontSize: 11)),
      );
    }
    if (settings['showLiveStats'] != true) return const SizedBox.shrink();
    return widget.builder(context, settings);
  }
}