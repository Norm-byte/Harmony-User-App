import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart'; // Added for caching
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import '../../services/user_service.dart';

class ContentViewer extends StatelessWidget {
  final String url;
  final bool controls;
  final bool autoPlay; // Added autoPlay
  final bool loop; // Added loop
  final BoxFit fit;

  const ContentViewer({
    super.key,
    required this.url,
    this.controls = true,
    this.autoPlay = false,
    this.loop = false,
    this.fit = BoxFit.contain,
  });

  @override
  Widget build(BuildContext context) {
    final userService = Provider.of<UserService>(context, listen: false);
    final volume = userService.eventVolume;

    if (url.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.image, color: Colors.white24, size: 48),
            SizedBox(height: 8),
            Text('No Content', style: TextStyle(color: Colors.white54)),
          ],
        ),
      );
    }

    final isVideo =
        url.toLowerCase().contains('.mp4') ||
        url.toLowerCase().contains('.mov') ||
        url.toLowerCase().contains('.webm') ||
        url.toLowerCase().contains('.mpeg') ||
        url.toLowerCase().contains('.mpg') ||
        url.toLowerCase().contains('.avi') ||
        url.toLowerCase().contains('.mkv') ||
        url.toLowerCase().contains('.mp3') || // Added Audio
        url.toLowerCase().contains('.wav') ||
        url.toLowerCase().contains('.aac') ||
        url.toLowerCase().contains('.m4a');

    final isPdf = url.toLowerCase().contains('.pdf');
    final isDoc =
        url.toLowerCase().contains('.ppt') ||
        url.toLowerCase().contains('.pptx') ||
        url.toLowerCase().contains('.doc') ||
        url.toLowerCase().contains('.docx');

    // Check for YouTube
    final isYoutube = url.contains('youtube.com') || url.contains('youtu.be');

    if (isYoutube) {
      return _NativeYoutubePlayer(url: url, autoPlay: autoPlay, volume: volume);
    }

    if (isVideo) {
      return _NativeVideoPlayer(
        url: url,
        controls: controls,
        autoPlay: autoPlay,
        loop: loop,
        fit: fit,
        volume: volume,
      );
    } else if (isPdf) {
      return SfPdfViewer.network(
        url,
        enableDoubleTapZooming: true,
        canShowScrollHead: true,
        canShowScrollStatus: true,
      );
    } else if (isDoc) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.description, color: Colors.white, size: 48),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => launchUrl(
                Uri.parse(url),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open Document'),
            ),
          ],
        ),
      );
    }

    return Image.network(
      url,
      fit: fit,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Center(
          child: CircularProgressIndicator(
            value: loadingProgress.expectedTotalBytes != null
                ? loadingProgress.cumulativeBytesLoaded /
                      loadingProgress.expectedTotalBytes!
                : null,
            color: Colors.white,
          ),
        );
      },
      errorBuilder: (_, __, ___) =>
          const Center(child: Icon(Icons.broken_image, color: Colors.white)),
    );
  }
}

class _NativeYoutubePlayer extends StatefulWidget {
  final String url;
  final bool autoPlay;
  final double volume;

  const _NativeYoutubePlayer({
    required this.url,
    this.autoPlay = false,
    required this.volume,
  });

  @override
  State<_NativeYoutubePlayer> createState() => _NativeYoutubePlayerState();
}

class _NativeYoutubePlayerState extends State<_NativeYoutubePlayer> {
  late YoutubePlayerController _controller;

  String? _extractVideoId(String url) {
    // 1. Try library function first
    String? id = YoutubePlayer.convertUrlToId(url);
    if (id != null) return id;

    // 2. Manual fallback for Shorts/Live
    try {
      final uri = Uri.parse(url);
      if (uri.pathSegments.contains('shorts')) {
        final index = uri.pathSegments.indexOf('shorts');
        if (index + 1 < uri.pathSegments.length)
          return uri.pathSegments[index + 1];
      }
      if (uri.pathSegments.contains('live')) {
        final index = uri.pathSegments.indexOf('live');
        if (index + 1 < uri.pathSegments.length)
          return uri.pathSegments[index + 1];
      }
    } catch (_) {}

    return null;
  }

  @override
  void initState() {
    super.initState();
    final videoId = _extractVideoId(widget.url);
    debugPrint('YoutubePlayer: URL: ${widget.url}');
    debugPrint('YoutubePlayer: Extracted ID: $videoId');

    _controller = YoutubePlayerController(
      initialVideoId: videoId ?? '',
      flags: YoutubePlayerFlags(
        autoPlay: widget.autoPlay, // Use widget.autoPlay
        mute: false,
        enableCaption: false,
        forceHD: false,
        loop: true,
      ),
    );

    // Set volume after init
    // Youtube volume is 0-100
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _controller.setVolume((widget.volume * 100).toInt());
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final videoId = _extractVideoId(widget.url);
    if (videoId == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, color: Colors.red, size: 48),
            const SizedBox(height: 8),
            Text(
              'Invalid Video ID\nURL: ${widget.url}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
      );
    }

