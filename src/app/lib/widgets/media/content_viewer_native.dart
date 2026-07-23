import 'dart:async';

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

    // Check for YouTube links across common host variants.
    final parsed = Uri.tryParse(url);
    final host = (parsed?.host ?? '').toLowerCase();
    final lowerUrl = url.toLowerCase();
    final isYoutube =
      host.contains('youtube.com') ||
      host.contains('youtu.be') ||
      host.contains('youtube-nocookie.com') ||
      host.contains('m.youtube.com') ||
      lowerUrl.contains('youtube.com') ||
      lowerUrl.contains('youtu.be');

    debugPrint(
      'CV_BRANCH: host=$host isYoutube=$isYoutube isVideo=$isVideo isPdf=$isPdf isDoc=$isDoc url=$url',
    );

    if (isYoutube) {
      debugPrint('CV_BRANCH: using _NativeYoutubePlayer fit=$fit controls=$controls');
      return _NativeYoutubePlayer(
        url: url,
        autoPlay: autoPlay,
        loop: loop,
        volume: volume,
        fit: fit,
      );
    }

    if (isVideo) {
      debugPrint('CV_BRANCH: using _NativeVideoPlayer fit=$fit controls=$controls');
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
  final bool loop;
  final double volume;
  final BoxFit fit;

  const _NativeYoutubePlayer({
    required this.url,
    this.autoPlay = false,
    this.loop = false,
    required this.volume,
    this.fit = BoxFit.contain,
  });

  @override
  State<_NativeYoutubePlayer> createState() => _NativeYoutubePlayerState();
}

class _NativeYoutubePlayerState extends State<_NativeYoutubePlayer> {
  late YoutubePlayerController _controller;
  bool _isReady = false;
  bool _repeatEnabled = false;
  bool _showControlsOverlay = false;
  double? _scrubValueMs;
  Timer? _controlsHideTimer;

  String? _extractVideoId(String url) {
    String? id = YoutubePlayer.convertUrlToId(url);
    if (id != null) return id;

    try {
      final uri = Uri.parse(url);
      if (uri.pathSegments.contains('shorts')) {
        final index = uri.pathSegments.indexOf('shorts');
        if (index + 1 < uri.pathSegments.length) {
          return uri.pathSegments[index + 1];
        }
      }
      if (uri.pathSegments.contains('live')) {
        final index = uri.pathSegments.indexOf('live');
        if (index + 1 < uri.pathSegments.length) {
          return uri.pathSegments[index + 1];
        }
      }
    } catch (_) {}

    return null;
  }

