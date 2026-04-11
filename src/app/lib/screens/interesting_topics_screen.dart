import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:share_plus/share_plus.dart';
import '../services/favorites_service.dart';
import 'video_player_screen.dart';
import 'generic_video_player_screen.dart';
import '../widgets/media/content_viewer.dart';

class InterestingTopicsScreen extends StatelessWidget {
  const InterestingTopicsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Navigator(
      onGenerateRoute: (settings) {
        Widget page;
        if (settings.name == '/') {
          page = const TopicsLandingScreen();
        } else if (settings.name == '/section') {
          final args = settings.arguments as Map<String, dynamic>;
          page = SectionDetailScreen(
            sectionId: args['sectionId'],
            sectionTitle: args['sectionTitle'],
            featuredContentId: args['featuredContentId'],
            allVideos: args['allVideos'],
            subcategories: args['subcategories'],
            subcategoryFeaturedContentIds: args['subcategoryFeaturedContentIds'],
          );
        } else if (settings.name == '/subcategory') {
          final args = settings.arguments as Map<String, dynamic>;
          page = SubcategoryDetailScreen(
            sectionTitle: args['sectionTitle'],
            subcategoryTitle: args['subcategoryTitle'],
            videos: args['videos'],
            featuredContentId: args['featuredContentId'],
          );
        } else {
          page = const TopicsLandingScreen();
        }
        return MaterialPageRoute(builder: (_) => page);
      },
    );
  }
}

