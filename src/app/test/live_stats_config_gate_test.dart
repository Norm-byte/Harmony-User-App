import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmony_user_app/widgets/live_stats_config_gate.dart';

void main() {
  testWidgets('unknown settings are connecting, not off or a false zero', (tester) async {
    final settings = StreamController<Map<String, dynamic>?>(sync: true);
    await tester.pumpWidget(MaterialApp(home: LiveStatsConfigGate(
      settings: settings.stream,
      builder: (_, data) => const Text('5 live viewers'),
    )));
    expect(find.text('Connecting live stats…'), findsOneWidget);
    settings.addError(StateError('Disconnected'));
    await tester.pump();
    expect(find.text('Connecting live stats…'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    unawaited(settings.close());
  });

  testWidgets('last good visibility survives errors and missing data; explicit off is honoured', (tester) async {
    final settings = StreamController<Map<String, dynamic>?>(sync: true);
    final errors = <Object>[];
    await tester.pumpWidget(MaterialApp(home: LiveStatsConfigGate(
      settings: settings.stream,
      onError: errors.add,
      builder: (_, data) => const Text('5 live viewers'),
    )));
    settings.add({'showLiveStats': true});
    await tester.pump();
    expect(find.text('5 live viewers'), findsOneWidget);
    settings.addError(StateError('Network failure'));
    settings.add(null);
    await tester.pump();
    expect(errors, hasLength(1));
    expect(find.text('5 live viewers'), findsOneWidget);
    settings.add({'showLiveStats': false});
    await tester.pump();
    expect(find.text('5 live viewers'), findsNothing);
    settings.addError(StateError('Still offline'));
    await tester.pump();
    expect(find.text('5 live viewers'), findsNothing);
    settings.add({'showLiveStats': true});
    await tester.pump();
    expect(find.text('5 live viewers'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    unawaited(settings.close());
  });

  testWidgets('repeated refresh rebuilds keep one settings subscription and dispose cancels it', (tester) async {
    var listens = 0;
    var cancels = 0;
    final settings = StreamController<Map<String, dynamic>?>.broadcast(
      sync: true,
      onListen: () => listens++, onCancel: () => cancels++,
    );
    final stream = settings.stream;
    Widget screen(int viewers) => MaterialApp(home: LiveStatsConfigGate(
      settings: stream,
      builder: (_, data) => Text('$viewers live viewers'),
    ));
    await tester.pumpWidget(screen(1));
    settings.add({'showLiveStats': true});
    await tester.pump();
    for (var i = 2; i <= 30; i++) {
      await tester.pumpWidget(screen(i));
      expect(find.text('$i live viewers'), findsOneWidget);
    }
    expect(listens, 1);
    expect(cancels, 0);
    await tester.pumpWidget(const SizedBox());
    expect(cancels, 1);
    unawaited(settings.close());
  });
}