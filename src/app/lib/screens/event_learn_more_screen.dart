import 'package:flutter/material.dart';
import '../models/event.dart';
import '../widgets/media/content_viewer.dart';
import 'fullscreen_content_screen.dart';

class EventLearnMoreScreen extends StatelessWidget {
  final Event event;

  const EventLearnMoreScreen({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    // Landscape drops the title bar so the content can use the full screen.
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                if (!isLandscape) ...[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    color: Colors.white,
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back, color: Colors.black),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            event.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.black,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                ],
                Expanded(
                  flex: 3,
                  child: Container(
                    color: Colors.black,
                    child: GestureDetector(
                      onTap: () {
                        final url = event.learnMoreContent;
                        if (url != null && url.isNotEmpty) {
                          _showExpandedContent(context, url);
                        }
                      },
                      child: _buildMainContent(context),
                    ),
                  ),
                ),
                if (event.learnMoreYoutubeUrl != null &&
                    event.learnMoreYoutubeUrl!.isNotEmpty)
                  Expanded(
                    flex: 1,
                    child: GestureDetector(
                      onTap: () {
                        _showExpandedContent(
                          context,
                          event.learnMoreYoutubeUrl!,
                        );
                      },
                      child: Container(
                        color: Colors.black,
                        child: _buildSecondaryContent(context),
                      ),
                    ),
                  ),
              ],
            ),
            if (isLandscape)
              Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Material(
                    color: Colors.black54,
                    shape: const CircleBorder(),
                    child: IconButton(
                      tooltip: 'Back',
                      icon: const Icon(
                        Icons.arrow_back,
                        color: Colors.white,
                        size: 26,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showExpandedContent(BuildContext context, String url) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => FullscreenContentScreen(url: url),
      ),
    );
  }

  Widget _buildMainContent(BuildContext context) {
    final url = event.learnMoreContent;
    
    if (url == null || url.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.image, color: Colors.white24, size: 48),
            SizedBox(height: 8),
            Text('No Learn More Visual',
                style: TextStyle(color: Colors.white54)),
          ],
        ),
      );
    }

    final viewer = ContentViewer(
      url: url,
      fit: BoxFit.contain,
      controls: true,
    );

    // PDFs bring their own zoom; images need InteractiveViewer to pinch zoom.
    if (url.toLowerCase().contains('.pdf')) {
      return viewer;
    }

    return InteractiveViewer(
      minScale: 1,
      maxScale: 5,
      child: Center(child: viewer),
    );
  }

  Widget _buildSecondaryContent(BuildContext context) {
    final url = event.learnMoreYoutubeUrl!;

    // 1. Check for YouTube
    final youtubeId = _extractYoutubeId(url);
    if (youtubeId.isNotEmpty) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            'https://img.youtube.com/vi/$youtubeId/0.jpg',
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Container(
                color: Colors.grey.shade900,
                child: const Icon(
                    Icons.play_circle_outline,
                    color: Colors.white,
                    size: 48)),
          ),
          const Center(
              child: Icon(Icons.play_circle_fill,
                  color: Colors.white, size: 48)),
        ],
      );
    }

    // 2. Use ContentViewer for everything else (Video, Image)
    return ContentViewer(
      url: url,
      fit: BoxFit.contain,
      controls: true,
      autoPlay: true,
      loop: false,
    );
  }

  String _extractYoutubeId(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return '';
    if (uri.host.contains('youtu.be')) {
      return uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '';
    }
    return uri.queryParameters['v'] ?? '';
  }
}