    return YoutubePlayerBuilder(
      player: YoutubePlayer(
        controller: _controller,
        showVideoProgressIndicator: true,
        progressIndicatorColor: Colors.amber,
        progressColors: const ProgressBarColors(
          playedColor: Colors.amber,
          handleColor: Colors.amberAccent,
        ),
        onReady: () {
          // _controller.addListener(listener);
        },
      ),
      builder: (context, player) {
        return Center(child: player);
      },
    );
  }
}

class _NativeVideoPlayer extends StatefulWidget {
  final String url;
  final bool controls;
  final bool autoPlay;
  final bool loop;
  final BoxFit fit;
  final double volume;

  const _NativeVideoPlayer({
    required this.url,
    required this.controls,
    required this.autoPlay,
    required this.loop,
    required this.fit,
    required this.volume,
  });

  @override
  State<_NativeVideoPlayer> createState() => _NativeVideoPlayerState();
}

class _NativeVideoPlayerState extends State<_NativeVideoPlayer>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _initFailed = false;
  DateTime? _lastAutoResume;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializePlayer();
  }

  @override
  void didUpdateWidget(covariant _NativeVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _controller?.dispose();
      _controller = null;
      _initialized = false;
      _initFailed = false;
      _initializePlayer();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _controller != null &&
        _initialized &&
        widget.autoPlay &&
        !widget.controls &&
        !_controller!.value.isPlaying) {
      _controller!.play();
    }
  }

  void _attachPlaybackGuard() {
    _controller?.addListener(() {
      final controller = _controller;
      if (controller == null ||
          !_initialized ||
          !widget.autoPlay ||
          widget.controls) {
        return;
      }

      final value = controller.value;
      if (!value.isInitialized || value.hasError) {
        return;
      }

      if (!value.isPlaying && !value.isCompleted) {
        final now = DateTime.now();
        if (_lastAutoResume == null ||
            now.difference(_lastAutoResume!) >
                const Duration(milliseconds: 750)) {
          _lastAutoResume = now;
          controller.play();
        }
      }
    });
  }

  Future<void> _initializePlayer() async {
    try {
      // CACHE STRATEGY IMPROVED (v4+):
      // 1. Check if file exists in cache WITHOUT blocking for download.
      // 2. If cached -> Play file (Instant).
      // 3. If NOT cached -> Stream from Network (Instant Start) while caching in background.

      final fileInfo = await DefaultCacheManager().getFileFromCache(widget.url);

      if (fileInfo != null && await fileInfo.file.exists()) {
        debugPrint("Playing from local cache: ${widget.url}");
        _controller = VideoPlayerController.file(fileInfo.file);
      } else {
        debugPrint(
          "File not in cache. Streaming network URL for immediate playback: ${widget.url}",
        );
        _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));

        // Verify connection/validity implicitly by letting initialize() run below.
        // Trigger background download for next time (Fire and Forget)
        DefaultCacheManager()
            .downloadFile(widget.url)
            .then((_) {
              debugPrint("Background download complete for: ${widget.url}");
            })
            .catchError((e) {
              debugPrint("Background download failed (non-fatal): $e");
            });
      }
    } catch (e) {
      debugPrint("Player init error: $e. Fallback to network stream.");
      _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    }

    try {
      await _controller!.initialize().timeout(const Duration(seconds: 10));
      if (mounted) {
        setState(() {
          _initialized = true;
          _initFailed = false;
        });
        _controller!.setVolume(widget.volume);
        _controller!.setLooping(widget.loop);
        _attachPlaybackGuard();
        if (widget.autoPlay) {
          _controller!.play();
        }
      }
    } catch (e) {
      debugPrint('Video initialize failed for ${widget.url}: $e');
      if (mounted) {
        setState(() {
          _initFailed = true;
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_initFailed) {
      return const Center(
        child: Icon(Icons.broken_image, color: Colors.white54, size: 42),
      );
    }

    if (!_initialized || _controller == null) {
      return Container(
        color: Colors.transparent,
        alignment: Alignment.center,
        child: const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white30,
          ),
        ),
      );
    }

    return Container(
      color: Colors.black,
      width: MediaQuery.of(context).size.width,
      height: MediaQuery.of(context).size.height,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: FittedBox(
              fit: widget.fit, // Use the passed fit (BoxFit.cover)
              alignment: Alignment.center,
              child: SizedBox(
                width: _controller!.value.size.width,
                height: _controller!.value.size.height,
                child: VideoPlayer(_controller!),
              ),
            ),
          ),
          if (widget.controls)
            GestureDetector(
              onTap: () {
                setState(() {
                  _controller!.value.isPlaying
                      ? _controller!.pause()
                      : _controller!.play();
                });
              },
              child: Container(
                color: Colors.transparent,
                child: Center(
                  child: Icon(
                    _controller!.value.isPlaying
                        ? Icons.pause
                        : Icons.play_arrow,
                    color: Colors.white.withValues(alpha: 0.7),
                    size: 48,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
