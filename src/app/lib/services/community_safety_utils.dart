/// Shared author-id resolution for legacy and current community documents.
class CommunitySafetyUtils {
  const CommunitySafetyUtils._();

  static String authorId(Map<String, dynamic> data) {
    for (final key in const ['authorUid', 'userId', 'authorId', 'senderId', 'uid']) {
      final value = data[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  static bool isBlocked(Map<String, dynamic> data, Set<String> blockedUserIds) {
    if (blockedUserIds.isEmpty) return false;
    return blockedUserIds.contains(authorId(data));
  }
}
