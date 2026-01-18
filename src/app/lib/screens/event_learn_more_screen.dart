import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/event.dart';
import '../widgets/media/content_viewer.dart';

class EventLearnMoreScreen extends StatelessWidget {
  final Event event;

  const EventLearnMoreScreen({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                        color: Colors.black),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Content (3/4) - Visual Only
          Expanded(
            flex: 3,
            child: Container(
              color: Colors.black,
              child: _buildMainContent(context),
            ),
          ),

          // YouTube Thumbnail / Secondary Content (1/4)
          if (event.learnMoreYoutubeUrl != null && event.learnMoreYoutubeUrl!.isNotEmpty)
            Expanded(
              flex: 1,
              child: GestureDetector(
                onTap: () {
                  if (event.learnMoreYoutubeUrl != null) {
                    _showExpandedContent(context, event.learnMoreYoutubeUrl!);
                  }
                },
                child: Container(
                  color: Colors.black,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildSecondaryContent(context),
                      
                      // Expand Overlay Icon
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Icon(Icons.fullscreen, // Changed icon to indicate expansion
                              color: Colors.white, size: 20),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showExpandedContent(BuildContext context, String url) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            ContentViewer(
              url: url,
              fit: BoxFit.contain,
              controls: true,
            ),
            Positioned(
              top: 16,
              right: 16,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
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

    return ContentViewer(
      url: url,
      fit: BoxFit.contain,
      controls: true,
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
      controls: false,
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