import 'package:flutter/material.dart';
import '../widgets/home_speaker_overlay.dart';
import '../widgets/support_icon.dart';

/// Full-screen shell for Community Support. The mirrored post feed itself
/// arrives in a later phase (dual-posting); this establishes navigation,
/// background, and the persistent speaker icon so those pieces have a home.
class CommunitySupportScreen extends StatelessWidget {
  final Map<String, dynamic> config;

  const CommunitySupportScreen({super.key, required this.config});

  @override
  Widget build(BuildContext context) {
    final title = (config['supportButtonText'] as String?)?.trim().isNotEmpty == true
        ? config['supportButtonText']
        : 'Community Support';
    final backgroundUrl = (config['supportBackgroundImageUrl'] as String?)?.trim();

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: (backgroundUrl != null && backgroundUrl.isNotEmpty)
                ? Image.network(backgroundUrl, fit: BoxFit.cover)
                : Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFF2A2550), Color(0xFF0F0D1F)],
                      ),
                    ),
                  ),
          ),
          const HomeSpeakerOverlay(),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SupportIcon(config: config, size: 56, fallbackColor: Colors.white70),
                  const SizedBox(height: 16),
                  const Text(
                    'Community support requests will appear here soon.',
                    style: TextStyle(color: Colors.white70, fontSize: 15),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