class TopicsLandingScreen extends StatelessWidget {
  const TopicsLandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      // Listen to LIVE Sections
      stream: FirebaseFirestore.instance.collection('youtube_sections').orderBy('order').snapshots(),
      builder: (context, sectionsSnapshot) {
        return StreamBuilder<QuerySnapshot>(
          // Listen to LIVE Library
          stream: FirebaseFirestore.instance.collection('youtube_library').orderBy('createdAt', descending: true).snapshots(),
          builder: (context, videosSnapshot) {
            if (sectionsSnapshot.hasError || videosSnapshot.hasError) {
              return const Center(child: Text('Error loading content', style: TextStyle(color: Colors.white)));
            }

            if (!sectionsSnapshot.hasData || !videosSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final sections = sectionsSnapshot.data!.docs;
            final videos = videosSnapshot.data!.docs;

            // Global Featured: First video with isFeatured=true
            final globalFeatured = videos.where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              return data['isFeatured'] == true;
            }).firstOrNull;

            return CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      if (globalFeatured != null)
                        _buildFeaturedTopicStatic(context, _docToMapStatic(globalFeatured)),
                      
                      const SizedBox(height: 24),
                      if (sections.isNotEmpty)
                        const Text(
                          'Explore Topics',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      const SizedBox(height: 16),
                    ]),
                  ),
                ),
                // Sections Grid (4 Columns)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      childAspectRatio: 1.0, 
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final sectionDoc = sections[index];
                        final sectionData = sectionDoc.data() as Map<String, dynamic>;
                        final sectionId = sectionDoc.id;
                        final sectionTitle = sectionData['title'] ?? '';
                        final subcategories = List<String>.from(sectionData['subcategories'] ?? []);

                        return InkWell(
                          onTap: () {
                             // If subcategories exist, logic to show them could go here
                             // For now, navigates to detail as before
                             Navigator.of(context).pushNamed(
                              '/section',
                              arguments: {
                                'sectionId': sectionId,
                                'sectionTitle': sectionTitle,
                                'featuredContentId': sectionData['featuredContentId'],
                                'allVideos': videos,
                                'subcategories': subcategories,
                                'subcategoryFeaturedContentIds': sectionData['subcategoryFeaturedContentIds'],
                              },
                            );
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white10),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // Icon or Thumbnail placeholder logic could go here
                                // For now, just title
                                Text(
                                  sectionTitle,
                                  textAlign: TextAlign.center,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10, // Reduced to 10 for better fit
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (subcategories.isNotEmpty) ...[
                                   const SizedBox(height: 4),
                                   Text(
                                     '${subcategories.length} Subtopics',
                                     style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.6)),
                                   )
                                ]
                              ],
                            ),
                          ),
                        );
                      },
                      childCount: sections.length,
                    ),
                  ),
                ),
                const SliverToBoxAdapter(
                  child: SizedBox(height: 80),
                ),
              ],
            );
          },
        );
      },
    );
  }

  static String? _getVideoId(String url) {
    // 1. Try standard regex for watch?v= and youtu.be/
    final regExp = RegExp(
      r'^.*((youtu.be\/)|(v\/)|(\/u\/\w\/)|(embed\/)|(watch\?))\??v?=?([^#&?]*).*',
      caseSensitive: false,
      multiLine: false,
    );
    final match = regExp.firstMatch(url);
    if (match != null && match.groupCount >= 7) {
      return match.group(7);
    }

    // 2. Handle Shorts and Live manually if regex failed
    try {
      final uri = Uri.parse(url);
      if (uri.pathSegments.contains('shorts')) {
        final index = uri.pathSegments.indexOf('shorts');
        if (index + 1 < uri.pathSegments.length) return uri.pathSegments[index + 1];
      }
      if (uri.pathSegments.contains('live')) {
        final index = uri.pathSegments.indexOf('live');
        if (index + 1 < uri.pathSegments.length) return uri.pathSegments[index + 1];
      }
    } catch (_) {}

    return null;
  }

  static Map<String, String> _docToMapStatic(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    String url = data['url']?.toString() ?? '';
    String thumbnail = data['thumbnailUrl']?.toString() ?? '';
    String storedVideoId = data['videoId']?.toString() ?? '';

    // Improved Type Detection
    String type = data['type']?.toString() ?? '';
    
    // Force detection for YouTube IDs/URLs to correct mislabeled data
    // This overrides the DB 'type' if the URL is clearly a YouTube ID or URL
    if (url.length == 11 && !url.contains('/') && !url.contains('.')) {
       type = 'youtube';
       url = 'https://www.youtube.com/watch?v=$url'; // Normalize ID to URL
    } else if (url.toLowerCase().contains('youtu')) {
       type = 'youtube';
    }

    if (type.isEmpty) {
      if (url.toLowerCase().endsWith('.mp4') || 
                 url.toLowerCase().contains('.mov') || 
                 url.toLowerCase().contains('.firebasestorage')) {
        type = 'video';
      } else {
        // Fallback: Check if it looks like a YouTube ID (11 chars, alphanumeric)
        // or if it's just a plain string that isn't a URL
        if (url.length == 11 && !url.contains('/')) {
           type = 'youtube';
           url = 'https://www.youtube.com/watch?v=$url'; // Normalize ID to URL
        } else {
           type = 'youtube'; // Default fallback
        }
      }
    }

    // Try to recover thumbnail if missing
    if (thumbnail.isEmpty && type == 'youtube') {
      // Use stored ID if available, otherwise extract from URL
      final videoId = storedVideoId.isNotEmpty ? storedVideoId : _getVideoId(url);
      if (videoId != null) {
        thumbnail = 'https://img.youtube.com/vi/$videoId/hqdefault.jpg';
      }
    }

    // Debug Log
    // debugPrint('Doc: ${data['title']} | URL: $url | Type: $type | Thumb: $thumbnail');

    return {
      'title': data['title']?.toString() ?? '',
      'description': data['description']?.toString() ?? '',
      'thumbnail': thumbnail,
      'youtubeUrl': url,
      'sectionId': data['sectionId']?.toString() ?? '',
      'type': type,
      'id': doc.id,
    };
  }

  static void _showVideoDialog(BuildContext context, String url) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black.withOpacity(0.9),
        barrierDismissible: true,
        pageBuilder: (context, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: animation,
            child: Scaffold(
              backgroundColor: Colors.transparent,
              body: SafeArea(
                child: Stack(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(color: Colors.transparent),
                    ),
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: ContentViewer(
                          url: url,
                          fit: BoxFit.contain,
                          controls: true,
                          autoPlay: true,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 16,
                      left: 16,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  static Widget _buildFeaturedTopicStatic(BuildContext context, Map<String, String> topic) {
    return FeaturedTopicViewer(topic: topic);
  }

  static Widget _buildTopicGridItemStatic(BuildContext context, Map<String, String> topic) {
    return Consumer<FavoritesService>(
      builder: (context, favoritesService, _) {
        final isFavorite = favoritesService.isFavorite(topic['youtubeUrl']!);

        return GestureDetector(
          onTap: () {
            if (topic['type'] == 'youtube') {
              _showVideoDialog(context, topic['youtubeUrl']!);
            } else {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => GenericVideoPlayerScreen(
                    videoUrl: topic['youtubeUrl']!,
                  ),
                ),
              );
            }
          },
          child: Card(
            margin: EdgeInsets.zero,
            color: Colors.white.withOpacity(0.1),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Thumbnail
                Expanded(
                  flex: 4,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: double.infinity,
                        decoration: const BoxDecoration(
                          color: Colors.black26,
                          borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                        ),
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                          child: topic['thumbnail']!.isNotEmpty
                              ? Image.network(
                                  topic['thumbnail']!,
                                  fit: BoxFit.cover,
                                  cacheWidth: 400, // Optimize memory usage
                                  errorBuilder: (context, error, stackTrace) {
                                    return const Center(
                                      child: Icon(Icons.video_library, size: 30, color: Colors.white54),
                                    );
                                  },
                                )
                              : const Center(
                                  child: Icon(Icons.video_file, size: 30, color: Colors.white54),
                                ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.4),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.play_arrow, size: 24, color: Colors.white),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          topic['title']!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Expanded(
                          child: Text(
                            topic['description']!,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white60, fontSize: 11),
                          ),
                        ),
                        Align(
                          alignment: Alignment.bottomRight,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GestureDetector(
                                onTap: () {
                                  Share.share('Check out this content on Harmony: ${topic['title']} - ${topic['youtubeUrl']}');
                                },
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 8.0),
                                  child: Icon(Icons.share, color: Colors.white54, size: 20),
                                ),
                              ),
                              GestureDetector(
                                onTap: () {
                                  favoritesService.toggleFavorite(topic);
                                },
                                child: Icon(
                                  isFavorite ? Icons.favorite : Icons.favorite_border,
                                  color: isFavorite ? Colors.red : Colors.white54,
                                  size: 20,
                                ),
                              ),
                            ],
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
      },
    );
  }
}

