import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/media/content_viewer.dart';

class GenericVideoPlayerScreen extends StatefulWidget {
  final String videoUrl;

  const GenericVideoPlayerScreen({super.key, required this.videoUrl});

  @override
  State<GenericVideoPlayerScreen> createState() => _GenericVideoPlayerScreenState();
}

class _GenericVideoPlayerScreenState extends State<GenericVideoPlayerScreen> {
  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: ContentViewer(
                url: widget.videoUrl,
                fit: BoxFit.contain,
                controls: true,
                autoPlay: true,
                loop: false,
              ),
            ),
            Positioned(
              top: 16,
              left: 16,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 30),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
