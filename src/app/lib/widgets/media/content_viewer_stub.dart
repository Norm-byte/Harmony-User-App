import 'package:flutter/material.dart';

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
    throw UnimplementedError('ContentViewer not implemented for this platform');
  }
}
