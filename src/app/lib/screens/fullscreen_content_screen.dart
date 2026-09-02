import 'package:flutter/material.dart';
import '../widgets/media/content_viewer.dart';

/// Full-screen route so PDFs and media get the whole viewport for pinch zoom.
class FullscreenContentScreen extends StatelessWidget {
  final String url;

  const FullscreenContentScreen({super.key, required this.url});

  @override
  Widget build(BuildContext context) {
    // PDFs bring their own zoom; images need InteractiveViewer to pinch zoom.
    final isPdf = url.toLowerCase().contains('.pdf');
    final viewer = ContentViewer(
      url: url,
      fit: BoxFit.contain,
      controls: true,
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: isPdf
                ? viewer
                : InteractiveViewer(
                    minScale: 1,
                    maxScale: 5,
                    child: Center(child: viewer),
                  ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Material(
                  color: Colors.black54,
                  shape: const CircleBorder(),
                  child: IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close, color: Colors.white, size: 28),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
