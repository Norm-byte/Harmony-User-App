import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:provider/provider.dart';
import '../services/event_service.dart';
import '../services/user_service.dart';
import '../models/event.dart';
import '../widgets/media/content_viewer.dart';
import '../widgets/gradient_scaffold.dart';
import 'events_screen.dart';
import 'community_feed_screen.dart';
import 'interesting_topics_screen.dart';
import 'settings_screen.dart';
import 'app_settings_screen.dart';
import 'video_player_screen.dart';

const int kMaxActiveReels = 30;

class HomeScreen extends StatefulWidget {
  final bool isSuperAdmin;

  const HomeScreen({super.key, this.isSuperAdmin = false});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  bool _isYoutubeUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('youtube.com') || lower.contains('youtu.be');
  }

  bool _isVideoUrl(String url) {
    final lower = url.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.m4v');
  }

  Future<void> _prewarmReels(List<Map<String, dynamic>> items) async {
    final firstFew = items.take(3);
    for (final item in firstFew) {
      final url = (item['url'] as String?)?.trim() ?? '';
      if (url.isEmpty) continue;

      if (_isVideoUrl(url)) {
        DefaultCacheManager().downloadFile(url).catchError((_) {});
        continue;
      }

      if (_isYoutubeUrl(url)) {
        final id = YoutubePlayer.convertUrlToId(url);
        if (id == null || id.isEmpty) continue;
        final thumb = 'https://img.youtube.com/vi/$id/hqdefault.jpg';
        precacheImage(NetworkImage(thumb), context).catchError((_) {});
      }
    }
  }

  void _openReelsFullscreen(List<Map<String, dynamic>> reelItems) {
    final enabled = reelItems.where((item) {
      final isEnabled = (item['enabled'] as bool?) ?? true;
      final url = (item['url'] as String?)?.trim() ?? '';
      return isEnabled && url.isNotEmpty;
    }).take(kMaxActiveReels).toList();

    if (enabled.isEmpty) return;

    unawaited(_prewarmReels(enabled));

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _ReelsFullscreenScreen(items: enabled),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(
        title: const Text('Harmony by Intent'),
        // backgroundColor: Colors.indigo, // Removed to let gradient show
        foregroundColor: Colors.white,
        actions: [
          // Show Gear Icon only on "My Harmony" tab (Index 4)
          if (_selectedIndex == 4)
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AppSettingsScreen()),
                );
              },
            ),

          if (widget.isSuperAdmin)
            Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                border: Border.all(color: Colors.white24),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.shield, size: 13, color: Colors.white70),
                  SizedBox(width: 4),
                  Text(
                    'Super Admin',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white70,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          // Tab 0: Home (Welcome Message / Next Event)
          _buildHomeTab(isVisible: _selectedIndex == 0),
          // Tab 1: Events
          const EventsScreen(),
          // Tab 2: Chat (Community Feed)
          const CommunityFeedScreen(),
          // Tab 3: Interesting Topics
          const InterestingTopicsScreen(),
          // Tab 4: Settings / My Harmony
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        selectedItemColor:
            Colors.amber, // Changed to Amber for better contrast on dark
        unselectedItemColor: Colors.white70,
        backgroundColor: Colors.black.withOpacity(
          0.3,
        ), // Semi-transparent nav bar
        type:
            BottomNavigationBarType.fixed, // Added to support 4 items properly
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.event), label: 'Events'),
          BottomNavigationBarItem(icon: Icon(Icons.chat), label: 'Community'),
          BottomNavigationBarItem(
            icon: Icon(Icons.lightbulb_outline),
            label: 'Topics',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            label: 'My Harmony',
          ),
        ],
      ),
    );
  }

  Widget _buildHomeTab({bool isVisible = true}) {
    return Consumer<EventService>(
      builder: (context, eventService, _) {
        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('app_config')
              .doc('home_screen')
              .snapshots(),
          builder: (context, configSnapshot) {
            if (configSnapshot.hasError) {
              return Center(
                child: Text(
                  'Error: ${configSnapshot.error}',
                  style: const TextStyle(color: Colors.white),
                ),
              );
            }

            if (!configSnapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(color: Colors.white),
              );
            }

            final data =
                configSnapshot.data!.data() as Map<String, dynamic>? ?? {};
            final title = data['title'] as String? ?? 'Welcome to Harmony';
            final message =
                data['message'] as String? ?? 'Your journey begins here.';
            final backgroundImageUrl = data['backgroundImageUrl'] as String?;
            bool showBulletin = false;
            String bulletinText = '';
            final showLiveStats = data['showLiveStats'] as bool? ?? false;
            final showFeatured = data['showFeatured'] as bool? ?? false;
            final featuredType = data['featuredType'] as String? ?? 'youtube';
            final featuredUrl = data['featuredUrl'] as String? ?? '';
            final featuredTitle = data['featuredTitle'] as String? ?? '';
            final featuredBody = data['featuredBody'] as String? ?? '';
            final showReelCarousel = data['showReelCarousel'] as bool? ?? false;
            final reelAutoRotateSeconds =
              (data['reelAutoRotateSeconds'] as num?)?.toInt() ?? 8;
            final reelItemsRaw = (data['reelItems'] as List?) ?? const [];
            final reelItems = reelItemsRaw
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
            String? noticeBgImage;

            // Hard rule: home bulletin is App Content-only and uses
            // dedicated keys to avoid legacy/event writers overriding text.
            showBulletin = data['appContentShowBulletin'] as bool? ?? false;
            bulletinText = data['appContentBulletinText'] as String? ?? '';

            return Stack(
              children: [
                // Background Image/Video Overlay (if present)
                if (backgroundImageUrl != null)
                  Positioned.fill(
                    child: _BackgroundWidget(url: backgroundImageUrl),
                  ),

                // Content
                Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.spa, size: 80, color: Colors.white70),
                        const SizedBox(height: 24),
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          message,
                          style: const TextStyle(color: Colors.white70),
                          textAlign: TextAlign.center,
                        ),

                        const SizedBox(height: 32),

                        // Bulletin Board
                        if (showBulletin)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            margin: const EdgeInsets.only(bottom: 24),
                            decoration: BoxDecoration(
                              color: noticeBgImage != null
                                  ? Colors.black.withOpacity(0.5)
                                  : Colors.white.withOpacity(0.15),
                              image: noticeBgImage != null
                                  ? DecorationImage(
                                      image: NetworkImage(noticeBgImage),
                                      fit: BoxFit.cover,
                                      colorFilter: ColorFilter.mode(
                                        Colors.black.withOpacity(0.4),
                                        BlendMode.darken,
                                      ),
                                    )
                                  : null,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white30),
                            ),
                            child: Column(
                              children: [
                                const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.push_pin,
                                      color: Colors.amber,
                                      size: 16,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'NOTICE BOARD',
                                      style: TextStyle(
                                        color: Colors.amber,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  bulletinText,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: noticeBgImage != null
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                    shadows: noticeBgImage != null
                                        ? [
                                            const Shadow(
                                              color: Colors.black,
                                              blurRadius: 4,
                                            ),
                                          ]
                                        : null,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),

                        if (showFeatured)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 24),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: Stack(
                              children: [
                                Column(
                                  children: [
                                    if (featuredTitle.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                            bottom: 8, right: 72),
                                        child: Text(
                                          featuredTitle,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    if (featuredBody.isNotEmpty)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 12),
                                        child: Text(
                                          featuredBody,
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 14,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    _FeaturedContentWidget(
                                      type: featuredType,
                                      url: featuredUrl,
                                      isVisible: isVisible,
                                    ),
                                  ],
                                ),
                                if (reelItems.isNotEmpty)
                                  Positioned(
                                    top: 0,
                                    right: 0,
                                    child: Tooltip(
                                      message: 'Open Reels',
                                      child: GestureDetector(
                                        onTap: () =>
                                            _openReelsFullscreen(reelItems),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.play_circle_fill_rounded,
                                              color: Colors.white70,
                                              size: 26,
                                            ),
                                            SizedBox(width: 4),
                                            Text(
                                              'Reels',
                                              style: TextStyle(
                                                color: Colors.white70,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          )
                        else if (showReelCarousel)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 24),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: _ReelsLaunchCard(
                              reelItems: reelItems,
                              onOpen: () => _openReelsFullscreen(reelItems),
                            ),
                          ),

                        // Live Stats
                        const _ActiveUsersChip(),

                        if (widget.isSuperAdmin) ...[
                          const SizedBox(height: 18),
                          Text(
                            'Super Admin access enabled',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.55),
                              fontSize: 11,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _ReelsLaunchCard extends StatelessWidget {
  final List<Map<String, dynamic>> reelItems;
  final VoidCallback onOpen;
  final bool compact;

  const _ReelsLaunchCard({
    required this.reelItems,
    required this.onOpen,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final activeCount = reelItems.where((item) {
      final enabled = (item['enabled'] as bool?) ?? true;
      final url = (item['url'] as String?)?.trim() ?? '';
      return enabled && url.isNotEmpty;
    }).take(kMaxActiveReels).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.slideshow, color: Colors.amber, size: 18),
            const SizedBox(width: 8),
            Text(
              compact
                  ? 'Reels'
                  : 'Reel Carousel${activeCount > 0 ? ' ($activeCount)' : ''}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: activeCount > 0 ? onOpen : null,
            icon: const Icon(Icons.play_circle_fill_rounded),
            label: const Text('Open Reels Full Screen'),
          ),
        ),
      ],
    );
  }
}

class _ReelsFullscreenScreen extends StatefulWidget {
  final List<Map<String, dynamic>> items;

  const _ReelsFullscreenScreen({required this.items});

  @override
  State<_ReelsFullscreenScreen> createState() => _ReelsFullscreenScreenState();
}

class _ReelsFullscreenScreenState extends State<_ReelsFullscreenScreen> {
  late final PageController _pageController;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToNext() {
    if (!_pageController.hasClients || widget.items.isEmpty) return;
    final next = (_currentPage + 1) % widget.items.length;
    _pageController.animateToPage(
      next,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
    );
  }

  String _resolveType(Map<String, dynamic> item) {
    final rawType = (item['type'] as String?)?.toLowerCase().trim() ?? '';
    if (rawType.isNotEmpty) return rawType;

    final url = (item['url'] as String?)?.toLowerCase() ?? '';
    if (url.contains('youtu')) return 'youtube';
    if (url.endsWith('.mp4') || url.endsWith('.mov') || url.endsWith('.webm')) {
      return 'video';
    }
    if (url.endsWith('.png') ||
        url.endsWith('.jpg') ||
        url.endsWith('.jpeg') ||
        url.endsWith('.gif') ||
        url.endsWith('.webp')) {
      return 'image';
    }
    if (url.endsWith('.pdf')) return 'pdf';
    return 'link';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: widget.items.length,
            onPageChanged: (index) => setState(() => _currentPage = index),
            itemBuilder: (context, index) {
              final item = widget.items[index];
              final url = (item['url'] as String?)?.trim() ?? '';
              final title = (item['title'] as String?)?.trim() ?? '';
              final caption = (item['caption'] as String?)?.trim() ?? '';
              final type = _resolveType(item);

              Widget media;
              if (type == 'video') {
                media = _FullscreenVideoReel(url: url, onEnded: _goToNext);
              } else if (type == 'youtube') {
                media = _FullscreenYoutubeReel(url: url, onEnded: _goToNext);
              } else {
                media = ContentViewer(
                  url: url,
                  fit: BoxFit.cover,
                  controls: true,
                  autoPlay: true,
                  loop: false,
                );
              }

              return Stack(
                children: [
                  Positioned.fill(child: media),
                  if (title.isNotEmpty || caption.isNotEmpty)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(16, 26, 16, 22),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.black87],
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (title.isNotEmpty)
                              Text(
                                title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                            if (caption.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  caption,
                                  style: const TextStyle(color: Colors.white70),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            child: CircleAvatar(
              backgroundColor: Colors.black.withOpacity(0.45),
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 14,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_currentPage + 1} / ${widget.items.length}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: Colors.black.withOpacity(0.45),
                  child: PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, color: Colors.white),
                    color: Colors.grey.shade900,
                    onSelected: (value) {
                      if (value == 'report') {
                        _showReportSheet(context, widget.items[_currentPage]);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'report',
                        child: Row(
                          children: [
                            Icon(Icons.flag_outlined, color: Colors.redAccent, size: 18),
                            SizedBox(width: 8),
                            Text('Report', style: TextStyle(color: Colors.white)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showReportSheet(BuildContext context, Map<String, dynamic> item) async {
    final reasons = [
      'Inappropriate content',
      'Misleading or false information',
      'Harmful or dangerous',
      'Spam',
      'Other',
    ];
    String? selected;
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey.shade900,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Report this Reel',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('Why are you reporting this content?',
                  style: TextStyle(color: Colors.white54, fontSize: 13)),
              const SizedBox(height: 16),
              ...reasons.map((r) => RadioListTile<String>(
                    value: r,
                    groupValue: selected,
                    title: Text(r, style: const TextStyle(color: Colors.white70)),
                    activeColor: Colors.redAccent,
                    onChanged: (v) => setModalState(() => selected = v),
                  )),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: selected == null
                      ? null
                      : () async {
                          Navigator.pop(ctx);
                          final title = (item['title'] as String?)?.trim() ?? 'Untitled Reel';
                          final reelUrl = (item['url'] as String?)?.trim() ?? '';
                          final reelType = (item['type'] as String?)?.trim() ?? _resolveType(item);
                          final ok = await UserService().reportContent(
                            'admin_media',
                            title,
                            selected!,
                            'Reel',
                            metadata: {
                              'contentType': 'reel',
                              'reelTitle': title,
                              'reelUrl': reelUrl,
                              'reelType': reelType,
                              'reelCaption': (item['caption'] as String?)?.trim() ?? '',
                            },
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  ok
                                      ? 'Report submitted. Thank you.'
                                      : 'Could not submit report. Please try again.',
                                ),
                                backgroundColor: ok ? Colors.green : Colors.red,
                              ),
                            );
                          }
                        },
                  child: const Text('Submit Report'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FullscreenVideoReel extends StatefulWidget {
  final String url;
  final VoidCallback onEnded;

  const _FullscreenVideoReel({required this.url, required this.onEnded});

  @override
  State<_FullscreenVideoReel> createState() => _FullscreenVideoReelState();
}

class _FullscreenVideoReelState extends State<_FullscreenVideoReel> {
  VideoPlayerController? _controller;
  bool _endedNotified = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      VideoPlayerController controller;
      final cached = await DefaultCacheManager().getFileFromCache(widget.url);
      if (cached != null && await cached.file.exists()) {
        controller = VideoPlayerController.file(cached.file);
      } else {
        controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
        DefaultCacheManager().downloadFile(widget.url).catchError((_) {});
      }
      await controller.initialize();
      controller.addListener(_listen);
      await controller.play();
      if (!mounted) return;
      setState(() => _controller = controller);
    } catch (_) {}
  }

  void _listen() {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _endedNotified) return;
    final duration = c.value.duration;
    if (duration.inMilliseconds <= 0) return;
    final remaining = duration - c.value.position;
    if (remaining.inMilliseconds <= 250) {
      _endedNotified = true;
      widget.onEnded();
    }
  }

  @override
  void didUpdateWidget(covariant _FullscreenVideoReel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _controller?.removeListener(_listen);
      _controller?.dispose();
      _controller = null;
      _endedNotified = false;
      _init();
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_listen);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF111111), Color(0xFF050505)],
          ),
        ),
        alignment: Alignment.center,
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.slideshow_rounded, color: Colors.white54, size: 44),
            SizedBox(height: 10),
            Text('Loading reel...', style: TextStyle(color: Colors.white54)),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: () {
        if (c.value.isPlaying) {
          c.pause();
        } else {
          c.play();
        }
        setState(() {});
      },
      child: ClipRect(
        child: SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: c.value.size.width,
              height: c.value.size.height,
              child: VideoPlayer(c),
            ),
          ),
        ),
      ),
    );
  }
}