  @override
  void initState() {
    super.initState();
    final videoId = _extractVideoId(widget.url);

    _controller = YoutubePlayerController(
      initialVideoId: videoId ?? '',
      flags: YoutubePlayerFlags(
        autoPlay: widget.autoPlay,
        mute: false,
        enableCaption: false,
        forceHD: false,
        loop: false,
        hideControls: true,
        controlsVisibleAtStart: false,
        disableDragSeek: true,
        hideThumbnail: true,
      ),
    );

    _repeatEnabled = widget.loop;
    _controller.addListener(_onControllerUpdate);

    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        _controller.setVolume((widget.volume * 100).toInt());
      }
    });
  }

  @override
  void dispose() {
    _controlsHideTimer?.cancel();
    _controller.removeListener(_onControllerUpdate);
    _controller.dispose();
    super.dispose();
  }

  double _durationMs() {
    final value = _controller.metadata.duration.inMilliseconds;
    if (value > 0) return value.toDouble();
    return 1;
  }

  double _currentSliderValueMs() {
    final durationMs = _durationMs();
    final currentMs =
        _scrubValueMs ?? _controller.value.position.inMilliseconds.toDouble();
    return currentMs.clamp(0, durationMs);
  }

  String _formatDuration(Duration value) {
    final totalSeconds = value.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }

    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  void _showControlsBriefly() {
    _controlsHideTimer?.cancel();
    setState(() => _showControlsOverlay = true);
    _controlsHideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() => _showControlsOverlay = false);
      }
    });
  }

  void _togglePlayPause() {
    if (_controller.value.isPlaying) {
      _controller.pause();
    } else {
      _controller.play();
    }
    _showControlsBriefly();
  }

  void _handlePrimaryTap() {
    if (!_isReady) return;

    if (!_controller.value.isPlaying) {
      _controller.play();
      return;
    }

    if (_showControlsOverlay) {
      _showControlsBriefly();
      return;
    }

    _showControlsBriefly();
  }

  void _onControllerUpdate() {
    if (!mounted) return;

    if (_repeatEnabled &&
        _controller.value.playerState == PlayerState.ended &&
        !_controller.value.isPlaying) {
      _controller.seekTo(Duration.zero);
      _controller.play();
    }

    if (_showControlsOverlay || !_controller.value.isPlaying) {
      setState(() {});
    }
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

    Widget buildYoutubeSurface(Widget player) {
      return SizedBox.expand(
        child: Center(
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: 16 * 100,
              height: 9 * 100,
              child: IgnorePointer(
                ignoring: true,
                child: player,
              ),
            ),
          ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Container(color: Colors.black),
        YoutubePlayerBuilder(
          player: YoutubePlayer(
            controller: _controller,
            showVideoProgressIndicator: false,
            onReady: () {
              if (!mounted) return;
              setState(() => _isReady = true);
            },
          ),
          builder: (context, player) => AnimatedOpacity(
            duration: const Duration(milliseconds: 180),
            opacity: _isReady ? 1 : 0,
            child: buildYoutubeSurface(player),
          ),
        ),
        if (!_isReady)
          const Center(
            child: CircularProgressIndicator(color: Colors.white70),
          ),
        if (_isReady)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _handlePrimaryTap,
              child: const SizedBox.expand(),
            ),
          ),
        if (_isReady && _showControlsOverlay)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.58),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white24),
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip: _controller.value.isPlaying ? 'Pause' : 'Play',
                    onPressed: _togglePlayPause,
                    icon: Icon(
                      _controller.value.isPlaying
                          ? Icons.pause_circle_filled
                          : Icons.play_circle_fill,
                      color: Colors.white,
                    ),
                  ),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 2.5,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 6,
                            ),
                          ),
                          child: Slider(
                            min: 0,
                            max: _durationMs(),
                            value: _currentSliderValueMs(),
                            activeColor: Colors.white,
                            inactiveColor: Colors.white24,
                            onChanged: (value) {
                              setState(() => _scrubValueMs = value);
                            },
                            onChangeEnd: (value) {
                              _controller.seekTo(
                                Duration(milliseconds: value.toInt()),
                              );
                              setState(() => _scrubValueMs = null);
                              _showControlsBriefly();
                            },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            '${_formatDuration(_controller.value.position)} / ${_formatDuration(_controller.metadata.duration)}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: _repeatEnabled ? 'Repeat on' : 'Repeat off',
                    icon: Icon(
                      Icons.repeat,
                      color:
                          _repeatEnabled ? Colors.amberAccent : Colors.white70,
                    ),
                    onPressed: () {
                      setState(() => _repeatEnabled = !_repeatEnabled);
                      _showControlsBriefly();
                    },
                  ),
                ],
              ),
            ),
          ),
      ],
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
  bool _repeatEnabled = false;
  bool _showControlsOverlay = false;
  double? _scrubValueMs;
  Timer? _controlsHideTimer;
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
      _controlsHideTimer?.cancel();
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

  double _currentSliderValueMs() {
    final controller = _controller;
    if (controller == null) return 0;
    final durationMs = controller.value.duration.inMilliseconds;
    if (durationMs <= 0) return 0;
    final currentMs =
        _scrubValueMs ?? controller.value.position.inMilliseconds.toDouble();
    return currentMs.clamp(0, durationMs.toDouble());
  }

  Duration _durationFromMs(double value) => Duration(milliseconds: value.toInt());

  String _formatDuration(Duration value) {
    final totalSeconds = value.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }

    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  void _showControlsBriefly() {
    _controlsHideTimer?.cancel();
    setState(() => _showControlsOverlay = true);
    _controlsHideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() => _showControlsOverlay = false);
      }
    });
  }

  void _hideControls() {
    _controlsHideTimer?.cancel();
    if (_showControlsOverlay) {
      setState(() => _showControlsOverlay = false);
    }
  }

  Future<void> _seekRelative(int deltaSeconds) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    final duration = controller.value.duration;
    final current = controller.value.position;
    final next = current + Duration(seconds: deltaSeconds);

    Duration clamped = next;
    if (clamped < Duration.zero) clamped = Duration.zero;
    if (duration > Duration.zero && clamped > duration) clamped = duration;

    await controller.seekTo(clamped);
  }

  Future<void> _toggleRepeat() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final next = !_repeatEnabled;
    setState(() => _repeatEnabled = next);
    await controller.setLooping(next);
  }

  void _handlePrimaryTap() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    if (!widget.controls) {
      setState(() {
        controller.value.isPlaying ? controller.pause() : controller.play();
      });
      return;
    }

    if (_showControlsOverlay) {
      _showControlsBriefly();
      return;
    }

    if (!controller.value.isPlaying) {
      setState(() => controller.play());
      return;
    }

    _showControlsBriefly();
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
          _repeatEnabled = widget.loop;
        });
        _controller!.setVolume(widget.volume);
        _controller!.setLooping(widget.loop);
        _attachPlaybackGuard();
        _controller!.addListener(() {
          if (!mounted) return;
          if (_showControlsOverlay) {
            setState(() {});
          }
        });
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
    _controlsHideTimer?.cancel();
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
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _handlePrimaryTap,
                child: const SizedBox.expand(),
              ),
            ),
          if (widget.controls && _showControlsOverlay)
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        overlayShape: SliderComponentShape.noOverlay,
                        trackHeight: 2.8,
                      ),
                      child: Slider(
                        value: _controller!.value.duration.inMilliseconds <= 0
                            ? 0
                            : _currentSliderValueMs(),
                        min: 0,
                        max: _controller!.value.duration.inMilliseconds <= 0
                            ? 1
                            : _controller!.value.duration.inMilliseconds.toDouble(),
                        onChangeStart: (_) => setState(() {
                          _scrubValueMs = _currentSliderValueMs();
                        }),
                        onChanged: (value) => setState(() => _scrubValueMs = value),
                        onChangeEnd: (value) async {
                          setState(() => _scrubValueMs = null);
                          await _controller!.seekTo(_durationFromMs(value));
                        },
                      ),
                    ),
                    Row(
                      children: [
                        Text(
                          _formatDuration(_controller!.value.position),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Back 10 seconds',
                          icon: const Icon(Icons.replay_10, color: Colors.white70),
                          onPressed: () {
                            _showControlsBriefly();
                            unawaited(_seekRelative(-10));
                          },
                        ),
                        IconButton(
                          tooltip: _controller!.value.isPlaying ? 'Pause' : 'Play',
                          icon: Icon(
                            _controller!.value.isPlaying
                                ? Icons.pause_circle_filled
                                : Icons.play_circle_fill,
                            color: Colors.white,
                          ),
                          onPressed: () {
                            _showControlsBriefly();
                            setState(() {
                              _controller!.value.isPlaying
                                  ? _controller!.pause()
                                  : _controller!.play();
                            });
                          },
                        ),
                        IconButton(
                          tooltip: 'Forward 10 seconds',
                          icon: const Icon(Icons.forward_10, color: Colors.white70),
                          onPressed: () {
                            _showControlsBriefly();
                            unawaited(_seekRelative(10));
                          },
                        ),
                        const Spacer(),
                        Text(
                          _formatDuration(_controller!.value.duration),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                          tooltip: _repeatEnabled ? 'Repeat on' : 'Repeat off',
                          icon: Icon(
                            Icons.repeat,
                            color: _repeatEnabled
                                ? Colors.amberAccent
                                : Colors.white70,
                          ),
                          onPressed: () {
                            _showControlsBriefly();
                            unawaited(_toggleRepeat());
                          },
                        ),
                        IconButton(
                          tooltip: 'Hide controls',
                          icon: const Icon(Icons.close, color: Colors.white70),
                          onPressed: _hideControls,
                        ),
                      ],
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
