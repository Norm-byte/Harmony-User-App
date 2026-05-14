import 'package:flutter/material.dart';

import '../services/translation_service.dart';

class TranslatableText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;

  const TranslatableText(
    this.text, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    final localeCode = Localizations.localeOf(context).languageCode;

    return ValueListenableBuilder<bool>(
      valueListenable: TranslationService.instance.enabledNotifier,
      builder: (context, enabled, _) {
        if (!enabled) {
          return Text(
            text,
            style: style,
            maxLines: maxLines,
            overflow: overflow,
            textAlign: textAlign,
          );
        }

        return FutureBuilder<String>(
          future: TranslationService.instance.translateForLocale(text, localeCode),
          builder: (context, snapshot) {
            final translated = snapshot.data ?? text;
            return Text(
              translated,
              style: style,
              maxLines: maxLines,
              overflow: overflow,
              textAlign: textAlign,
            );
          },
        );
      },
    );
  }
}
