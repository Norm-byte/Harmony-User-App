import 'package:flutter/material.dart';
import '../widgets/media/content_viewer.dart';

class EventOverlayScreen extends StatefulWidget {
  final String title;
  final String description;
  final bool isWorldwide;
  final String? mediaUrl;
  final DateTime? eventStartTime;
  final DateTime? eventEndTime;
  final String? userIntent;
  final VoidCallback onDismiss;

  const EventOverlayScreen({
    super.key,
    required this.title,
    required this.description,
    required this.isWorldwide,
    this.mediaUrl,
    this.eventStartTime,
    this.eventEndTime,
    this.userIntent,
    required this.onDismiss,
  });

  @override
  State<EventOverlayScreen> createState() => _EventOverlayScreenState();
}

class _EventOverlayScreenState extends State<EventOverlayScreen> {
  late final ValueNotifier<DateTime> _now;

  @override
  void initState() {
    super.initState();
    _now = ValueNotifier<DateTime>(DateTime.now());
    _startTicker();
  }

  void _startTicker() {
    Future.doWhile(() async {
      if (!mounted) return false;
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      _now.value = DateTime.now();
      return true;
    });
  }

  @override
  void dispose() {
    _now.dispose();
    super.dispose();
  }

  String _formatClock(int totalSeconds) {
    final safe = totalSeconds < 0 ? 0 : totalSeconds;
    final minutes = safe ~/ 60;
    final seconds = safe % 60;
    final mm = minutes.toString().padLeft(2, '0');
    final ss = seconds.toString().padLeft(2, '0');
    return '$mm:$ss';
  }

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
                      widget.isWorldwide
                        ? Colors.purple.shade900
                        : Colors.indigo.shade900,
                    Colors.black,
                  ],
                ),
              ),
            ),
          ),
          if (widget.mediaUrl != null && widget.mediaUrl!.isNotEmpty)
            Positioned.fill(
              child: IgnorePointer(
                child: ContentViewer(
                  url: widget.mediaUrl!,
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
                        widget.isWorldwide
                          ? Colors.purple.shade900
                          : Colors.indigo.shade900,
                      Colors.black,
                    ],
                  ),
                ),
                child: Center(
                  child: Icon(
                      widget.isWorldwide ? Icons.public : Icons.music_note,
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
                        child: ValueListenableBuilder<DateTime>(
                          valueListenable: _now,
                          builder: (context, now, _) {
                            final start = widget.eventStartTime;
                            final end = widget.eventEndTime;
                            final hasTiming = start != null && end != null;
                            final totalSeconds = hasTiming
                                ? end.difference(start).inSeconds
                                : 0;
                            final remainingSeconds = hasTiming
                                ? end.difference(now).inSeconds
                                : 0;
                            final clampedTotal = totalSeconds <= 0 ? 1 : totalSeconds;
                            final clampedRemaining = remainingSeconds < 0 ? 0 : remainingSeconds;
                            final progress = (clampedRemaining / clampedTotal)
                                .clamp(0.0, 1.0)
                                .toDouble();

                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.45),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.35),
                                    ),
                                  ),
                                  child: Text(
                                    widget.isWorldwide ? 'WORLDWIDE LIVE' : 'NATIONAL LIVE',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  widget.title,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  widget.description,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.92),
                                    fontSize: 14,
                                    height: 1.35,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                if (hasTiming)
                                  Container(
                                    width: 240,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.45),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: Colors.white.withValues(alpha: 0.28),
                                      ),
                                    ),
                                    child: Column(
                                      children: [
                                        Text(
                                          _formatClock(clampedRemaining),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 26,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 1.0,
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(999),
                                          child: LinearProgressIndicator(
                                            minHeight: 6,
                                            value: progress,
                                            backgroundColor: Colors.white24,
                                            valueColor: const AlwaysStoppedAnimation<Color>(
                                              Colors.lightGreenAccent,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 16,
                    bottom: 20,
                    child: TextButton(
                      onPressed: widget.onDismiss,
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