class _FullscreenYoutubeReel extends StatefulWidget {
  final String url;
  final VoidCallback onEnded;

  const _FullscreenYoutubeReel({required this.url, required this.onEnded});

  @override
  State<_FullscreenYoutubeReel> createState() => _FullscreenYoutubeReelState();
}

class _FullscreenYoutubeReelState extends State<_FullscreenYoutubeReel> {
  YoutubePlayerController? _controller;

  @override
  void initState() {
    super.initState();
    _init();
  }

  void _init() {
    final id = YoutubePlayer.convertUrlToId(widget.url);
    if (id == null) return;
    _controller = YoutubePlayerController(
      initialVideoId: id,
      flags: const YoutubePlayerFlags(
        autoPlay: true,
        mute: false,
        hideThumbnail: true,
        disableDragSeek: true,
        hideControls: true,
        controlsVisibleAtStart: false,
      ),
    );
  }

  @override
  void didUpdateWidget(covariant _FullscreenYoutubeReel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _controller?.dispose();
      _controller = null;
      _init();
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null) {
      return const Center(
        child: Text(
          'Unable to load this YouTube reel',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    return GestureDetector(
      onTap: () {
        final c = _controller!;
        if (c.value.isPlaying) {
          c.pause();
        } else {
          c.play();
        }
      },
      child: SizedBox.expand(
        child: YoutubePlayerBuilder(
          player: YoutubePlayer(
            controller: _controller!,
            showVideoProgressIndicator: false,
            onEnded: (_) => widget.onEnded(),
          ),
          builder: (context, player) => player,
        ),
      ),
    );
  }
}

class _HomeReelCarousel extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  final int autoRotateSeconds;
  final bool isVisible;

  const _HomeReelCarousel({
    required this.items,
    required this.autoRotateSeconds,
    required this.isVisible,
  });

  @override
  State<_HomeReelCarousel> createState() => _HomeReelCarouselState();
}

class _HomeReelCarouselState extends State<_HomeReelCarousel> {
  late final PageController _pageController;
  Timer? _autoRotateTimer;
  int _currentPage = 0;

