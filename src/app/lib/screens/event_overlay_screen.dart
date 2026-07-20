import 'package:flutter/material.dart';
import '../widgets/media/content_viewer.dart';

class EventOverlayScreen extends StatelessWidget {
  final String title;
  final String description;
  final bool isWorldwide;
  final String? mediaUrl;
  final String? userIntent;
  final VoidCallback onDismiss;

  const EventOverlayScreen({
    super.key,
    required this.title,
    required this.description,
    required this.isWorldwide,
    this.mediaUrl,
    this.userIntent,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    isWorldwide
                        ? Colors.purple.shade900
                        : Colors.indigo.shade900,
                    Colors.black,
                  ],
                ),
              ),
            ),
          ),
          if (mediaUrl != null && mediaUrl!.isNotEmpty)
            Positioned.fill(
              child: IgnorePointer(
                child: ContentViewer(
                  url: mediaUrl!,
                  fit: BoxFit.cover,
                  controls: false,
                  autoPlay: true,
                  loop: true,
                ),
              ),
            )
          else
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      isWorldwide
                          ? Colors.purple.shade900
                          : Colors.indigo.shade900,
                      Colors.black,
                    ],
                  ),
                ),
                child: Center(
                  child: Icon(
                    isWorldwide ? Icons.public : Icons.music_note,
                    size: 120,
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                ),
              ),
            ),

          Positioned.fill(
            child: SafeArea(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 72, 24, 120),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: const [],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 16,
                    bottom: 20,
                    child: TextButton(
                      onPressed: onDismiss,
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.black.withValues(alpha: 0.2),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.35),
                            width: 1,
                          ),
                        ),
                      ),
                      child: const Text(
                        'Exit Event',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
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
