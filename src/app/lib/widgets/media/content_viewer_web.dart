import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
// ignore: avoid_web_libraries_in_flutter
import 'dart:ui_web' as ui_web;

class ContentViewer extends StatelessWidget {
  final String url;
  final bool controls;
  final bool autoPlay;
  final bool loop;
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

    final isVideo = url.toLowerCase().contains('.mp4') ||
        url.toLowerCase().contains('.mov') ||
        url.toLowerCase().contains('.webm') ||
        url.toLowerCase().contains('.mpeg') ||
        url.toLowerCase().contains('.mpg') ||
        url.toLowerCase().contains('.avi') ||
        url.toLowerCase().contains('.mkv');
    final isPdf = url.toLowerCase().contains('.pdf');
    final isDoc = url.toLowerCase().contains('.ppt') ||
        url.toLowerCase().contains('.pptx') ||
        url.toLowerCase().contains('.doc') ||
        url.toLowerCase().contains('.docx');
    
    // Check for YouTube
    final isYoutube = url.contains('youtube.com') || url.contains('youtu.be');

    if (isYoutube) {
      final videoId = _extractYoutubeId(url);
      // Autoplay enabled (autoplay=1)
      final embedUrl = 'https://www.youtube.com/embed/$videoId?autoplay=${autoPlay ? 1 : 0}&rel=0';
      final viewId = 'content-viewer-youtube-${url.hashCode}';
      
      // ignore: undefined_prefixed_name
      ui_web.platformViewRegistry.registerViewFactory(viewId, (int viewId) {
        final element = html.IFrameElement()
          ..src = embedUrl
          ..style.border = 'none'
          ..style.width = '100%'
          ..style.height = '100%'
          ..allow = 'accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture';
        return element;
      });
      
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: HtmlElementView(viewType: viewId),
      );
    }

    if (isVideo) {
      final viewId = 'content-viewer-video-${url.hashCode}-${DateTime.now().millisecondsSinceEpoch}';
      // ignore: undefined_prefixed_name
      ui_web.platformViewRegistry.registerViewFactory(viewId, (int viewId) {
        final video = html.VideoElement()
          ..src = url
          ..autoplay = autoPlay
          ..loop = loop
          ..controls = controls
          ..style.objectFit = fit == BoxFit.cover ? 'cover' : 'contain'
          ..style.width = '100%'
          ..style.height = '100%';
        video.setAttribute('playsinline', 'true');
        // video.muted = true; // User needs sound mostly
        return video;
      });
      return Stack(
        children: [
          HtmlElementView(viewType: viewId, key: ValueKey(viewId)),
          if (controls)
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.open_in_new, color: Colors.white),
                tooltip: 'Open Video in New Tab',
                onPressed: () => launchUrl(Uri.parse(url)),
              ),
            ),
        ],
      );
    } else if (isPdf) {
      final viewId = 'content-viewer-pdf-${url.hashCode}';
      // Append params to hide toolbar if not already present
      final pdfUrl = url.contains('#') ? url : '$url#toolbar=0&navpanes=0&scrollbar=0';
      
      // ignore: undefined_prefixed_name
      ui_web.platformViewRegistry.registerViewFactory(viewId, (int viewId) {
        final element = html.ObjectElement()
          ..data = pdfUrl
          ..type = 'application/pdf'
          ..style.border = 'none'
          ..style.width = '100%'
          ..style.height = '100%';
        return element;
      });
      return Stack(
        children: [
          HtmlElementView(viewType: viewId),
          Positioned(
            top: 8,
            right: 8,
            child: IconButton(
              icon: const Icon(Icons.open_in_new, color: Colors.black),
              tooltip: 'Open PDF in New Tab',
              onPressed: () => launchUrl(Uri.parse(url)),
              style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withOpacity(0.7)),
            ),
          ),
        ],
      );
    } else if (isDoc) {
      final viewId = 'content-viewer-doc-${url.hashCode}';
      // ignore: undefined_prefixed_name
      ui_web.platformViewRegistry.registerViewFactory(viewId, (int viewId) {
        final iframe = html.IFrameElement()
          ..src = 'https://view.officeapps.live.com/op/embed.aspx?src=${Uri.encodeComponent(url)}'
          ..style.border = 'none'
          ..style.width = '100%'
          ..style.height = '100%';
        return iframe;
      });
      return HtmlElementView(viewType: viewId);
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
      errorBuilder: (_, __, ___) => const Center(
          child: Icon(Icons.broken_image, color: Colors.white)),
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