  List<Map<String, dynamic>> get _enabledItems => widget.items.where((item) {
        final enabled = (item['enabled'] as bool?) ?? true;
        final url = (item['url'] as String?)?.trim() ?? '';
        return enabled && url.isNotEmpty;
    }).take(kMaxActiveReels).toList();

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _scheduleNextAutoRotate();
  }

  @override
  void didUpdateWidget(covariant _HomeReelCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items != widget.items ||
        oldWidget.autoRotateSeconds != widget.autoRotateSeconds ||
        oldWidget.isVisible != widget.isVisible) {
      if (_currentPage >= _enabledItems.length) {
        _currentPage = 0;
      }
      _scheduleNextAutoRotate();
    }
  }

  void _scheduleNextAutoRotate() {
    _autoRotateTimer?.cancel();
    final active = _enabledItems;
    if (!widget.isVisible || active.length < 2) return;

    final safePage = _currentPage.clamp(0, active.length - 1);
    final currentType = _resolveType(active[safePage]);

    // Never auto-skip a playing video reel.
    if (currentType == 'video' || currentType == 'youtube') return;

    final seconds = widget.autoRotateSeconds.clamp(4, 20);
    _autoRotateTimer = Timer(Duration(seconds: seconds), () {
      if (!mounted || !_pageController.hasClients) return;
      final nextPage = (_currentPage + 1) % active.length;
      _pageController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeInOut,
      );
    });
  }

  Future<void> _openFullscreen(String url) async {
    _autoRotateTimer?.cancel();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(videoUrl: url),
      ),
    );
    if (!mounted) return;
    _scheduleNextAutoRotate();
  }

  void _goToPreviousPage(int totalItems) {
    if (!_pageController.hasClients || totalItems < 2) return;
    final prevPage = (_currentPage - 1 + totalItems) % totalItems;
    _pageController.animateToPage(
      prevPage,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _goToNextPage(int totalItems) {
    if (!_pageController.hasClients || totalItems < 2) return;
    final nextPage = (_currentPage + 1) % totalItems;
    _pageController.animateToPage(
      nextPage,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  String _resolveType(Map<String, dynamic> item) {
    final rawType = (item['type'] as String?)?.toLowerCase().trim() ?? '';
    if (rawType.isNotEmpty) return rawType;

    final url = (item['url'] as String?)?.toLowerCase() ?? '';
    if (url.contains('youtu')) return 'youtube';
    if (url.endsWith('.mp4') || url.endsWith('.mov') || url.endsWith('.webm')) {
      return 'video';
    }
    if (url.endsWith('.png') ||
        url.endsWith('.jpg') ||
        url.endsWith('.jpeg') ||
        url.endsWith('.gif') ||
        url.endsWith('.webp')) {
      return 'image';
    }
    if (url.endsWith('.pdf')) return 'pdf';
    return 'link';
  }

  Widget _buildMedia(Map<String, dynamic> item) {
    final url = (item['url'] as String?)?.trim() ?? '';
    final type = _resolveType(item);

    if (type == 'link') {
      return Container(
        color: Colors.black38,
        alignment: Alignment.center,
        child: ElevatedButton.icon(
          onPressed: () => launchUrl(Uri.parse(url)),
          icon: const Icon(Icons.open_in_new),
          label: const Text('Open Link'),
        ),
      );
    }

    final isExpandableVideo = type == 'video' || type == 'youtube';

    return Stack(
      children: [
        Positioned.fill(
          child: ContentViewer(
            url: url,
            fit: BoxFit.cover,
            controls: type != 'image',
            autoPlay: true,
            loop: type != 'video' && type != 'youtube',
          ),
        ),
        if (isExpandableVideo)
          Positioned(
            right: 10,
            bottom: 10,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.45),
                borderRadius: BorderRadius.circular(18),
              ),
              child: IconButton(
                tooltip: 'Expand',
                icon: const Icon(Icons.zoom_out_map, color: Colors.white, size: 18),
                onPressed: () => _openFullscreen(url),
              ),
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _autoRotateTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeItems = _enabledItems;

    if (activeItems.isEmpty) {
      return const Text(
        'Carousel enabled but no active reels.',
        style: TextStyle(color: Colors.white70),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.slideshow, color: Colors.amber, size: 16),
            const SizedBox(width: 8),
            Text(
              'Reel Carousel (${activeItems.length})',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 250,
          child: Stack(
            children: [
              PageView.builder(
                controller: _pageController,
                itemCount: activeItems.length,
                onPageChanged: (index) {
                  setState(() => _currentPage = index);
                  _scheduleNextAutoRotate();
                },
                // No physics override — default scroll physics for swipe.
                itemBuilder: (context, index) {
                  final item = activeItems[index];
                  final title = (item['title'] as String?)?.trim() ?? '';
                  final caption = (item['caption'] as String?)?.trim() ?? '';

                  return ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      color: Colors.black54,
                      child: Column(
                        children: [
                          Expanded(child: _buildMedia(item)),
                          if (title.isNotEmpty || caption.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (title.isNotEmpty)
                                    Text(
                                      title,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  if (caption.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        caption,
                                        style: const TextStyle(
                                          color: Colors.white70,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              if (activeItems.length > 1)
                Positioned(
                  left: 8,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.4),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: const Icon(
                          Icons.arrow_back_ios_new,
                          color: Colors.white,
                          size: 18,
                        ),
                        tooltip: 'Previous reel',
                        onPressed: () => _goToPreviousPage(activeItems.length),
                      ),
                    ),
                  ),
                ),
              if (activeItems.length > 1)
                Positioned(
                  right: 8,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.4),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: const Icon(
                          Icons.arrow_forward_ios,
                          color: Colors.white,
                          size: 18,
                        ),
                        tooltip: 'Next reel',
                        onPressed: () => _goToNextPage(activeItems.length),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (activeItems.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${_currentPage + 1} / ${activeItems.length}',
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Flip card: front = featured content, back = reel carousel.
// Flip is only available when admin enables BOTH showFeatured + showReelCarousel.
// Flip triggers (front → back): amber carousel icon (top-right) OR horizontal swipe.
// Return trigger (back → front): back arrow button (top-left). Tapping the carousel
// itself is reserved for pause/play/swipe between reel items.
// ---------------------------------------------------------------------------
class _FlipContentCard extends StatefulWidget {
  final String featuredType;
  final String featuredUrl;
  final String featuredTitle;
  final String featuredBody;
  final List<Map<String, dynamic>> reelItems;
  final int autoRotateSeconds;
  final bool isVisible;

  const _FlipContentCard({
    required this.featuredType,
    required this.featuredUrl,
    required this.featuredTitle,
    required this.featuredBody,
    required this.reelItems,
    required this.autoRotateSeconds,
    required this.isVisible,
  });

  @override
  State<_FlipContentCard> createState() => _FlipContentCardState();
}

class _FlipContentCardState extends State<_FlipContentCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;
  bool _showBack = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _animation = Tween<double>(begin: 0.0, end: pi).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    // Once the reverse animation finishes, mark _showBack = false so the
    // carousel widget pauses (stops its auto-rotate timer).
    _animation.addStatusListener((status) {
      if (status == AnimationStatus.dismissed && mounted) {
        setState(() => _showBack = false);
      }
    });
  }

  @override
  void didUpdateWidget(covariant _FlipContentCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the home tab becomes invisible (user switches tabs), silently flip back.
    if (!widget.isVisible && oldWidget.isVisible && _showBack) {
      _controller.value = 0.0;
      _showBack = false;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _flipToCarousel() {
    if (_showBack) return;
    setState(() => _showBack = true);
    _controller.forward();
  }

  void _flipToFront() {
    if (!_showBack) return;
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        final angle = _animation.value;
        final isShowingFront = angle <= pi / 2;

        final Widget face = isShowingFront
            ? _buildFrontFace()
            : Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()..rotateY(pi),
                child: _buildBackFace(),
              );

        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateY(angle),
          child: face,
        );
      },
    );
  }

  Widget _buildFrontFace() {
    return GestureDetector(
      // Swipe left or right on the card to flip to the carousel.
      onHorizontalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0).abs() > 300) _flipToCarousel();
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 24),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white24),
        ),
        child: Stack(
          children: [
            Column(
              children: [
                if (widget.featuredTitle.isNotEmpty)
                  Padding(
                    // Extra right padding so text doesn't overlap the flip button.
                    padding: const EdgeInsets.only(bottom: 8, right: 36),
                    child: Text(
                      widget.featuredTitle,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                if (widget.featuredBody.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      widget.featuredBody,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                _FeaturedContentWidget(
                  type: widget.featuredType,
                  url: widget.featuredUrl,
                  // Pause the featured media while the back face is shown.
                  isVisible: widget.isVisible && !_showBack,
                ),
              ],
            ),
            // ── Carousel flip trigger ──────────────────────────────────────
            Positioned(
              top: 0,
              right: 0,
              child: Tooltip(
                message: 'View Reel Carousel',
                child: GestureDetector(
                  onTap: _flipToCarousel,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.view_carousel_outlined,
                      color: Colors.amberAccent,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackFace() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amberAccent.withOpacity(0.35)),
      ),
      child: Stack(
        children: [
          // Offset content below the back button row.
          Padding(
            padding: const EdgeInsets.only(top: 34),
            child: _HomeReelCarousel(
              items: widget.reelItems,
              autoRotateSeconds: widget.autoRotateSeconds,
              // Only active while back face is actually showing.
              isVisible: widget.isVisible && _showBack,
            ),
          ),
          // ── Return to featured button ──────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            child: Tooltip(
              message: 'Back to featured',
              child: GestureDetector(
                onTap: _flipToFront,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_back,
                    color: Colors.white,
                    size: 20,
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

class _ActiveUsersChip extends StatefulWidget {
  const _ActiveUsersChip();

  @override
  State<_ActiveUsersChip> createState() => _ActiveUsersChipState();
}

class _ActiveUsersChipState extends State<_ActiveUsersChip> {
  static const Duration _refreshInterval = Duration(hours: 1);
  late Future<int> _activeUsersFuture;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _activeUsersFuture = _loadActiveUsers();
    _refreshTimer = Timer.periodic(_refreshInterval, (_) {
      if (!mounted) return;
      setState(() {
        _activeUsersFuture = _loadActiveUsers();
      });
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<int> _loadActiveUsers() async {
    final cutoff = Timestamp.fromDate(
      DateTime.now().subtract(_refreshInterval),
    );
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('lastActive', isGreaterThan: cutoff)
        .count()
        .get();
    return snapshot.count ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: _activeUsersFuture,
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.2),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.green.withOpacity(0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.circle, color: Colors.green, size: 12),
              const SizedBox(width: 8),
              Text(
                '$count Active In Last Hour',
                style: const TextStyle(
                  color: Colors.greenAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FeaturedContentWidget extends StatefulWidget {
  final String type;
  final String url;
  final bool isVisible;

  const _FeaturedContentWidget({
    required this.type,
    required this.url,
    this.isVisible = true,
  });

  @override
  State<_FeaturedContentWidget> createState() => _FeaturedContentWidgetState();
}

class _FeaturedContentWidgetState extends State<_FeaturedContentWidget> {
  bool _isYoutubeUrl(String url) {
    return url.contains('youtu') || (url.length == 11 && !url.contains('/'));
  }

  void _openFeaturedFullscreen(String type) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _ReelsFullscreenScreen(
          items: [
            {
              'url': widget.url,
              'type': type,
              'title': '',
              'caption': '',
              'enabled': true,
            },
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.url.isEmpty) return const SizedBox();

    String effectiveType = widget.type;
    if (_isYoutubeUrl(widget.url)) {
      effectiveType = 'youtube';
    }

    switch (effectiveType) {
      case 'youtube':
        final videoId = YoutubePlayer.convertUrlToId(widget.url);
        final thumbUrl = videoId != null
            ? 'https://img.youtube.com/vi/$videoId/hqdefault.jpg'
            : '';

        return GestureDetector(
          onTap: () => _openFeaturedFullscreen('youtube'),
          child: Container(
            height: 200,
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 24),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (thumbUrl.isNotEmpty)
                    Image.network(
                      thumbUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, _, __) => Container(
                        color: Colors.black,
                      ),
                    )
                  else
                    Container(color: Colors.black),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.4),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.play_arrow,
                        size: 40,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

      case 'image':
        return Container(
          height: 200,
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 24),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(16),
            image: DecorationImage(
              image: NetworkImage(widget.url),
              fit: BoxFit.cover,
            ),
          ),
        );

      case 'video':
        return GestureDetector(
          onTap: () => _openFeaturedFullscreen('video'),
          child: Container(
            height: 200,
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 24),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(color: Colors.black),
                  const Center(
                    child: Icon(
                      Icons.ondemand_video,
                      color: Colors.white54,
                      size: 48,
                    ),
                  ),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.4),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.play_arrow,
                        size: 40,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

      case 'pdf':
        return GestureDetector(
          onTap: () => launchUrl(Uri.parse(widget.url)),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            margin: const EdgeInsets.only(bottom: 24),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white30),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.picture_as_pdf,
                  color: Colors.redAccent,
                  size: 40,
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Featured Document',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        'Tap to view PDF',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.open_in_new, color: Colors.grey.shade400),
              ],
            ),
          ),
        );

      default:
        return const SizedBox();
    }
  }
}

class _BackgroundWidget extends StatefulWidget {
  final String url;

  const _BackgroundWidget({required this.url});

  @override
  State<_BackgroundWidget> createState() => _BackgroundWidgetState();
}

class _BackgroundWidgetState extends State<_BackgroundWidget> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(_BackgroundWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.url != oldWidget.url) {
      _init();
    }
  }

  void _init() {
    _controller?.dispose();
    _controller = null;

    if (_isVideo(widget.url)) {
      _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
        ..initialize().then((_) {
          _controller!.setLooping(true);
          _controller!.setVolume(0); // Muted background
          _controller!.play();
          if (mounted) setState(() {});
        });
    }
  }

  bool _isVideo(String url) {
    final lower = url.toLowerCase();
    return lower.contains('.mp4') ||
        lower.contains('.mov') ||
        lower.contains('video');
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller != null && _controller!.value.isInitialized) {
      return Stack(
        fit: StackFit.expand,
        children: [
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: _controller!.value.size.width,
              height: _controller!.value.size.height,
              child: VideoPlayer(_controller!),
            ),
          ),
          Container(color: Colors.black.withOpacity(0.4)), // Dark overlay
        ],
      );
    }

    return Image.network(
      widget.url,
      fit: BoxFit.cover,
      color: Colors.black.withOpacity(0.4),
      colorBlendMode: BlendMode.darken,
      errorBuilder: (c, e, s) => Container(color: Colors.black),
    );
  }
}
