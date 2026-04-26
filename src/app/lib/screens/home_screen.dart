import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:provider/provider.dart';
import '../services/event_service.dart';
import '../models/event.dart';
import '../widgets/media/content_viewer.dart';
import '../widgets/gradient_scaffold.dart';
import 'events_screen.dart';
import 'community_feed_screen.dart';
import 'interesting_topics_screen.dart';
import 'settings_screen.dart';
import 'app_settings_screen.dart';
import 'video_player_screen.dart';

class HomeScreen extends StatefulWidget {
  final bool isSuperAdmin;

  const HomeScreen({super.key, this.isSuperAdmin = false});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

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

                        // Content card: flip card when BOTH carousel + featured active.
                        // When only one is active it renders as a plain card (existing behaviour).
                        if (showReelCarousel && showFeatured)
                          _FlipContentCard(
                            featuredType: featuredType,
                            featuredUrl: featuredUrl,
                            featuredTitle: featuredTitle,
                            featuredBody: featuredBody,
                            reelItems: reelItems,
                            autoRotateSeconds: reelAutoRotateSeconds,
                            isVisible: isVisible,
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
                            child: _HomeReelCarousel(
                              items: reelItems,
                              autoRotateSeconds: reelAutoRotateSeconds,
                              isVisible: isVisible,
                            ),
                          )
                        else if (showFeatured)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 24),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: Column(
                              children: [
                                if (featuredTitle.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
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
                                    padding: const EdgeInsets.only(bottom: 12),
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
      }).toList();

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _restartAutoRotate();
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
      _restartAutoRotate();
    }
  }

  void _restartAutoRotate() {
    _autoRotateTimer?.cancel();
    final active = _enabledItems;
    if (!widget.isVisible || active.length < 2) return;

    final seconds = widget.autoRotateSeconds.clamp(4, 20);
    _autoRotateTimer = Timer.periodic(Duration(seconds: seconds), (_) {
      if (!mounted || !_pageController.hasClients) return;
      final nextPage = (_currentPage + 1) % active.length;
      _pageController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeInOut,
      );
    });
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
    final supportsFullscreen = type == 'video' || type == 'youtube';

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

    return Stack(
      children: [
        Positioned.fill(
          child: ContentViewer(
            url: url,
            fit: BoxFit.cover,
            controls: type != 'image',
            autoPlay: true,
            loop: true,
          ),
        ),
        if (supportsFullscreen)
          Positioned(
            top: 8,
            right: 8,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.45),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.fullscreen, color: Colors.white),
                tooltip: 'Open full screen',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => VideoPlayerScreen(videoUrl: url),
                    ),
                  );
                },
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
          child: PageView.builder(
            controller: _pageController,
            itemCount: activeItems.length,
            onPageChanged: (index) {
              setState(() => _currentPage = index);
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
                                    style: const TextStyle(color: Colors.white70),
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
  VideoPlayerController? _videoController;
  YoutubePlayerController? _youtubeController;
  bool _isInitialized = false;
  bool _hasError = false;

  bool _isYoutubeUrl(String url) {
    return url.contains('youtu') || (url.length == 11 && !url.contains('/'));
  }

  @override
  void initState() {
    super.initState();
    if (widget.url.isNotEmpty) {
      if (_isYoutubeUrl(widget.url)) {
        _initializeYoutube();
      } else if (widget.type == 'video') {
        _initializeVideo();
      }
    }
  }

  @override
  void didUpdateWidget(_FeaturedContentWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.url != oldWidget.url || widget.type != oldWidget.type) {
      _disposeVideo();
      if (widget.url.isNotEmpty) {
        if (_isYoutubeUrl(widget.url)) {
          _initializeYoutube();
        } else if (widget.type == 'video') {
          _initializeVideo();
        }
      }
    }

    if (widget.isVisible != oldWidget.isVisible) {
      if (!widget.isVisible) {
        _videoController?.pause();
        _youtubeController?.pause();
      } else {
        // Optional: Auto-resume when coming back?
        // _videoController?.play();
      }
    }
  }

  void _initializeYoutube() {
    final videoId = YoutubePlayer.convertUrlToId(widget.url);
    if (videoId != null) {
      _youtubeController = YoutubePlayerController(
        initialVideoId: videoId,
        flags: const YoutubePlayerFlags(
          autoPlay: false,
          mute: false,
          enableCaption: false,
          disableDragSeek: true,
          loop: false,
          isLive: false,
          forceHD: false,
        ),
      );
      setState(() => _isInitialized = true);
    } else {
      setState(() => _hasError = true);
    }
  }

  Future<void> _initializeVideo() async {
    try {
      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(widget.url),
      );

      // Add timeout to initialization
      await _videoController!.initialize().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Video initialization timed out');
        },
      );

      _videoController!.setLooping(true);
      // Auto-play for shorts style feel, but muted to be polite? Or let user tap?
      // Let's auto-play muted for "Shorts" feel.
      await _videoController!.setVolume(0.0);
      await _videoController!.play();
      if (mounted) setState(() => _isInitialized = true);
    } catch (e) {
      debugPrint('Error initializing video: $e');
      if (mounted) setState(() => _hasError = true);
    }
  }

  void _disposeVideo() {
    _videoController?.dispose();
    _videoController = null;
    _youtubeController?.dispose();
    _youtubeController = null;
    _isInitialized = false;
    _hasError = false;
  }

  @override
  void dispose() {
    _disposeVideo();
    super.dispose();
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
        if (_hasError) {
          return Container(
            height: 200,
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 24),
            color: Colors.black,
            alignment: Alignment.center,
            child: const Text(
              'Error loading YouTube video',
              style: TextStyle(color: Colors.white),
            ),
          );
        }

        if (_youtubeController == null) {
          return Container(
            height: 200,
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 24),
            color: Colors.black,
            alignment: Alignment.center,
            child: const CircularProgressIndicator(color: Colors.white),
          );
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 24),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                YoutubePlayerBuilder(
                  player: YoutubePlayer(
                    controller: _youtubeController!,
                    showVideoProgressIndicator: true,
                    progressIndicatorColor: Colors.amber,
                    progressColors: const ProgressBarColors(
                      playedColor: Colors.amber,
                      handleColor: Colors.amberAccent,
                    ),
                    onReady: () {
                      // _youtubeController!.addListener(listener);
                    },
                  ),
                  builder: (context, player) => player,
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.45),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.fullscreen, color: Colors.white),
                      tooltip: 'Open full screen',
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => VideoPlayerScreen(videoUrl: widget.url),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
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
        final controller = _videoController;
        if (_hasError) {
          return Container(
            height: 200,
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 24),
            color: Colors.black,
            alignment: Alignment.center,
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, color: Colors.red, size: 48),
                SizedBox(height: 8),
                Text(
                  'Unable to load video',
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
          );
        }

        if (!_isInitialized || controller == null) {
          return Container(
            height: 200,
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 24),
            color: Colors.black,
            alignment: Alignment.center,
            child: const CircularProgressIndicator(color: Colors.white),
          );
        }

        final isMuted = controller.value.volume == 0;
        final isPlaying = controller.value.isPlaying;

        return GestureDetector(
          onTap: () {
            setState(() {
              if (controller.value.isPlaying) {
                controller.pause();
              } else {
                controller.play();
              }
            });
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 24),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AnimatedScale(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                scale: isPlaying ? 1.06 : 1.0,
                child: AspectRatio(
                  aspectRatio: controller.value.aspectRatio,
                  child: Stack(
                    children: [
                      VideoPlayer(controller),

                    // Play/Pause Overlay
                    if (!isPlaying)
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

                      Positioned(
                        top: 8,
                        right: 8,
                        child: IconButton(
                          icon: const Icon(
                            Icons.fullscreen,
                            color: Colors.white,
                          ),
                          tooltip: 'Open full screen',
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    VideoPlayerScreen(videoUrl: widget.url),
                              ),
                            );
                          },
                        ),
                      ),

                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: IconButton(
                          icon: Icon(
                            isMuted ? Icons.volume_off : Icons.volume_up,
                            color: Colors.white,
                          ),
                          onPressed: () {
                            setState(() {
                              controller.setVolume(isMuted ? 1.0 : 0.0);
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),
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
