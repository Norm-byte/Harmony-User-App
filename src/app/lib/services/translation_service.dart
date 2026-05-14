import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:translator/translator.dart';

class TranslationService {
  TranslationService._();

  static final TranslationService instance = TranslationService._();

  static const String _enabledKey = 'translation_toggle_enabled';

  final GoogleTranslator _translator = GoogleTranslator();
  final ValueNotifier<bool> enabledNotifier = ValueNotifier<bool>(false);
  final Map<String, String> _cache = <String, String>{};

  bool _initialized = false;

  bool get isEnabled => enabledNotifier.value;

  Future<void> init() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    enabledNotifier.value = prefs.getBool(_enabledKey) ?? false;
    _initialized = true;
  }

  Future<void> setEnabled(bool enabled) async {
    enabledNotifier.value = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
  }

  String _normalizeLanguageCode(String code) {
    final lower = code.toLowerCase();
    if (lower.startsWith('fr')) return 'fr';
    if (lower.startsWith('de')) return 'de';
    if (lower.startsWith('nl')) return 'nl';
    if (lower.startsWith('es')) return 'es';
    if (lower.startsWith('ro')) return 'ro';
    if (lower.startsWith('sv')) return 'sv';
    if (lower.startsWith('hi')) return 'hi';
    if (lower.startsWith('en')) return 'en';
    return 'en';
  }

  Future<String> translateForLocale(String text, String localeLanguageCode) async {
    final source = text.trim();
    if (source.isEmpty) return text;
    if (!enabledNotifier.value) return text;

    final target = _normalizeLanguageCode(localeLanguageCode);
    final cacheKey = '$target|$source';

    final cached = _cache[cacheKey];
    if (cached != null) return cached;

    try {
      final translated = await _translator.translate(source, to: target);
      final output = translated.text.trim().isEmpty ? text : translated.text;
      _cache[cacheKey] = output;
      return output;
    } catch (_) {
      _cache[cacheKey] = text;
      return text;
    }
  }
}
