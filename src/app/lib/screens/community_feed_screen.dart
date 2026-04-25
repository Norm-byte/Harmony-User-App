import 'package:flutter/material.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/gradient_scaffold.dart';
import '../services/user_service.dart';
import '../services/usage_service.dart';
import '../services/profanity_service.dart';

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
  Future<void> _toggleLike(String docId, List<dynamic> likedBy) async {
    final uid = UserService().userId;
    if (uid.isEmpty) return;
    
    final docRef = FirebaseFirestore.instance.collection('community_posts').doc(docId);
    
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
        emailPrefix,
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

    // A valid explicit post name should always override any stale cached fallback.
    if (UserService.isRecognizedPublicDisplayName(rawName) &&
        !_looksLikeFallbackName(rawName)) {
      if (userId.isNotEmpty) {
        _resolvedNameFutureByUserId[userId] = Future.value(rawName);
      }
      return Future.value(rawName);
    }

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

    // final content = _postController.text.trim(); // Removed duplicate
    if (content.isEmpty) return;

    setState(() => _isPosting = true);

    try {
      final user = UserService();
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
    return GradientScaffold(
      appBar: AppBar(
        title: const Text('Community Room • 1.0.11'),
        foregroundColor: Colors.white,
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
              final adminMessage = data['admin_message'] as String?;

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
                        const CircleAvatar(
                          radius: 16,
                          backgroundColor: Colors.amber,
                          child: Icon(Icons.shield, size: 16, color: Colors.black),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Admin',
                          style: TextStyle(
                            color: Colors.amber,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const Spacer(),
                        Icon(Icons.push_pin, size: 16, color: Colors.white.withValues(alpha: 0.5)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
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
                  reverse: true, // Typically chats are bottom-up, but this was top-down. Let's keep it consistent or flip?
                  // User said "appear the same as... newly created chat rooms". Chat rooms are usually reverse.
                  // But this is a "Feed" (like Facebook). 
                  // If I move input to bottom, it feels more like a Chat.
                  // I will KEEP it standard list for now but move input to bottom.
                  padding: const EdgeInsets.all(16),
                  itemCount: posts.length,
                  itemBuilder: (context, index) {
                    final post = posts[index].data() as Map<String, dynamic>;
                    final timestamp = (post['timestamp'] as Timestamp?)?.toDate();
                    final likedBy = List<String>.from(post['likedBy'] ?? []);
                    final uid = UserService().userId;

                    return FutureBuilder<String>(
                      future: _resolveDisplayNameForPost(post),
                      builder: (context, nameSnapshot) {
                        final displayName = nameSnapshot.data ?? 'Member';
                        return Padding(
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
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
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
                                          '${post['likes'] ?? 0}',
                                          style: const TextStyle(color: Colors.white54, fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
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
            padding: const EdgeInsets.all(16),
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
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Daily Limit Counter
                Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                IconButton(
                  onPressed: _isPosting ? null : _submitPost,
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
