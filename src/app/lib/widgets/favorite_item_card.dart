import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/favorites_service.dart';
import '../screens/video_player_screen.dart';

class FavoriteItemCard extends StatelessWidget {
  final Map<String, dynamic> topic;

  const FavoriteItemCard({super.key, required this.topic});

  @override
  Widget build(BuildContext context) {
    // Debug print to verify data integrity
    // debugPrint('Building FavoriteItemCard: ${topic['title']} - URL: ${topic['youtubeUrl'] ?? topic['url']}');

    return Container(
      // width: 160, // Removed to allow parent control (e.g., GridView)
      // margin: const EdgeInsets.only(right: 12), // Removed to allow parent control
      child: Stack(
        fit: StackFit.expand, // Ensure the stack fills the container
        children: [
          // Main Clickable Area
          GestureDetector(
            behavior: HitTestBehavior.opaque, // Ensure taps are caught
            onLongPress: () {
              // Debug Dialog to inspect data
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Debug Info'),
                  content: SingleChildScrollView(
                    child: Text(
                      topic.entries.map((e) => '${e.key}: ${e.value}').join('\n'),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              );
            },
            onTap: () {
              debugPrint('FavoriteItemCard: Tapped ${topic['title']}');
              
              String? url = topic['youtubeUrl'] as String?;
              if (url == null || url.isEmpty) {
                url = topic['url'] as String?;
              }

              debugPrint('FavoriteItemCard: Resolved URL: $url');

              if (url != null && url.isNotEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Playing: ${topic['title']}'),
                    duration: const Duration(milliseconds: 500),
                  ),
                );
                
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => VideoPlayerScreen(
                      videoUrl: url!,
                    ),
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Error: Content URL is missing'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Thumbnail Section
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          topic['thumbnail'] as String? ?? '',
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: Colors.black26,
                            child: const Icon(Icons.broken_image, color: Colors.white54),
                          ),
                        ),
                        // Play Icon Overlay
                        Center(
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.5),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.play_arrow, color: Colors.white, size: 24),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Title Section
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      topic['title'] as String? ?? 'Unknown',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Remove Button (Top Right)
          Positioned(
            top: 0,
            right: 0,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                debugPrint('FavoriteItemCard: Remove tapped for ${topic['title']}');
                final url = topic['youtubeUrl'] as String? ?? topic['url'] as String?;
                if (url != null) {
                  Provider.of<FavoritesService>(context, listen: false).removeFavorite(url);
                }
              },
              child: Container(
                padding: const EdgeInsets.all(12), // Increased touch area
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, size: 16, color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