class SectionDetailScreen extends StatelessWidget {
  final String sectionId;
  final String sectionTitle;
  final String? featuredContentId;
  final List<QueryDocumentSnapshot> allVideos;
  final List<String> subcategories;
  final Map<String, dynamic>? subcategoryFeaturedContentIds;

  const SectionDetailScreen({
    super.key, 
    required this.sectionId, 
    required this.sectionTitle, 
    this.featuredContentId,
    required this.allVideos,
    this.subcategories = const [],
    this.subcategoryFeaturedContentIds,
  });

  @override
  Widget build(BuildContext context) {
    // Filter videos for this section
    final sectionVideos = allVideos.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return data['sectionId'] == sectionId;
    }).toList();

    // Find featured for this section
    final featured = sectionVideos.where((doc) => doc.id == featuredContentId).firstOrNull 
        ?? sectionVideos.where((doc) {
             final data = doc.data() as Map<String, dynamic>;
             return data['isFeatured'] == true;
           }).firstOrNull 
        ?? sectionVideos.firstOrNull;

    // Filter "General Content": Not featured AND subcategory is null/empty
    final gridVideos = sectionVideos.where((doc) {
      if (doc.id == featured?.id) return false;
      final data = doc.data() as Map<String, dynamic>;
      final sub = data['subcategory'];
      return sub == null || sub.toString().isEmpty;
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E), 
      appBar: AppBar(
        title: Text(sectionTitle),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (featured != null)
                  TopicsLandingScreen._buildFeaturedTopicStatic(context, TopicsLandingScreen._docToMapStatic(featured)),
                
                 if (subcategories.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  const Text(
                    'Explore Categories',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 12),
                ]
              ]),
            ),
          ),
          
          if (subcategories.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4, // 4 Abreast
                  childAspectRatio: 1.0, 
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                      final sub = subcategories[index];
                      // Find featured ID for this subcategory
                      final subFeaturedId = subcategoryFeaturedContentIds?[sub]?.toString();

                      return InkWell(
                        onTap: () {
                          // Filter videos for this subcategory
                          final subVideos = sectionVideos.where((doc) {
                            final data = doc.data() as Map<String, dynamic>;
                            return data['subcategory'] == sub;
                          }).toList();
                          
                          Navigator.of(context).pushNamed(
                            '/subcategory',
                            arguments: {
                              'sectionTitle': sectionTitle,
                              'subcategoryTitle': sub,
                              'videos': subVideos,
                              'featuredContentId': subFeaturedId,
                            }
                          );
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.indigo.shade900.withOpacity(0.5), // Distinct subcat color
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white24),
                          ),
                          alignment: Alignment.center,
                          padding: const EdgeInsets.all(4),
                          child: Text(
                            sub,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      );
                  },
                  childCount: subcategories.length,
                ),
              ),
            ),

          if (gridVideos.isNotEmpty) ...[
          /* General content removed from view
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    const SizedBox(height: 24),
                    Text(
                    subcategories.isNotEmpty ? 'General Content' : 'Content',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(height: 12),
                  ])
                )
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.85, 
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      return TopicsLandingScreen._buildTopicGridItemStatic(context, TopicsLandingScreen._docToMapStatic(gridVideos[index]));
                    },
                    childCount: gridVideos.length,
                  ),
                ),
              ),
            */
          ],
          const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
        ],
      ),
    );
  }
}

class SubcategoryDetailScreen extends StatelessWidget {
  final String sectionTitle;
  final String subcategoryTitle;
  final List<QueryDocumentSnapshot> videos;
  final String? featuredContentId;

