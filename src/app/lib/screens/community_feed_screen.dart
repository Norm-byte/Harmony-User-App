import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/gradient_scaffold.dart';
import '../widgets/live_room_counter_badge.dart';
import '../widgets/threaded_replies_panel.dart';
import '../widgets/translatable_text.dart';
import '../services/user_service.dart';
import '../services/usage_service.dart';
import '../services/profanity_service.dart';
import '../services/media_vault_service.dart';
import '../services/translation_service.dart';

class CommunityFeedScreen extends StatelessWidget {
  final Map<String, dynamic>? preselectedVaultImage;

  const CommunityFeedScreen({super.key, this.preselectedVaultImage});

  @override
  Widget build(BuildContext context) {
    return _CommunityFeedContent(preselectedVaultImage: preselectedVaultImage);
  }
}

class _CommunityFeedContent extends StatefulWidget {
  final Map<String, dynamic>? preselectedVaultImage;

  const _CommunityFeedContent({this.preselectedVaultImage});

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
  final MediaVaultService _mediaVaultService = MediaVaultService();
  final ImagePicker _imagePicker = ImagePicker();
  XFile? _pendingPickedImage;
  Map<String, dynamic>? _pendingVaultImage;
  Uint8List? _pendingPreviewBytes;
  bool _saveCameraToVault = true;
  int _imageUploadsUsedThisMonth = 0;
  bool _isLoadingImageUsage = false;

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
    if (widget.preselectedVaultImage != null) {
      _pendingVaultImage = Map<String, dynamic>.from(
        widget.preselectedVaultImage!,
      );
    }
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
    } else if (prefs.containsKey('chat_messages_remaining') &&
        !prefs.containsKey('chat_messages_sent_today')) {
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

    await _refreshImageUsageCounter();
  }

  Future<void> _refreshImageUsageCounter() async {
    final userId = _effectiveCurrentUserId();
    if (userId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _imageUploadsUsedThisMonth = 0;
        _isLoadingImageUsage = false;
      });
      return;
    }

    final limit = _usageService?.monthlyImageUploadLimit ?? 0;
    if (limit <= 0) {
      if (!mounted) return;
      setState(() {
        _imageUploadsUsedThisMonth = 0;
        _isLoadingImageUsage = false;
      });
      return;
    }

    if (mounted) {
      setState(() => _isLoadingImageUsage = true);
    }

    try {
      final used = await _mediaVaultService.getSharedRoomUploadsForMonth(
        userId,
        DateTime.now(),
      );
      if (!mounted) return;
      setState(() {
        _imageUploadsUsedThisMonth = used;
      });
    } catch (_) {
      // Keep existing count on transient errors.
    } finally {
      if (mounted) {
        setState(() => _isLoadingImageUsage = false);
      }
    }
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
      if (!mounted ||
          !_autoScrollEnabled ||
          !_feedScrollController.hasClients) {
        return;
      }
      final step =
          _autoScrollSpeedPxPerSecond * (interval.inMilliseconds / 1000);
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

  ({bool showCounter, bool showFlags}) _counterSettingsFromAppConfig(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    Map<String, dynamic> home = const <String, dynamic>{};
    Map<String, dynamic> community = const <String, dynamic>{};

    for (final doc in snapshot.docs) {
      if (doc.id == 'home_screen') {
        home = doc.data();
      } else if (doc.id == 'community_settings') {
        community = doc.data();
      }
    }

    final showCounter = community.containsKey('showCommunityLiveCounter')
        ? community['showCommunityLiveCounter'] == true
        : home['showCommunityLiveCounter'] == true;

    final showFlags = community.containsKey('statsShowTimezoneFlags')
        ? community['statsShowTimezoneFlags'] == true
        : home['statsShowTimezoneFlags'] == true;

    return (showCounter: showCounter, showFlags: showFlags);
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
              const Text(
                'Report this post',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Why are you reporting this post?',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(height: 16),
              ...reasons.map(
                (r) => RadioListTile<String>(
                  value: r,
                  groupValue: selected,
                  title: Text(r, style: const TextStyle(color: Colors.white70)),
                  activeColor: Colors.redAccent,
                  onChanged: (v) => setModalState(() => selected = v),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
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

    final docRef = FirebaseFirestore.instance
        .collection('community_posts')
        .doc(docId);

    try {
      if (likedBy.contains(uid)) {
        await docRef.update({
          'likes': FieldValue.increment(-1),
          'likedBy': FieldValue.arrayRemove([uid]),
        });
      } else {
        await docRef.update({
          'likes': FieldValue.increment(1),
          'likedBy': FieldValue.arrayUnion([uid]),
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

  Future<void> _toggleReplyLike({
    required String postId,
    required String replyId,
    required List<dynamic> likedBy,
  }) async {
    final uid = UserService().userId;
    if (uid.isEmpty) return;

    final replyRef = FirebaseFirestore.instance
        .collection('community_posts')
        .doc(postId)
        .collection('replies')
        .doc(replyId);

    try {
      if (likedBy.contains(uid)) {
        await replyRef.update({
          'likes': FieldValue.increment(-1),
          'likedBy': FieldValue.arrayRemove([uid]),
        });
      } else {
        await replyRef.update({
          'likes': FieldValue.increment(1),
          'likedBy': FieldValue.arrayUnion([uid]),
        });
      }
    } catch (e) {
      debugPrint('Community reply like toggle failed for $postId/$replyId: $e');
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
    final likes = (rawLikes is num)
        ? rawLikes.toInt()
        : int.tryParse('$rawLikes') ?? 0;
    if (likes < 1000) return '$likes';
    if (likes < 1000000) {
      final value = likes / 1000;
      final compact = value >= 100
          ? value.toStringAsFixed(0)
          : value.toStringAsFixed(1);
      return '${compact.replaceAll(RegExp(r'\.0$'), '')}K';
    }
    final value = likes / 1000000;
    final compact = value >= 100
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
    return '${compact.replaceAll(RegExp(r'\.0$'), '')}M';
  }

  Future<void> _decrementMessageLimit() async {
    final prefs = await SharedPreferences.getInstance();
    int sent = prefs.getInt('chat_messages_sent_today') ?? 0;
    sent++;
    await prefs.setInt('chat_messages_sent_today', sent);
    _calculateRemaining();
  }

  bool _isLegacyFallbackName(String rawName) {
    final normalized = UserService.sanitizePublicDisplayName(
      rawName,
    ).trim().toLowerCase();
    if (normalized.isEmpty) return false;
    if (normalized == 'admin 1' || normalized == 'admin1') return true;
    final compact = normalized.replaceAll(RegExp(r'\s+'), '');
    if (RegExp(r'^admin[0-9]+$').hasMatch(compact)) return true;
    final collapsed = normalized.replaceAll(RegExp(r'[^a-z0-9]'), '');
    return RegExp(r'^admin0*1$').hasMatch(collapsed);
  }

  bool _looksLikeFallbackName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return true;
    if (_isLegacyFallbackName(trimmed)) return true;
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

  String? _normalizedCurrentEmailPrefix() {
    final authUser = FirebaseAuth.instance.currentUser;
    final emailPrefix = (authUser?.email?.contains('@') == true)
        ? authUser?.email?.split('@').first.trim()
        : null;
    if (emailPrefix == null || emailPrefix.isEmpty) {
      return null;
    }
    return UserService.sanitizePublicDisplayName(emailPrefix).toLowerCase();
  }

  Future<String> _fetchBestNameForUserId(String userId, String fallback) async {
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();
      final data = userDoc.data();

      final emailPrefix = (data?['email'] as String?)?.contains('@') == true
          ? (data!['email'] as String).split('@').first.trim()
          : null;
      final normalizedEmailPrefix = emailPrefix == null
          ? null
          : UserService.sanitizePublicDisplayName(emailPrefix).toLowerCase();

      final candidates = <String?>[
        data?['username'] as String?,
        data?['userName'] as String?,
        data?['name'] as String?,
        data?['displayName'] as String?,
        fallback,
      ];

      for (final candidate in candidates) {
        final sanitized = UserService.sanitizePublicDisplayName(candidate);
        final normalized = sanitized.toLowerCase();
        final isEmailDerived =
            normalizedEmailPrefix != null &&
            normalized == normalizedEmailPrefix;
        if (UserService.isRecognizedPublicDisplayName(sanitized) &&
            !_looksLikeFallbackName(sanitized) &&
            !isEmailDerived) {
          return sanitized;
        }
      }
    } catch (_) {}

    if (UserService.isRecognizedPublicDisplayName(fallback) &&
        !_looksLikeFallbackName(fallback)) {
      final normalizedCurrentEmailPrefix = _normalizedCurrentEmailPrefix();
      final normalizedFallback = UserService.sanitizePublicDisplayName(
        fallback,
      ).toLowerCase();
      if (normalizedCurrentEmailPrefix != null &&
          normalizedFallback == normalizedCurrentEmailPrefix) {
        return 'Member';
      }
      return fallback;
    }
    return 'Member';
  }

  Future<String> _resolveDisplayNameForPost(Map<String, dynamic> post) {
    final rawName = UserService.sanitizePublicDisplayName(
      post['userName']?.toString(),
    );
    final userId = (post['userId']?.toString() ?? '').trim();
    final currentUser = UserService();
    final normalizedEmailPrefix = _normalizedCurrentEmailPrefix();
    final rawNameIsEmailDerived =
        normalizedEmailPrefix != null &&
        rawName.toLowerCase() == normalizedEmailPrefix;

    if (userId.isEmpty) {
      final localName = UserService.sanitizePublicDisplayName(
        currentUser.userName,
      );
      final localNameIsEmailDerived =
          normalizedEmailPrefix != null &&
          localName.toLowerCase() == normalizedEmailPrefix;
      if (UserService.isRecognizedPublicDisplayName(localName) &&
          !_looksLikeFallbackName(localName) &&
          !localNameIsEmailDerived) {
        return Future.value(localName);
      }
      if (UserService.isRecognizedPublicDisplayName(rawName) &&
          !_looksLikeFallbackName(rawName) &&
          !rawNameIsEmailDerived) {
        return Future.value(rawName);
      }
      return Future.value('Member');
    }

    if (userId == currentUser.userId) {
      final localName = UserService.sanitizePublicDisplayName(
        currentUser.userName,
      );
      final localNameIsEmailDerived =
          normalizedEmailPrefix != null &&
          localName.toLowerCase() == normalizedEmailPrefix;
      if (UserService.isRecognizedPublicDisplayName(localName) &&
          !_looksLikeFallbackName(localName) &&
          !localNameIsEmailDerived) {
        _resolvedNameFutureByUserId[userId] = Future.value(localName);
        return Future.value(localName);
      }

      final recovered = currentUser.ensureRecognizedPublicDisplayName().then((
        value,
      ) {
        final normalizedRecovered = UserService.sanitizePublicDisplayName(
          value,
        ).toLowerCase();
        final recoveredIsEmailDerived =
            normalizedEmailPrefix != null &&
            normalizedRecovered == normalizedEmailPrefix;
        if (value != null &&
            UserService.isRecognizedPublicDisplayName(value) &&
            !_looksLikeFallbackName(value) &&
            !recoveredIsEmailDerived) {
          return value;
        }
        return 'Member';
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
      await _repliesCollection(
        postId,
      ).get(const GetOptions(source: Source.server));
    } catch (e) {
      debugPrint('Community replies server refresh failed for $postId: $e');
    }
  }

  String _currentAuthUid() {
    return (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
  }

  String _effectiveCurrentUserId() {
    final authUid = _currentAuthUid();
    if (authUid.isNotEmpty) return authUid;
    final serviceId = UserService().userId.trim();
    if (serviceId.isNotEmpty) return serviceId;
    return '';
  }

  Future<String?> _canonicalPublicNameForAuthUid(String authUid) async {
    if (authUid.trim().isEmpty) return null;

    final authUser = FirebaseAuth.instance.currentUser;
    final emailPrefix = (authUser?.email?.contains('@') == true)
        ? authUser?.email?.split('@').first.trim()
        : null;
    final normalizedEmailPrefix = emailPrefix == null
        ? null
        : UserService.sanitizePublicDisplayName(emailPrefix).toLowerCase();

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(authUid)
          .get();
      final data = userDoc.data();
      if (data == null) return null;

      final candidates = <String?>[
        data['username'] as String?,
        data['userName'] as String?,
        data['displayName'] as String?,
        data['fullName'] as String?,
        data['name'] as String?,
      ];

      for (final candidate in candidates) {
        final sanitized = UserService.sanitizePublicDisplayName(candidate);
        final normalized = sanitized.toLowerCase();
        final isEmailDerived =
            normalizedEmailPrefix != null &&
            normalized == normalizedEmailPrefix;
        if (UserService.isRecognizedPublicDisplayName(sanitized) &&
            !_looksLikeFallbackName(sanitized) &&
            !isEmailDerived) {
          await UserService().setUser(authUid, sanitized);
          return sanitized;
        }
      }
    } catch (_) {}

    return null;
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
      final sanitized = UserService.sanitizePublicDisplayName(rawName);
      final normalizedEmailPrefix = _normalizedCurrentEmailPrefix();
      final isEmailDerived =
          normalizedEmailPrefix != null &&
          sanitized.toLowerCase() == normalizedEmailPrefix;
      if (UserService.isRecognizedPublicDisplayName(sanitized) &&
          !_looksLikeFallbackName(sanitized) &&
          !isEmailDerived) {
        return Future.value(sanitized);
      }
      return Future.value('Member');
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

    final authUid = _currentAuthUid();
    if (authUid.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Your account session is still loading. Please wait a moment and try again.',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    final userId = authUid;

    final publicName =
        await _canonicalPublicNameForAuthUid(authUid) ??
        await user.ensureRecognizedPublicDisplayName();
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
                                  await _submitReply(
                                    postId: postId,
                                    content: content,
                                  );
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
                                  SnackBar(
                                    content: Text('Could not send reply: $e'),
                                  ),
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
          content: Text(
            'Could not resolve account id. Please re-login and try again.',
          ),
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
          content: Text(
            'Profanity detected. Reply update flagged for moderation.',
          ),
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
    final confirmed =
        await showDialog<bool>(
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Reply deleted.')));
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
                                await _updatePost(
                                  postId: postId,
                                  content: content,
                                );
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Comment updated.')));
  }

  Future<void> _deletePost({required String postId}) async {
    final confirmed =
        await showDialog<bool>(
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Comment deleted.')));
  }

  Future<bool> _canUploadMoreImages(String userId) async {
    final limit = _usageService?.monthlyImageUploadLimit ?? 0;
    if (limit < 0) return true;
    if (limit == 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Image uploads are not enabled for your current tier.',
            ),
          ),
        );
      }
      return false;
    }

    final used = await _mediaVaultService.getSharedRoomUploadsForMonth(
      userId,
      DateTime.now(),
    );
    if (used >= limit) {
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Monthly Image Limit Reached'),
            content: const Text(
              'You have used your monthly photo upload limit. Upgrade your tier for more uploads.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
      return false;
    }

    return true;
  }

  void _clearPendingImage() {
    if (!mounted) return;
    setState(() {
      _pendingPickedImage = null;
      _pendingVaultImage = null;
      _pendingPreviewBytes = null;
      _saveCameraToVault = true;
    });
  }

  Future<void> _pickFromCamera() async {
    final userId = _effectiveCurrentUserId();
    if (userId.isEmpty) {
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Account Required'),
            content: const Text(
              'Could not resolve your account id. Please re-login and try again.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
      return;
    }
    if (!await _canUploadMoreImages(userId)) return;

    try {
      final picked = await _imagePicker.pickImage(source: ImageSource.camera);
      if (picked == null) {
        if (mounted) {
          await showDialog<void>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Camera Not Opened'),
              content: const Text(
                'No photo was captured. If camera did not open, please check Camera permission in iOS Settings for Harmony.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
        return;
      }

      final preview = await picked.readAsBytes();
      if (!mounted) return;
      setState(() {
        _pendingPickedImage = picked;
        _pendingVaultImage = null;
        _pendingPreviewBytes = preview;
        _saveCameraToVault = true;
      });
    } catch (e) {
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Could Not Open Camera'),
            content: Text('Error: $e'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _pickFromGallery() async {
    final userId = _effectiveCurrentUserId();
    if (userId.isEmpty) {
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Account Required'),
            content: const Text(
              'Could not resolve your account id. Please re-login and try again.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
      return;
    }
    if (!await _canUploadMoreImages(userId)) return;

    try {
      final picked = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (picked == null) {
        if (mounted) {
          await showDialog<void>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Photos Not Opened'),
              content: const Text(
                'No photo was selected. If Photos did not open, please check Photos permission in iOS Settings for Harmony.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
        return;
      }

      final preview = await picked.readAsBytes();
      if (!mounted) return;
      setState(() {
        _pendingPickedImage = picked;
        _pendingVaultImage = null;
        _pendingPreviewBytes = preview;
        _saveCameraToVault = false;
      });
    } catch (e) {
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Could Not Open Photos'),
            content: Text('Error: $e'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _pickFromVault() async {
    final userId = _effectiveCurrentUserId();
    if (userId.isEmpty) {
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Account Required'),
            content: const Text(
              'Could not resolve your account id. Please re-login and try again.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(sheetContext).size.height * 0.65,
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _mediaVaultService.watchVaultImages(userId),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'Could not load vault images right now.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Details: ${snapshot.error}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 12),
                        Text(
                          'Loading vault images...',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                }

                final docs = snapshot.data?.docs ?? const [];
                if (docs.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        'No vault images yet. Add one from camera or gallery.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                return Column(
                  children: [
                    const SizedBox(height: 12),
                    const Text(
                      'My Harmony Vault',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: GridView.builder(
                        padding: const EdgeInsets.all(12),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                              childAspectRatio: 1,
                            ),
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final doc = docs[index];
                          final data = doc.data();
                          final url = (data['downloadUrl'] ?? '').toString();
                          if (url.isEmpty) return const SizedBox.shrink();

                          return InkWell(
                            onTap: () {
                              if (!mounted) return;
                              setState(() {
                                _pendingVaultImage = {
                                  'imageId': doc.id,
                                  'downloadUrl': url,
                                  'storagePath': (data['storagePath'] ?? '')
                                      .toString(),
                                  'bytes':
                                      (data['bytes'] as num?)?.toInt() ?? 0,
                                  'width':
                                      (data['width'] as num?)?.toInt() ?? 0,
                                  'height':
                                      (data['height'] as num?)?.toInt() ?? 0,
                                };
                                _pendingPickedImage = null;
                                _pendingPreviewBytes = null;
                              });
                              Navigator.of(sheetContext).pop();
                            },
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.network(url, fit: BoxFit.cover),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _openImagePickerSheet() async {
    FocusScope.of(context).unfocus();

    const cameraChoice = 'camera';
    const galleryChoice = 'gallery';
    const vaultChoice = 'vault';

    final choice = await showDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Attach Image'),
          contentPadding: const EdgeInsets.only(top: 8, bottom: 8),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('Take Photo'),
                subtitle: const Text('Capture live photo from camera'),
                onTap: () => Navigator.of(dialogContext).pop(cameraChoice),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from Device Photos'),
                onTap: () => Navigator.of(dialogContext).pop(galleryChoice),
              ),
              ListTile(
                leading: const Icon(Icons.collections_bookmark_outlined),
                title: const Text('Choose from My Harmony Vault'),
                onTap: () => Navigator.of(dialogContext).pop(vaultChoice),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );

    if (!mounted || choice == null) return;

    await Future<void>.delayed(const Duration(milliseconds: 420));
    if (!mounted) return;

    try {
      switch (choice) {
        case cameraChoice:
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Take Photo selected. Opening camera...'),
              duration: Duration(milliseconds: 1400),
            ),
          );
          await _pickFromCamera();
          break;
        case galleryChoice:
          await _pickFromGallery();
          break;
        case vaultChoice:
          await _pickFromVault();
          break;
        default:
          break;
      }
    } catch (e) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Could Not Open Image Picker'),
          content: Text('Error: $e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _submitPost() async {
    final content = _postController.text.trim();
    final hasPendingImage =
        _pendingPickedImage != null || _pendingVaultImage != null;
    if (content.isEmpty && !hasPendingImage) return;

    await _calculateRemaining();

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

    if (content.isNotEmpty && ProfanityService().hasProfanity(content)) {
      final authUid = _currentAuthUid();
      if (authUid.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Your account session is still loading. Please wait a moment and try again.',
              ),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }
      final userId = authUid;
      final publicName =
          await _canonicalPublicNameForAuthUid(authUid) ??
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
      _clearPendingImage();
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

    if (content.isEmpty && !hasPendingImage) return;

    setState(() => _isPosting = true);

    try {
      final authUid = _currentAuthUid();
      if (authUid.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Your account session is still loading. Please wait a moment and try again.',
              ),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }
      final userId = authUid;

      final publicName =
          await _canonicalPublicNameForAuthUid(authUid) ??
          await user.ensureRecognizedPublicDisplayName();
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

      final postData = <String, dynamic>{
        'content': content,
        'userId': userId,
        'authorUid': authUid,
        'userName': publicName,
        'userPhoto': user.userPhoto,
        'timestamp': FieldValue.serverTimestamp(),
      };

      if (_pendingVaultImage != null) {
        final expiryDays = (_usageService?.feedImageExpiryDays ?? 5).clamp(
          1,
          90,
        );
        postData.addAll({
          'hasImage': true,
          'imageUrl': _pendingVaultImage!['downloadUrl'],
          'imageStoragePath': _pendingVaultImage!['storagePath'],
          'imageBytes': _pendingVaultImage!['bytes'],
          'imageWidth': _pendingVaultImage!['width'],
          'imageHeight': _pendingVaultImage!['height'],
          'imageCreatedAt': FieldValue.serverTimestamp(),
          'imageExpiresAt': Timestamp.fromDate(
            DateTime.now().add(Duration(days: expiryDays)),
          ),
          'imageStatus': 'active',
          'imageSource': 'vault',
        });
      } else if (_pendingPickedImage != null) {
        if (!await _canUploadMoreImages(userId)) {
          return;
        }

        final prepared = await _mediaVaultService.prepareImage(
          _pendingPickedImage!,
        );
        final roomUpload = await _mediaVaultService.uploadToRoom(
          roomId: 'community_room',
          uid: userId,
          prepared: prepared,
        );

        final expiryDays = (_usageService?.feedImageExpiryDays ?? 5).clamp(
          1,
          90,
        );
        postData.addAll({
          'hasImage': true,
          'imageUrl': roomUpload.downloadUrl,
          'imageStoragePath': roomUpload.storagePath,
          'imageBytes': roomUpload.bytes,
          'imageWidth': roomUpload.width,
          'imageHeight': roomUpload.height,
          'imageCreatedAt': FieldValue.serverTimestamp(),
          'imageExpiresAt': Timestamp.fromDate(
            DateTime.now().add(Duration(days: expiryDays)),
          ),
          'imageStatus': 'active',
          'imageSource': 'upload',
        });

        await _mediaVaultService.incrementSharedRoomUploadsForMonth(
          userId,
          DateTime.now(),
        );

        if (_saveCameraToVault) {
          await _mediaVaultService.uploadToVault(
            uid: userId,
            prepared: prepared,
            source: 'camera_auto_save',
          );
          await _mediaVaultService.incrementVaultUploadsForMonth(
            userId,
            DateTime.now(),
          );
        }
      }

      await FirebaseFirestore.instance
          .collection('community_posts')
          .add(postData);

      await _decrementMessageLimit();

      _postController.clear();
      _clearPendingImage();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Post shared with the community!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error posting: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isPosting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    return GradientScaffold(
      appBar: AppBar(
        title: const SizedBox.shrink(),
        foregroundColor: Colors.white,
        actions: [
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('app_config')
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SizedBox.shrink();
              final settings = _counterSettingsFromAppConfig(snapshot.data!);
              if (!settings.showCounter) return const SizedBox.shrink();
              return LiveRoomCounterBadge(
                roomId: 'community_room',
                enabled: true,
                showFlags: settings.showFlags,
              );
            },
          ),
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
                final settingsData =
                    snapshot.data!.data() as Map<String, dynamic>;
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
                      enableLinks: true,
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
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Text(
                      'No posts yet. Be the first!',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
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
                    final timestamp = (post['timestamp'] as Timestamp?)
                        ?.toDate();
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
                                    backgroundImage: post['userPhoto'] != null
                                        ? NetworkImage(post['userPhoto'])
                                        : null,
                                    child: post['userPhoto'] == null
                                        ? Text(
                                            displayName.isNotEmpty
                                                ? displayName[0].toUpperCase()
                                                : 'M',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 10,
                                            ),
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
                                      DateFormat(
                                        'MMM d, h:mm a',
                                      ).format(timestamp),
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.white54,
                                      ),
                                    ),
                                  SizedBox(
                                    width: 28,
                                    height: 28,
                                    child: PopupMenuButton<String>(
                                      padding: EdgeInsets.zero,
                                      icon: const Icon(
                                        Icons.more_vert,
                                        color: Colors.white38,
                                        size: 16,
                                      ),
                                      color: Colors.grey.shade900,
                                      onSelected: (value) async {
                                        if (value == 'report') {
                                          _showReportPostSheet(
                                            context,
                                            postId: posts[index].id,
                                            reportedUserId: postUserId,
                                            content:
                                                post['content']?.toString() ??
                                                '',
                                          );
                                        } else if (value == 'edit') {
                                          await _showPostEditor(
                                            postId: posts[index].id,
                                            initialContent:
                                                post['content']?.toString() ??
                                                '',
                                          );
                                        } else if (value == 'delete') {
                                          await _deletePost(
                                            postId: posts[index].id,
                                          );
                                        }
                                      },
                                      itemBuilder: (_) {
                                        if (isOwnPost) {
                                          return const [
                                            PopupMenuItem(
                                              value: 'edit',
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons.edit_outlined,
                                                    color: Colors.white70,
                                                    size: 16,
                                                  ),
                                                  SizedBox(width: 8),
                                                  Text(
                                                    'Edit post',
                                                    style: TextStyle(
                                                      color: Colors.white70,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            PopupMenuItem(
                                              value: 'delete',
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons.delete_outline,
                                                    color: Colors.redAccent,
                                                    size: 16,
                                                  ),
                                                  SizedBox(width: 8),
                                                  Text(
                                                    'Delete post',
                                                    style: TextStyle(
                                                      color: Colors.redAccent,
                                                    ),
                                                  ),
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
                                                Icon(
                                                  Icons.flag_outlined,
                                                  color: Colors.redAccent,
                                                  size: 16,
                                                ),
                                                SizedBox(width: 8),
                                                Text(
                                                  'Report post',
                                                  style: TextStyle(
                                                    color: Colors.white70,
                                                  ),
                                                ),
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
                                style: const TextStyle(
                                  color: Colors.white,
                                  height: 1.22,
                                  fontSize: 13,
                                ),
                                enableLinks: true,
                              ),
                              const SizedBox(height: 4),
                              if ((post['hasImage'] ?? false) == true &&
                                  (post['imageUrl'] ?? '')
                                      .toString()
                                      .isNotEmpty) ...[
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.network(
                                    (post['imageUrl'] ?? '').toString(),
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    height: 180,
                                  ),
                                ),
                                const SizedBox(height: 6),
                              ],
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  GestureDetector(
                                    onTap: () =>
                                        _toggleLike(posts[index].id, likedBy),
                                    child: Row(
                                      children: [
                                        Icon(
                                          likedBy.contains(uid)
                                              ? Icons.thumb_up
                                              : Icons.thumb_up_outlined,
                                          size: 13,
                                          color: likedBy.contains(uid)
                                              ? Colors.greenAccent
                                              : Colors.white54,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          _formatLikeCount(post['likes']),
                                          style: const TextStyle(
                                            color: Colors.white54,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              ThreadedRepliesPanel(
                                postId: posts[index].id,
                                isExpanded:
                                    _expandedRepliesByPostId[posts[index].id] ??
                                    false,
                                currentUserId: uid,
                                currentAuthUid: authUid,
                                repliesStream: _repliesCollection(
                                  posts[index].id,
                                ).snapshots(includeMetadataChanges: true),
                                resolveDisplayName: (userId, rawName) =>
                                    _resolveDisplayNameForUser(
                                      userId: userId,
                                      rawName: rawName,
                                    ),
                                onToggleExpanded: () {
                                  final current =
                                      _expandedRepliesByPostId[posts[index]
                                          .id] ??
                                      false;
                                  final next = !current;
                                  setState(() {
                                    _expandedRepliesByPostId[posts[index].id] =
                                        next;
                                  });
                                  if (next) {
                                    _primeRepliesFromServer(posts[index].id);
                                  }
                                },
                                onComposeReply: () =>
                                    _showReplyComposer(postId: posts[index].id),
                                onEditReply: (replyId, reply) =>
                                    _showReplyComposer(
                                      postId: posts[index].id,
                                      replyId: replyId,
                                      initialContent:
                                          reply['content']?.toString() ?? '',
                                    ),
                                onDeleteReply: (replyId, _) => _deleteReply(
                                  postId: posts[index].id,
                                  replyId: replyId,
                                ),
                                onLikeReply: (replyId, reply) =>
                                    _toggleReplyLike(
                                      postId: posts[index].id,
                                      replyId: replyId,
                                      likedBy: List<dynamic>.from(
                                        reply['likedBy'] ?? const [],
                                      ),
                                    ),
                                onReportReply: (replyId, reply) =>
                                    _showReportPostSheet(
                                      context,
                                      postId: posts[index].id + ':' + replyId,
                                      reportedUserId: (reply['userId'] ?? '')
                                          .toString()
                                          .trim(),
                                      content: (reply['content'] ?? '')
                                          .toString(),
                                    ),
                              ),
                              Divider(
                                color: Colors.white.withValues(alpha: 0.05),
                                height: 10,
                              ),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_pendingPreviewBytes != null ||
                    _pendingVaultImage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 52,
                            height: 52,
                            child: _pendingPreviewBytes != null
                                ? Image.memory(
                                    _pendingPreviewBytes!,
                                    fit: BoxFit.cover,
                                  )
                                : Image.network(
                                    (_pendingVaultImage?['downloadUrl'] ?? '')
                                        .toString(),
                                    fit: BoxFit.cover,
                                  ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Photo attached',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _pendingVaultImage != null
                                    ? 'Using image from My Harmony Vault'
                                    : 'Using new image from this device',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: _clearPendingImage,
                          icon: const Icon(Icons.close, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  if (_pendingPickedImage != null) ...[
                    Row(
                      children: [
                        Checkbox(
                          value: _saveCameraToVault,
                          onChanged: (value) {
                            if (!mounted) return;
                            setState(() => _saveCameraToVault = value ?? false);
                          },
                          activeColor: Colors.amber,
                          checkColor: Colors.black,
                        ),
                        const Expanded(
                          child: Text(
                            'Save this image to My Harmony Vault as well',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _postController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Message...',
                          hintStyle: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                          ),
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
                    SizedBox(width: isLandscape ? 4 : 6),
                    IconButton(
                      tooltip: _isLoadingImageUsage
                          ? 'Checking image uploads...'
                          : ((_usageService?.monthlyImageUploadLimit ?? 0) > 0
                                ? '${((_usageService?.monthlyImageUploadLimit ?? 0) - _imageUploadsUsedThisMonth).clamp(0, _usageService?.monthlyImageUploadLimit ?? 0)} image uploads left'
                                : 'Attach image'),
                      onPressed: _isPosting ? null : _openImagePickerSheet,
                      constraints: BoxConstraints.tightFor(
                        width: isLandscape ? 36 : 40,
                        height: isLandscape ? 36 : 40,
                      ),
                      padding: EdgeInsets.zero,
                      icon: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          const Icon(
                            Icons.add_photo_alternate_outlined,
                            color: Colors.white,
                          ),
                          Builder(
                            builder: (context) {
                              final monthlyLimit =
                                  _usageService?.monthlyImageUploadLimit ?? 0;
                              final remaining = monthlyLimit > 0
                                  ? (monthlyLimit - _imageUploadsUsedThisMonth)
                                        .clamp(0, monthlyLimit)
                                  : 0;
                              return Positioned(
                                right: -8,
                                top: -8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: monthlyLimit > 0
                                        ? Colors.amber
                                        : Colors.redAccent,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: Colors.black87,
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Text(
                                    _isLoadingImageUsage ? '...' : '$remaining',
                                    style: const TextStyle(
                                      color: Colors.black,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: isLandscape ? 4 : 8),
                    Container(
                      margin: EdgeInsets.only(right: isLandscape ? 4 : 8),
                      padding: EdgeInsets.symmetric(
                        horizontal: isLandscape ? 8 : 10,
                        vertical: isLandscape ? 4 : 6,
                      ),
                      decoration: BoxDecoration(
                        color: _messagesRemaining <= 3
                            ? Colors.red.withValues(alpha: 0.2)
                            : Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _messagesRemaining <= 3
                              ? Colors.red.withValues(alpha: 0.5)
                              : Colors.white24,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.bolt,
                            size: 14,
                            color: _messagesRemaining <= 3
                                ? Colors.redAccent
                                : Colors.amber,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$_messagesRemaining/$_dailyLimit',
                            style: TextStyle(
                              color: _messagesRemaining <= 3
                                  ? Colors.redAccent
                                  : Colors.white70,
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
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send, color: Colors.amber),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
