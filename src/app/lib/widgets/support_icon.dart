import 'package:flutter/material.dart';

/// Renders the admin-configured Community Support icon/badge. Mirrors the
/// key set in admin's community_support_tab.dart (kSupportBuiltInIcons) —
/// keep both in sync manually since app and admin are separate projects.
const Map<String, IconData> kSupportBuiltInIcons = {
  'front_hand': Icons.front_hand,
  'volunteer_activism': Icons.volunteer_activism,
  'shield_outlined': Icons.shield_outlined,
  'self_improvement': Icons.self_improvement,
  'favorite': Icons.favorite,
};

class SupportIcon extends StatelessWidget {
  final Map<String, dynamic> config;
  final double size;
  final Color? fallbackColor;

  const SupportIcon({
    super.key,
    required this.config,
    this.size = 24,
    this.fallbackColor,
  });

  Color? _parseHexColor(String hex) {
    final cleaned = hex.trim().replaceAll('#', '');
    if (cleaned.length != 6 && cleaned.length != 8) return null;
    final value = int.tryParse(cleaned.length == 6 ? 'FF$cleaned' : cleaned, radix: 16);
    return value == null ? null : Color(value);
  }

  @override
  Widget build(BuildContext context) {
    final mode = (config['supportIconMode'] as String?) ?? 'builtin';

    if (mode == 'text') {
      final label = (config['supportTextLabel'] as String?)?.trim();
      final color = _parseHexColor((config['supportTextColor'] as String?) ?? '') ??
          fallbackColor ??
          Colors.amberAccent;
      return Text(
        (label == null || label.isEmpty) ? 'Community Served' : label,
        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: size * 0.6),
      );
    }

    if (mode == 'custom') {
      final url = (config['supportIconCustomUrl'] as String?)?.trim();
      if (url != null && url.isNotEmpty) {
        return Image.network(
          url,
          width: size,
          height: size,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) =>
              Icon(Icons.front_hand, size: size, color: fallbackColor ?? Colors.white70),
        );
      }
    }

    final key = (config['supportIconBuiltInKey'] as String?) ?? 'front_hand';
    return Icon(
      kSupportBuiltInIcons[key] ?? Icons.front_hand,
      size: size,
      color: fallbackColor ?? Colors.white70,
    );
  }
}
