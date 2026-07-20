import 'package:flutter/material.dart';
// Diagnostic boot mode to confirm Flutter rendering on-device.

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HarmonyDiagnosticApp());
}

class HarmonyDiagnosticApp extends StatelessWidget {
  const HarmonyDiagnosticApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Color(0xFF0B3D91),
        body: Center(
          child: Text(
            'HARMONY DIAGNOSTIC BOOT OK',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}
