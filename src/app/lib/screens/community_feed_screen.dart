import 'package:flutter/material.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/gradient_scaffold.dart';
import '../widgets/threaded_replies_panel.dart';
import '../widgets/translatable_text.dart';
import '../services/user_service.dart';
import '../services/usage_service.dart';
import '../services/profanity_service.dart';
import '../services/translation_service.dart';

class CommunityFeedScreen extends StatelessWidget {
  const CommunityFeedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _CommunityFeedContent();
  }
}

class _CommunityFeedContent extends StatefulWidget {
  const _CommunityFeedContent();

  @override
  State<_CommunityFeedContent> createState() => _CommunityFeedScreenState();
}

class _CommunityFeedScreenState extends State<_CommunityFeedContent>
  with WidgetsBindingObserver {
  final _postController = TextEditingController();
  final ScrollController _feedScrollController = ScrollController();
  final Map<String, Future<String>> _resolvedNameFutureByUserId = {};
  final Map<String, bool> _expandedRepliesByPostId = {};
  bool _isPosting = false;
  
  // Daily Message Limit State
  int _messagesRemaining = 0;
  int _dailyLimit = 5;
  UsageService? _usageService;
  bool _autoScrollEnabled = false;
  double _autoScrollSpeedPxPerSecond = 28;
  Timer? _autoScrollTimer;

  BoxDecoration _glassPanelDecoration({
    Color baseColor = Colors.white,
    double alpha = 0.015,
    Color borderColor = const Color(0x55A7E8FF),
  }) {
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          baseColor.withValues(alpha: alpha + 0.01),
          baseColor.withValues(alpha: alpha),
        ],
      ),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: borderColor),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 12,
          offset: const Offset(0, 5),
        ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    TranslationService.instance.init();
  }

  Future<void> _toggleTranslation() async {
    final enabled = !TranslationService.instance.isEnabled;
    await TranslationService.instance.setEnabled(enabled);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          enabled
              ? 'Translation is ON for Community Room.'
              : 'Translation is OFF for Community Room.',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newService = context.read<UsageService>();
    if (_usageService != newService) {
      _usageService?.removeListener(_calculateRemaining);
      _usageService = newService;
      _usageService?.addListener(_calculateRemaining);
      _calculateRemaining();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoScrollTimer?.cancel();
    _feedScrollController.dispose();
    _usageService?.removeListener(_calculateRemaining);
    _postController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _calculateRemaining();
    }
  }

  Future<void> _calculateRemaining() async {
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    
    // Check for new day reset
    final lastResetStr = prefs.getString('chat_daily_limit_date');
    final todayStr = DateTime.now().toIso8601String().split('T').first;

    if (lastResetStr != todayStr) {
      await prefs.setInt('chat_messages_sent_today', 0);
      await prefs.setString('chat_daily_limit_date', todayStr);
      await prefs.remove('chat_messages_remaining'); // Cleanup legacy
    } else if (prefs.containsKey('chat_messages_remaining') && !prefs.containsKey('chat_messages_sent_today')) {
       // Migration: Reset to 0 sent
       await prefs.setInt('chat_messages_sent_today', 0);
       await prefs.remove('chat_messages_remaining');
    }

    final int sentToday = prefs.getInt('chat_messages_sent_today') ?? 0;
    final int limit = _usageService?.maxDailySends ?? 5;

    setState(() {
      _dailyLimit = limit;
      _messagesRemaining = (limit - sentToday).clamp(0, 9999);
    });
  }

  void _applyFeedScrollSettings(Map<String, dynamic> data) {
    final enabled = (data['auto_scroll_enabled'] as bool?) ?? false;
    final speed = ((data['auto_scroll_speed'] as num?)?.toDouble() ?? 28.0)
        .clamp(8.0, 120.0);

    if (enabled == _autoScrollEnabled && speed == _autoScrollSpeedPxPerSecond) {
      return;
    }

    _autoScrollEnabled = enabled;
    _autoScrollSpeedPxPerSecond = speed;
    _restartAutoScrollTimer();
  }

  void _restartAutoScrollTimer() {
    _autoScrollTimer?.cancel();
    if (!_autoScrollEnabled) return;

    const interval = Duration(milliseconds: 120);
    _autoScrollTimer = Timer.periodic(interval, (_) {
      if (!mounted || !_autoScrollEnabled || !_feedScrollController.hasClients) {
        return;
      }
      final step = _autoScrollSpeedPxPerSecond * (interval.inMilliseconds / 1000);
      final position = _feedScrollController.position;
      final maxExtent = position.maxScrollExtent;
      if (maxExtent <= 0) return;

      final target = (position.pixels + step) >= maxExtent
          ? 0.0
          : (position.pixels + step);

      _feedScrollController.animateTo(
        target,
        duration: interval,
        curve: Curves.linear,
      );
    });
  }
  Future<void> _showReportPostSheet(
    BuildContext context, {
    required String postId,
    required String reportedUserId,
    required String content,
  }) async {
    final reasons = [
      'Inappropriate content',
      'Harassment or bullying',
      'Spam',
      'Misleading information',
      'Other',
    ];
    String? selected;
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey.shade900,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Report this post',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('Why are you reporting this post?',
                  style: TextStyle(color: Colors.white54, fontSize: 13)),
              const SizedBox(height: 16),
              ...reasons.map((r) => RadioListTile<String>(
                    value: r,
                    groupValue: selected,
                    title: Text(r, style: const TextStyle(color: Colors.white70)),
                    activeColor: Colors.redAccent,
                    onChanged: (v) => setModalState(() => selected = v),
                  )),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: selected == null
                      ? null
                      : () async {
                          Navigator.pop(ctx);
                          final ok = await UserService().reportContent(
                            reportedUserId,
                            content,
                            selected!,
                            'Community Room',
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  ok
                                      ? 'Report submitted. Thank you.'
                                      : 'Could not submit report. Please try again.',
                                ),
                                backgroundColor: ok ? Colors.green : Colors.red,
                              ),
                            );
                          }
                        },
                  child: const Text('Submit Report'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleLike(String docId, List<dynamic> likedBy) async {
    final uid = UserService().userId;
    if (uid.isEmpty) return;
    
    final docRef = FirebaseFirestore.instance.collection('community_posts').doc(docId);

    try {
      if (likedBy.contains(uid)) {
        await docRef.update({
          'likes': FieldValue.increment(-1),
          'likedBy': FieldValue.arrayRemove([uid])
        });
      } else {
        await docRef.update({
          'likes': FieldValue.increment(1),
          'likedBy': FieldValue.arrayUnion([uid])
        });
      }
    } catch (e) {
      debugPrint('Community like toggle failed for $docId: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not update like right now. Please try again.'),
          backgroundColor: Colors.redAccent,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  String _formatLikeCount(dynamic rawLikes) {
    final likes = (rawLikes is num) ? rawLikes.toInt() : int.tryParse('$rawLikes') ?? 0;
    if (likes < 1000) return '$likes';
    if (likes < 1000000) {
      final value = likes / 1000;
      final compact = value >= 100 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
      return '${compact.replaceAll(RegExp(r'\.0$'), '')}K';
    }
    final value = likes / 1000000;
    final compact = value >= 100 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
    return '${compact.replaceAll(RegExp(r'\.0$'), '')}M';
  }
  Future<void> _decrementMessageLimit() async {
    final prefs = await SharedPreferences.getInstance();
    int sent = prefs.getInt('chat_messages_sent_today') ?? 0;
    sent++;
    await prefs.setInt('chat_messages_sent_today', sent);
    _calculateRemaining();
  }

  bool _looksLikeFallbackName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return true;
    final normalized = trimmed.toLowerCase();
    if (normalized == 'member' || normalized == 'guest') return true;
    if (RegExp(r'^user[a-z0-9]{4,}$', caseSensitive: false).hasMatch(trimmed)) {
      return true;
    }
    if (RegExp(r'^[a-z0-9]{6}$', caseSensitive: false).hasMatch(trimmed) &&
        RegExp(r'\d').hasMatch(trimmed)) {
      return true;
    }
    return false;
  }

  Future<String> _fetchBestNameForUserId(
    String userId,
    String fallback,
  ) async {
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();
      final data = userDoc.data();

      final emailPrefix = (data?['email'] as String?)?.contains('@') == true
          ? (data!['email'] as String).split('@').first.trim()
          : null;

      final candidates = <String?>[
        data?['username'] as String?,
        data?['userName'] as String?,
        data?['name'] as String?,
        data?['displayName'] as String?,
        fallback,
      ];

      for (final candidate in candidates) {
        final sanitized = UserService.sanitizePublicDisplayName(candidate);
        if (UserService.isRecognizedPublicDisplayName(sanitized) &&
            !_looksLikeFallbackName(sanitized)) {
          return sanitized;
        }
      }

      if (data?['isSuperAdmin'] == true) {
        return 'Admin 1';
      }

      final sanitizedEmail = UserService.sanitizePublicDisplayName(emailPrefix);
      if (UserService.isRecognizedPublicDisplayName(sanitizedEmail) &&
          !_looksLikeFallbackName(sanitizedEmail)) {
        return sanitizedEmail;
      }
    } catch (_) {}

    if (UserService.isRecognizedPublicDisplayName(fallback) &&
        !_looksLikeFallbackName(fallback)) {
      return fallback;
    }
    return 'Member';
  }

  Future<String> _resolveDisplayNameForPost(Map<String, dynamic> post) {
    final rawName = UserService.sanitizePublicDisplayName(post['userName']?.toString());
    final userId = (post['userId']?.toString() ?? '').trim();
    final currentUser = UserService();

    if (userId.isEmpty) {
      final localName = UserService.sanitizePublicDisplayName(currentUser.userName);
      if (UserService.isRecognizedPublicDisplayName(localName) &&
          !_looksLikeFallbackName(localName)) {
        return Future.value(localName);
      }
      if (UserService.isRecognizedPublicDisplayName(rawName) &&
          !_looksLikeFallbackName(rawName)) {
        return Future.value(rawName);
      }
      return Future.value('Admin 1');
    }

    if (userId == currentUser.userId) {
      final localName = UserService.sanitizePublicDisplayName(currentUser.userName);
      if (UserService.isRecognizedPublicDisplayName(localName) &&
          !_looksLikeFallbackName(localName)) {
        _resolvedNameFutureByUserId[userId] = Future.value(localName);
        return Future.value(localName);
      }

      final recovered = currentUser.ensureRecognizedPublicDisplayName().then((value) {
        if (value != null &&
            UserService.isRecognizedPublicDisplayName(value) &&
            !_looksLikeFallbackName(value)) {
          return value;
        }
        return 'Admin 1';
      });
      _resolvedNameFutureByUserId[userId] = recovered;
      return recovered;
    }

    final existing = _resolvedNameFutureByUserId[userId];
    if (existing != null) {
      return existing;
    }

    final future = _fetchBestNameForUserId(userId, rawName);
    _resolvedNameFutureByUserId[userId] = future;
    return future;
  }

  CollectionReference<Map<String, dynamic>> _roomPostsCollection() {
    return FirebaseFirestore.instance.collection('community_posts');
  }

  CollectionReference<Map<String, dynamic>> _repliesCollection(String postId) {
    return _roomPostsCollection().doc(postId).collection('replies');
  }

  Future<void> _primeRepliesFromServer(String postId) async {
    try {
      await _repliesCollection(postId).get(const GetOptions(source: Source.server));
    } catch (e) {
      debugPrint('Community replies server refresh failed for $postId: $e');
    }
  }

  String _currentAuthUid() {
    return (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
  }

  String _effectiveCurrentUserId() {
    final serviceId = UserService().userId.trim();
    if (serviceId.isNotEmpty) return serviceId;
    return _currentAuthUid();
  }

  bool _isCurrentUserAuthor({required String authorId, String? authorUid}) {
    final normalizedAuthorId = authorId.trim();
    final candidates = <String>{
      _effectiveCurrentUserId(),
      _currentAuthUid(),
    }.where((v) => v.isNotEmpty);
    final normalizedAuthorUid = (authorUid ?? '').trim();
    return candidates.any(
      (id) =>
          (normalizedAuthorId.isNotEmpty && id == normalizedAuthorId) ||
          (normalizedAuthorUid.isNotEmpty && id == normalizedAuthorUid),
    );
  }

  Future<String> _resolveDisplayNameForUser({
    required String userId,
    required String rawName,
  }) {
    if (userId.isEmpty) {
      return Future.value(UserService.sanitizePublicDisplayName(rawName));
    }

    final existing = _resolvedNameFutureByUserId[userId];
    if (existing != null) {
      return existing;
    }

    final future = _fetchBestNameForUserId(
      userId,
      UserService.sanitizePublicDisplayName(rawName),
    );
    _resolvedNameFutureByUserId[userId] = future;
    return future;
  }

  Future<void> _submitReply({
    required String postId,
    required String content,
  }) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;

    await _calculateRemaining();
    if (_messagesRemaining <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Daily message limit reached. Try again tomorrow!'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final user = UserService();
    final suspended = await user.isCurrentlySuspended();
    if (suspended) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Your account is suspended from community posting. Please use Support chat in My Harmony for assistance.',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final userId = _effectiveCurrentUserId();
    final authUid = _currentAuthUid();
    if (userId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not resolve account id. Please re-login and try again.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final publicName = await user.ensureRecognizedPublicDisplayName();
    if (publicName == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Your account username is not recognized. Messaging is disabled until your profile name is fixed.',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (ProfanityService().hasProfanity(trimmed)) {
      await FirebaseFirestore.instance.collection('moderation_queue').add({
        'content': trimmed,
        'userId': userId,
        'userName': publicName,
        'source': 'Community Room Reply',
        'timestamp': FieldValue.serverTimestamp(),
        'reason': 'Profanity Detected',
        'status': 'pending',
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profanity detected. Reply flagged for moderation.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    await _repliesCollection(postId).add({
      'content': trimmed,
      'userId': userId,
      'authorUid': authUid,
      'userName': publicName,
      'userPhoto': user.userPhoto,
      'timestamp': FieldValue.serverTimestamp(),
      'likes': 0,
      'likedBy': <String>[],
    });

    await _decrementMessageLimit();
  }

  Future<void> _showReplyComposer({
    required String postId,
    String? replyId,
    String? initialContent,
  }) async {
    final replyController = TextEditingController(text: initialContent ?? '');
    bool sending = false;
    final isEditing = replyId != null;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.grey.shade900,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Reply to comment',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: replyController,
                    autofocus: true,
                    maxLines: 4,
                    minLines: 1,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Type your reply...',
                      hintStyle: const TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.08),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: sending
                          ? null
                          : () async {
                              final content = replyController.text.trim();
                              if (content.isEmpty) return;
                              setModalState(() => sending = true);
                              try {
                                if (isEditing) {
                                  await _updateReply(
                                    postId: postId,
                                    replyId: replyId!,
                                    content: content,
                                  );
                                } else {
                                  await _submitReply(postId: postId, content: content);
                                }
                                if (mounted) {
                                  setState(() {
                                    _expandedRepliesByPostId[postId] = true;
                                  });
                                }
                                if (ctx.mounted) {
                                  Navigator.of(ctx).pop();
                                }
                              } catch (e) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Could not send reply: $e')),
                                );
                              } finally {
                                if (ctx.mounted) {
                                  setModalState(() => sending = false);
                                }
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber,
                        foregroundColor: Colors.black,
                      ),
                      child: sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(isEditing ? 'Save changes' : 'Send reply'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _updateReply({
    required String postId,
    required String replyId,
    required String content,
  }) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;

    final user = UserService();
    final suspended = await user.isCurrentlySuspended();
    if (suspended) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Your account is suspended from community posting. Please use Support chat in My Harmony for assistance.',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final userId = _effectiveCurrentUserId();
    final authUid = _currentAuthUid();
    if (userId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not resolve account id. Please re-login and try again.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final publicName = await user.ensureRecognizedPublicDisplayName();
    if (publicName == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Your account username is not recognized. Messaging is disabled until your profile name is fixed.',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (ProfanityService().hasProfanity(trimmed)) {
      await FirebaseFirestore.instance.collection('moderation_queue').add({
        'content': trimmed,
        'userId': userId,
        'userName': publicName,
        'source': 'Community Room Reply Edit',
        'timestamp': FieldValue.serverTimestamp(),
        'reason': 'Profanity Detected',
        'status': 'pending',
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profanity detected. Reply update flagged for moderation.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    await _repliesCollection(postId).doc(replyId).update({
      'content': trimmed,
      'userId': userId,
      'authorUid': authUid,
      'userName': publicName,
      'userPhoto': user.userPhoto,
    });
  }

  Future<void> _deleteReply({
    required String postId,
    required String replyId,
  }) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: Colors.grey.shade900,
            title: const Text(
              'Delete reply?',
              style: TextStyle(color: Colors.white),
            ),
            content: const Text(
              'This will permanently remove your reply from the conversation.',
              style: TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text(
                  'Delete',
                  style: TextStyle(color: Colors.redAccent),
                ),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    await _repliesCollection(postId).doc(replyId).delete();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Reply deleted.')),
    );
  }

  Future<void> _showPostEditor({
    required String postId,
    required String initialContent,
  }) async {
    final controller = TextEditingController(text: initialContent);
    bool saving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.grey.shade900,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Edit comment',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    maxLines: 6,
                    minLines: 1,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Update your comment...',
                      hintStyle: const TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.08),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: saving
                          ? null
                          : () async {
                              final content = controller.text.trim();
                              if (content.isEmpty) return;
                              setModalState(() => saving = true);
                              try {
                                await _updatePost(postId: postId, content: content);
                                if (ctx.mounted) {
                                  Navigator.of(ctx).pop();
                                }
                              } finally {
                                if (ctx.mounted) {
                                  setModalState(() => saving = false);
                                }
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber,
                        foregroundColor: Colors.black,
                      ),
                      child: saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save changes'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _updatePost({
    required String postId,
    required String content,
  }) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;

    if (ProfanityService().hasProfanity(trimmed)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profanity detected. Please adjust and try again.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    await _roomPostsCollection().doc(postId).update({
      'content': trimmed,
      'editedAt': FieldValue.serverTimestamp(),
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Comment updated.')),
    );
  }

  Future<void> _deletePost({required String postId}) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: Colors.grey.shade900,
            title: const Text(
              'Delete comment?',
              style: TextStyle(color: Colors.white),
            ),
            content: const Text(
              'This will permanently remove your comment.',
              style: TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text(
                  'Delete',
                  style: TextStyle(color: Colors.redAccent),
                ),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    await _roomPostsCollection().doc(postId).delete();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Comment deleted.')),
    );
  }

  Future<void> _submitPost() async {
    final content = _postController.text.trim();
    if (content.isEmpty) return;

    await _calculateRemaining();

    // Profanity Check
    if (ProfanityService().hasProfanity(content)) {
      final user = UserService();
      final userId = user.userId.isNotEmpty
          ? user.userId
          : (FirebaseAuth.instance.currentUser?.uid ?? '');
      final publicName =
          await user.ensureRecognizedPublicDisplayName() ??
          UserService.sanitizePublicDisplayName(user.userName);
      await FirebaseFirestore.instance.collection('moderation_queue').add({
        'content': content,
        'userId': userId,
        'userName': publicName,
        'source': 'Community Room',
        'timestamp': FieldValue.serverTimestamp(),
        'reason': 'Profanity Detected',
        'status': 'pending',
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profanity detected. Message flagged for moderation.'),
          backgroundColor: Colors.orange,
        ),
      );
      _postController.clear();
      return;
    }

    if (_messagesRemaining <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Daily message limit reached. Try again tomorrow!'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final user = UserService();
    final suspended = await user.isCurrentlySuspended();
    if (suspended) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Your account is suspended from community posting. Please use Support chat in My Harmony for assistance.',
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    // final content = _postController.text.trim(); // Removed duplicate
    if (content.isEmpty) return;

    setState(() => _isPosting = true);

    try {
      final userId = user.userId.isNotEmpty
          ? user.userId
          : (FirebaseAuth.instance.currentUser?.uid ?? '');
      if (userId.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not resolve account id. Please re-login and try again.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }
      final publicName = await user.ensureRecognizedPublicDisplayName();
      if (publicName == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Your account username is not recognized. Messaging is disabled until your profile name is fixed.',
              ),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }
      await FirebaseFirestore.instance.collection('community_posts').add({
        'content': content,
        'userId': userId,
        'authorUid': _currentAuthUid(),
        'userName': publicName,
        'userPhoto': user.userPhoto,
        'timestamp': FieldValue.serverTimestamp(),
      });

      await _decrementMessageLimit();

      _postController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Post shared with the community!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error posting: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isPosting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    return GradientScaffold(
      appBar: AppBar(
        title: const Text('Community Room'),
        foregroundColor: Colors.white,
        actions: [
          ValueListenableBuilder<bool>(
            valueListenable: TranslationService.instance.enabledNotifier,
            builder: (context, enabled, _) {
              return IconButton(
                tooltip: enabled ? 'Disable Translation' : 'Enable Translation',
                onPressed: _toggleTranslation,
                icon: Icon(
                  Icons.translate,
                  color: enabled ? Colors.greenAccent : Colors.white,
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Admin Message (Pinned)
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('app_config')
                .doc('community_settings')
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasData && snapshot.data!.exists) {
                final settingsData = snapshot.data!.data() as Map<String, dynamic>;
                _applyFeedScrollSettings(settingsData);
              } else {
                _applyFeedScrollSettings(const {});
              }

              if (!snapshot.hasData || !snapshot.data!.exists) {
                return const SizedBox.shrink();
              }
              final data = snapshot.data!.data() as Map<String, dynamic>;
              final rawAdminMessage = data['admin_message'];
              final adminMessage = rawAdminMessage == null
                  ? null
                  : rawAdminMessage.toString();

              if (adminMessage == null || adminMessage.isEmpty) {
                return const SizedBox.shrink();
              }

              return Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: _glassPanelDecoration(
                  baseColor: Colors.indigo.shade700,
                  alpha: 0.18,
                  borderColor: Colors.amber.withValues(alpha: 0.45),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.push_pin,
                          size: 16,
                          color: Colors.amber.withValues(alpha: 0.9),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Pinned',
                          style: TextStyle(
                            color: Colors.amber.withValues(alpha: 0.9),
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TranslatableText(
                      adminMessage,
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                    ),
                  ],
                ),
              );
            },
          ),

          // Feed List
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('community_posts')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Colors.white));
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Text(
                      'No posts yet. Be the first!',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                    ),
                  );
                }

                final posts = snapshot.data!.docs;

                return ListView.builder(
                  controller: _feedScrollController,
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: posts.length,
                  itemBuilder: (context, index) {
                    final post = posts[index].data() as Map<String, dynamic>;
                    final timestamp = (post['timestamp'] as Timestamp?)?.toDate();
                    final likedBy = List<String>.from(post['likedBy'] ?? []);
                    final uid = _effectiveCurrentUserId();
                    final authUid = _currentAuthUid();
                    final postUserId = post['userId']?.toString() ?? '';
                    final postAuthorUid = post['authorUid']?.toString() ?? '';
                    final isOwnPost = _isCurrentUserAuthor(
                      authorId: postUserId,
                      authorUid: postAuthorUid,
                    );

                    return FutureBuilder<String>(
                      future: _resolveDisplayNameForPost(post),
                      builder: (context, nameSnapshot) {
                        final displayName = nameSnapshot.data ?? 'Member';
                        return Padding(
                          key: ValueKey('community_post_${posts[index].id}'),
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 11,
                                    backgroundColor: Colors.white12,
                                    backgroundImage: post['userPhoto'] != null ? NetworkImage(post['userPhoto']) : null,
                                    child: post['userPhoto'] == null
                                        ? Text(
                                            displayName.isNotEmpty ? displayName[0].toUpperCase() : 'M',
                                            style: const TextStyle(color: Colors.white, fontSize: 10),
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    displayName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const Spacer(),
                                  if (timestamp != null)
                                    Text(
                                      DateFormat('MMM d, h:mm a').format(timestamp),
                                      style: TextStyle(fontSize: 10, color: Colors.white54),
                                    ),
                                  SizedBox(
                                    width: 28,
                                    height: 28,
                                    child: PopupMenuButton<String>(
                                      padding: EdgeInsets.zero,
                                      icon: const Icon(Icons.more_vert, color: Colors.white38, size: 16),
                                      color: Colors.grey.shade900,
                                      onSelected: (value) async {
                                        if (value == 'report') {
                                          _showReportPostSheet(
                                            context,
                                            postId: posts[index].id,
                                            reportedUserId: postUserId,
                                            content: post['content']?.toString() ?? '',
                                          );
                                        } else if (value == 'edit') {
                                          await _showPostEditor(
                                            postId: posts[index].id,
                                            initialContent: post['content']?.toString() ?? '',
                                          );
                                        } else if (value == 'delete') {
                                          await _deletePost(postId: posts[index].id);
                                        }
                                      },
                                      itemBuilder: (_) {
                                        if (isOwnPost) {
                                          return const [
                                            PopupMenuItem(
                                              value: 'edit',
                                              child: Row(
                                                children: [
                                                  Icon(Icons.edit_outlined, color: Colors.white70, size: 16),
                                                  SizedBox(width: 8),
                                                  Text('Edit post', style: TextStyle(color: Colors.white70)),
                                                ],
                                              ),
                                            ),
                                            PopupMenuItem(
                                              value: 'delete',
                                              child: Row(
                                                children: [
                                                  Icon(Icons.delete_outline, color: Colors.redAccent, size: 16),
                                                  SizedBox(width: 8),
                                                  Text('Delete post', style: TextStyle(color: Colors.redAccent)),
                                                ],
                                              ),
                                            ),
                                          ];
                                        }

                                        return const [
                                          PopupMenuItem(
                                            value: 'report',
                                            child: Row(
                                              children: [
                                                Icon(Icons.flag_outlined, color: Colors.redAccent, size: 16),
                                                SizedBox(width: 8),
                                                Text('Report post', style: TextStyle(color: Colors.white70)),
                                              ],
                                            ),
                                          ),
                                        ];
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              TranslatableText(
                                post['content'] ?? '',
                                style: const TextStyle(color: Colors.white, height: 1.22, fontSize: 13),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  GestureDetector(
                                    onTap: () => _toggleLike(posts[index].id, likedBy),
                                    child: Row(
                                      children: [
                                        Icon(
                                          likedBy.contains(uid) ? Icons.thumb_up : Icons.thumb_up_outlined,
                                          size: 13,
                                          color: likedBy.contains(uid) ? Colors.greenAccent : Colors.white54,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          _formatLikeCount(post['likes']),
                                          style: const TextStyle(color: Colors.white54, fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              ThreadedRepliesPanel(
                                postId: posts[index].id,
                                isExpanded: _expandedRepliesByPostId[posts[index].id] ?? false,
                                currentUserId: uid,
                                currentAuthUid: authUid,
                                  repliesStream: _repliesCollection(posts[index].id)
                                      .snapshots(includeMetadataChanges: true),
                                resolveDisplayName: (userId, rawName) =>
                                    _resolveDisplayNameForUser(
                                  userId: userId,
                                  rawName: rawName,
                                ),
                                onToggleExpanded: () {
                                  final current = _expandedRepliesByPostId[posts[index].id] ?? false;
                                  final next = !current;
                                  setState(() {
                                    _expandedRepliesByPostId[posts[index].id] = next;
                                  });
                                  if (next) {
                                    _primeRepliesFromServer(posts[index].id);
                                  }
                                },
                                onComposeReply: () => _showReplyComposer(postId: posts[index].id),
                                onEditReply: (replyId, reply) => _showReplyComposer(
                                  postId: posts[index].id,
                                  replyId: replyId,
                                  initialContent: reply['content']?.toString() ?? '',
                                ),
                                onDeleteReply: (replyId, _) => _deleteReply(
                                  postId: posts[index].id,
                                  replyId: replyId,
                                ),
                              ),
                              Divider(color: Colors.white.withValues(alpha: 0.05), height: 10),
                            ],
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),

          // Post Input Area (Moved to Bottom)
          Container(
            padding: EdgeInsets.all(isLandscape ? 10 : 16),
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            decoration: _glassPanelDecoration(alpha: 0.06),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _postController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Message...', 
                      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.08),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: isLandscape ? 14 : 20,
                        vertical: isLandscape ? 8 : 10,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: isLandscape ? 6 : 8),
                // Daily Limit Counter
                Container(
                    margin: EdgeInsets.only(right: isLandscape ? 4 : 8),
                    padding: EdgeInsets.symmetric(
                      horizontal: isLandscape ? 8 : 10,
                      vertical: isLandscape ? 4 : 6,
                    ),
                    decoration: BoxDecoration(
                      color: _messagesRemaining <= 3 ? Colors.red.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _messagesRemaining <= 3 ? Colors.red.withValues(alpha: 0.5) : Colors.white24,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.bolt, 
                          size: 14, 
                          color: _messagesRemaining <= 3 ? Colors.redAccent : Colors.amber
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$_messagesRemaining/$_dailyLimit',
                          style: TextStyle(
                            color: _messagesRemaining <= 3 ? Colors.redAccent : Colors.white70,
                            fontSize: isLandscape ? 11 : 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                IconButton(
                  onPressed: _isPosting ? null : _submitPost,
                  constraints: BoxConstraints.tightFor(
                    width: isLandscape ? 40 : 48,
                    height: isLandscape ? 40 : 48,
                  ),
                  padding: EdgeInsets.zero,
                  icon: _isPosting 
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send, color: Colors.amber),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