  const SubcategoryDetailScreen({
    super.key,
    required this.sectionTitle,
    required this.subcategoryTitle,
    required this.videos,
    this.featuredContentId,
  });

  @override
  Widget build(BuildContext context) {
    // Identify featured video
    final featured = videos.where((doc) => doc.id == featuredContentId).firstOrNull;
    final gridVideos = videos.where((doc) => doc.id != featured?.id).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E), 
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(subcategoryTitle, style: const TextStyle(fontSize: 18)),
            Text(sectionTitle, style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: videos.isEmpty ? 
        const Center(child: Text('No content in this subcategory', style: TextStyle(color: Colors.white54)))
        : CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (featured != null) ...[
                   TopicsLandingScreen._buildFeaturedTopicStatic(context, TopicsLandingScreen._docToMapStatic(featured)),
                   const SizedBox(height: 24),
                   const Text('Subcategory Content', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16)),
                   const SizedBox(height: 12),
                ],
              ]),
            ),
          ),
          
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.85,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  return TopicsLandingScreen._buildTopicGridItemStatic(context, TopicsLandingScreen._docToMapStatic(gridVideos[index]));
                },
                childCount: gridVideos.length,
              ),
            ),
          ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
        ],
      ),
    );
  }
}

class FeaturedTopicViewer extends StatefulWidget {
  final Map<String, String> topic;
  final bool isVisible;
  const FeaturedTopicViewer({super.key, required this.topic, this.isVisible = true});

  @override
  State<FeaturedTopicViewer> createState() => _FeaturedTopicViewerState();
}

class _FeaturedTopicViewerState extends State<FeaturedTopicViewer> {
  @override
  Widget build(BuildContext context) {
    // If not visible, we can return a placeholder or the thumbnail to save resources.
    // But to keep the UI stable, we should return the same structure.
    // The ContentViewer/VideoPlayer inside should handle the pause/dispose.
    
    return Consumer<FavoritesService>(
      builder: (context, favoritesService, _) {
        final isFavorite = favoritesService.isFavorite(widget.topic['youtubeUrl']!);
        final isYoutube = widget.topic['type'] == 'youtube';
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.amber.shade200.withOpacity(0.8),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'FEATURED SPECIAL',
                style: TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              margin: EdgeInsets.zero,
              color: Colors.white.withOpacity(0.1),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                    child: SizedBox(
                      height: 180,
                      width: double.infinity,
                      child: isYoutube
                          ? GestureDetector(
                              onTap: () {
                                TopicsLandingScreen._showVideoDialog(context, widget.topic['youtubeUrl']!);
                              },
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  widget.topic['thumbnail']!.isNotEmpty
                                      ? Image.network(
                                          widget.topic['thumbnail']!,
                                          fit: BoxFit.cover,
                                          width: double.infinity,
                                          height: double.infinity,
                                          cacheWidth: 800,
                                          errorBuilder: (context, error, stackTrace) {
                                            return Container(
                                              color: Colors.black26,
                                              child: const Icon(Icons.star, size: 50, color: Colors.white54),
                                            );
                                          },
                                        )
                                      : Container(
                                          color: Colors.black26,
                                          child: const Center(
                                            child: Icon(Icons.video_file, size: 50, color: Colors.white54),
                                          ),
                                        ),
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.4),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.play_arrow, size: 40, color: Colors.white),
                                  ),
                                ],
                              ),
                            )
                          : (widget.isVisible 
                              ? ContentViewer(
                                  url: widget.topic['youtubeUrl']!,
                                  fit: BoxFit.cover,
                                  controls: true,
                                )
                              : Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    // Show thumbnail when not visible (tab switched)
                                    widget.topic['thumbnail']!.isNotEmpty
                                        ? Image.network(
                                            widget.topic['thumbnail']!,
                                            fit: BoxFit.cover,
                                            width: double.infinity,
                                            height: double.infinity,
                                            cacheWidth: 800,
                                          )
                                        : Container(color: Colors.black26),
                                    const Icon(Icons.play_arrow, size: 40, color: Colors.white),
                                  ],
                                )
                            ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                widget.topic['title']!,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                isFavorite ? Icons.favorite : Icons.favorite_border,
                                color: isFavorite ? Colors.red : Colors.white70,
                                size: 24,
                              ),
                              onPressed: () => favoritesService.toggleFavorite(widget.topic),
                            ),
                            IconButton(
                              icon: const Icon(Icons.share, color: Colors.white70, size: 24),
                              onPressed: () {
                                Share.share('Check out this content on Harmony: ${widget.topic['title']} - ${widget.topic['youtubeUrl']}');
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.topic['description']!,
                          style: const TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

