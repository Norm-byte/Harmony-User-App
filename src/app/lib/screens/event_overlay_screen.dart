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
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: onDismiss,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          children: [
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
                        isWorldwide ? Colors.purple.shade900 : Colors.indigo.shade900,
                        Colors.black,
                      ],
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      isWorldwide ? Icons.public : Icons.music_note,
                      size: 120,
                      color: Colors.white.withOpacity(0.2),
                    ),
                  ),
                ),
              ),
            
            Positioned.fill(
              child: SafeArea(
                child: Stack(
                  children: [
                    Positioned(
                      top: 12,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          decoration: BoxDecoration(
                            color: (isWorldwide ? Colors.purple : Colors.indigo).withOpacity(0.8),
                            borderRadius: BorderRadius.circular(30),
                            boxShadow: [
                              BoxShadow(
                                color: (isWorldwide ? Colors.purple : Colors.indigo).withOpacity(0.5),
                                blurRadius: 20,
                                spreadRadius: 5,
                              ),
                            ],
                          ),
                          child: Text(
                            isWorldwide ? 'WORLDWIDE EVENT' : 'NATIONAL CHIME',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2.0,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 12,
                      child: Material(
                        color: Colors.black.withOpacity(0.35),
                        shape: const CircleBorder(),
                        child: IconButton(
                          onPressed: onDismiss,
                          icon: const Icon(Icons.close, color: Colors.white),
                          tooltip: 'Exit Event',
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(24, 120, 24, 140),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                title,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 36,
                                  fontWeight: FontWeight.bold,
                                  shadows: [
                                    Shadow(
                                      blurRadius: 10.0,
                                      color: Colors.black,
                                      offset: Offset(2.0, 2.0),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),
                              Text(
                                description.isNotEmpty
                                    ? description
                                    : 'Join us for a moment of shared intention...',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  height: 1.5,
                                  shadows: [
                                    Shadow(
                                      blurRadius: 10.0,
                                      color: Colors.black,
                                      offset: Offset(1.0, 1.0),
                                    ),
                                  ],
                                ),
                              ),
                              if (userIntent != null && userIntent!.isNotEmpty) ...[
                                const SizedBox(height: 32),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      top: BorderSide(color: Colors.white.withOpacity(0.2)),
                                      bottom: BorderSide(color: Colors.white.withOpacity(0.2)),
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      Text(
                                        'YOUR INTENT',
                                        style: TextStyle(
                                          color: Colors.amberAccent,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 2.0,
                                          shadows: const [Shadow(blurRadius: 4, color: Colors.black)],
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        userIntent!,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 22,
                                          fontWeight: FontWeight.w300,
                                          fontStyle: FontStyle.italic,
                                          shadows: [
                                            Shadow(
                                              blurRadius: 10.0,
                                              color: Colors.black,
                                              offset: Offset(1.0, 1.0),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 24,
                      child: Center(
                        child: ElevatedButton(
                          onPressed: onDismiss,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white.withOpacity(0.2),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                              side: const BorderSide(color: Colors.white54, width: 1.5),
                            ),
                            elevation: 0,
                          ),
                          child: const Text(
                            'LEAVE EVENT',
                            style: TextStyle(
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.bold,
                            ),
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
      ),
    );
  }
}
