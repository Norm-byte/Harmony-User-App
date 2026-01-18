class ProfanityFilter {
  static final List<String> _badWords = [
    'badword',
    'abuse',
    'hate',
    'violence',
    'kill',
    // Add more words as needed or use a package
    // For this demo, we'll keep it simple
  ];

  static bool hasProfanity(String text) {
    final lowerText = text.toLowerCase();
    for (final word in _badWords) {
      if (lowerText.contains(word)) {
        return true;
      }
    }
    return false;
  }

  static String clean(String text) {
    String result = text;
    for (final word in _badWords) {
      final stars = '*' * word.length;
      result = result.replaceAll(RegExp(word, caseSensitive: false), stars);
    }
    return result;
  }
}
