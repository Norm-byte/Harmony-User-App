import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/translation_service.dart';

class TranslatableText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;
  final bool enableLinks;

  const TranslatableText(
    this.text, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
    this.enableLinks = false,
  });

  @override
  State<TranslatableText> createState() => _TranslatableTextState();
}

class _TranslatableTextState extends State<TranslatableText> {
  static final RegExp _linkPattern = RegExp(
    r'((?:https?:\/\/|www\.)[^\s]+)|([A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,})',
    caseSensitive: false,
  );

  static final RegExp _trailingPunctuationPattern = RegExp(r'[.,!?;:)}\]]+$');

  final List<TapGestureRecognizer> _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  Future<void> _openLink(String rawValue) async {
    final value = rawValue.trim();
    if (value.isEmpty) return;

    final isEmail = value.contains('@') && !value.contains('://');
    final uri = isEmail
        ? Uri(scheme: 'mailto', path: value)
        : Uri.parse(
            value.startsWith('http://') || value.startsWith('https://')
                ? value
                : 'https://$value',
          );

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not open link.')));
    }
  }

  List<InlineSpan> _buildLinkifiedSpans(String value) {
    _disposeRecognizers();

    final spans = <InlineSpan>[];
    var currentIndex = 0;
    final baseStyle = widget.style;
    final linkStyle = (baseStyle ?? const TextStyle()).copyWith(
      color: Colors.lightBlueAccent,
      decoration: TextDecoration.underline,
    );

    for (final match in _linkPattern.allMatches(value)) {
      if (match.start > currentIndex) {
        spans.add(
          TextSpan(
            text: value.substring(currentIndex, match.start),
            style: baseStyle,
          ),
        );
      }

      final rawMatch = match.group(0) ?? '';
      final punctuationMatch = _trailingPunctuationPattern.firstMatch(rawMatch);
      final punctuation = punctuationMatch?.group(0) ?? '';
      final trimmedMatch = punctuation.isEmpty
          ? rawMatch
          : rawMatch.substring(0, rawMatch.length - punctuation.length);

      if (trimmedMatch.isNotEmpty) {
        final recognizer = TapGestureRecognizer()
          ..onTap = () {
            _openLink(trimmedMatch);
          };
        _recognizers.add(recognizer);
        spans.add(
          TextSpan(
            text: trimmedMatch,
            style: linkStyle,
            recognizer: recognizer,
          ),
        );
      }

      if (punctuation.isNotEmpty) {
        spans.add(TextSpan(text: punctuation, style: baseStyle));
      }

      currentIndex = match.end;
    }

    if (currentIndex < value.length) {
      spans.add(
        TextSpan(text: value.substring(currentIndex), style: baseStyle),
      );
    }

    if (spans.isEmpty) {
      spans.add(TextSpan(text: value, style: baseStyle));
    }

    return spans;
  }

  Widget _buildText(String value) {
    if (!widget.enableLinks) {
      return Text(
        value,
        style: widget.style,
        maxLines: widget.maxLines,
        overflow: widget.overflow,
        textAlign: widget.textAlign,
      );
    }

    return RichText(
      textAlign: widget.textAlign ?? TextAlign.start,
      maxLines: widget.maxLines,
      overflow: widget.overflow ?? TextOverflow.clip,
      text: TextSpan(
        style: DefaultTextStyle.of(context).style.merge(widget.style),
        children: _buildLinkifiedSpans(value),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final localeCode = Localizations.localeOf(context).languageCode;

    return ValueListenableBuilder<bool>(
      valueListenable: TranslationService.instance.enabledNotifier,
      builder: (context, enabled, _) {
        if (!enabled) {
          return _buildText(widget.text);
        }

        return FutureBuilder<String>(
          future: TranslationService.instance.translateForLocale(
            widget.text,
            localeCode,
          ),
          builder: (context, snapshot) {
            final translated = snapshot.data ?? widget.text;
            return _buildText(translated);
          },
        );
      },
    );
  }
}
