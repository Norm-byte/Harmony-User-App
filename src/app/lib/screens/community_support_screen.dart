import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/profanity_service.dart';
import '../services/user_service.dart';
import '../widgets/home_speaker_overlay.dart';
import '../widgets/support_icon.dart';

/// Full-screen shell for Community Support. Reads the same community_posts
/// collection as the Common Room, filtered to isSupportRequest == true, so
/// edits/deletes on either side stay in sync automatically (single doc,
/// single source of truth — no separate mirrored collection to drift).
class CommunitySupportScreen extends StatefulWidget {
  final Map<String, dynamic> config;

  const CommunitySupportScreen({super.key, required this.config});

  @override
  State<CommunitySupportScreen> createState() => _CommunitySupportScreenState();
}

class _CommunitySupportScreenState extends State<CommunitySupportScreen> {
  bool _isSupportingAll = false;
  final Set<String> _expandedReplyPostIds = {};
  final Map<String, TextEditingController> _replyControllers = {};

  @override
  void dispose() {
    for (final c in _replyControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _currentAuthUid() => FirebaseAuth.instance.currentUser?.uid ?? '';

  String _effectiveCurrentUserId() {
    final authUid = _currentAuthUid().trim();
    if (authUid.isNotEmpty) return authUid;
    return UserService().userId.trim();
  }

  CollectionReference<Map<String, dynamic>> _repliesCollection(String postId) {
    return FirebaseFirestore.instance
        .collection('community_posts')
        .doc(postId)
        .collection('replies');
  }

  TextEditingController _replyControllerFor(String postId) {
    return _replyControllers.putIfAbsent(postId, () => TextEditingController());
  }

  void _toggleRepliesExpanded(String postId) {
    setState(() {
      if (_expandedReplyPostIds.contains(postId)) {
        _expandedReplyPostIds.remove(postId);
      } else {
        _expandedReplyPostIds.add(postId);
      }
    });
  }

  // Same moderation gate as the Common Room composer: replies posted from
  // here land in the identical replies subcollection, so parity must include
  // the profanity/suspension checks, not just the visible reply UI.
  Future<void> _submitReply(String postId) async {
    final controller = _replyControllerFor(postId);
    final trimmed = controller.text.trim();
    if (trimmed.isEmpty) return;

    final userService = UserService();
    if (await userService.isCurrentlySuspended()) return;

    if (ProfanityService().hasProfanity(trimmed)) {
      final authUid = _currentAuthUid();
      final userId = _effectiveCurrentUserId();
      final publicName =
          await userService.ensureRecognizedPublicDisplayName() ??
          UserService.sanitizePublicDisplayName(userService.userName);
      await FirebaseFirestore.instance.collection('moderation_queue').add({
        'content': trimmed,
        'userId': userId,
        'authorUid': authUid,
        'userName': publicName,
        'source': 'Community Support Reply',
        'type': 'content_flag',
        'targetKind': 'community_reply',
        'metadata': {'postId': postId},
        'timestamp': FieldValue.serverTimestamp(),
        'reason': 'Profanity Detected',
        'status': 'pending',
      });
      controller.clear();
      return;
    }

    final authUid = _currentAuthUid();
    final userId = _effectiveCurrentUserId();
    final publicName = await userService.ensureRecognizedPublicDisplayName();
    if (userId.isEmpty || publicName == null) return;

    await _repliesCollection(postId).add({
      'content': trimmed,
      'userId': userId,
      'authorUid': authUid,
      'userName': publicName,
      'timestamp': FieldValue.serverTimestamp(),
    });
    controller.clear();
  }

  Future<void> _deleteReply(String postId, String replyId) async {
    await _repliesCollection(postId).doc(replyId).delete();
  }

  Future<void> _showEditReplyDialog(String postId, String replyId, String initialText) async {
    final controller = TextEditingController(text: initialText);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit reply'),
        content: TextField(controller: controller, maxLines: 4, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty) return;
    await _repliesCollection(postId).doc(replyId).update({
      'content': result,
      'editedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _toggleReplyLike(String postId, String replyId, List<dynamic> likedBy) async {
    final authUid = _currentAuthUid().trim();
    final userServiceUid = UserService().userId.trim();
    final actorIds = <String>{
      if (authUid.isNotEmpty) authUid,
      if (userServiceUid.isNotEmpty) userServiceUid,
    };
    if (actorIds.isEmpty) return;
    final actorId = authUid.isNotEmpty ? authUid : userServiceUid;
    final likedBySet = likedBy.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toSet();
    final alreadyLiked = actorIds.any(likedBySet.contains);

    final replyRef = _repliesCollection(postId).doc(replyId);
    if (alreadyLiked) {
      await replyRef.update({
        'likes': FieldValue.increment(-1),
        'likedBy': FieldValue.arrayRemove(actorIds.toList()),
      });
    } else {
      await replyRef.update({
        'likes': FieldValue.increment(1),
        'likedBy': FieldValue.arrayUnion([actorId]),
      });
    }
  }

  Future<void> _supportPost(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final userId = UserService().userId;
    if (userId.isEmpty) return;
    final data = doc.data();
    final supportedBy = List<String>.from(data['supportedBy'] ?? const []);
    if (supportedBy.contains(userId)) return; // one tap per user per post, like Likes

    await doc.reference.update({
      'supportTapCount': FieldValue.increment(1),
      'supportedBy': FieldValue.arrayUnion([userId]),
    });
  }

  Future<void> _supportAll(List<QueryDocumentSnapshot<Map<String, dynamic>>> posts) async {
    final userId = UserService().userId;
    if (userId.isEmpty || _isSupportingAll) return;
    setState(() => _isSupportingAll = true);
    try {
      final batch = FirebaseFirestore.instance.batch();
      var count = 0;
      for (final doc in posts) {
        final supportedBy = List<String>.from(doc.data()['supportedBy'] ?? const []);
        if (supportedBy.contains(userId)) continue;
        batch.update(doc.reference, {
          'supportTapCount': FieldValue.increment(1),
          'supportedBy': FieldValue.arrayUnion([userId]),
        });
        count++;
      }
      if (count > 0) await batch.commit();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(count > 0 ? 'Supported $count request${count == 1 ? '' : 's'}.' : 'Already supported everything here.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSupportingAll = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.config;
    final title = (config['supportButtonText'] as String?)?.trim().isNotEmpty == true
        ? config['supportButtonText']
        : 'Community Support';
    final backgroundUrl = (config['supportBackgroundImageUrl'] as String?)?.trim();
    final currentUserId = UserService().userId;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: (backgroundUrl != null && backgroundUrl.isNotEmpty)
                ? Image.network(backgroundUrl, fit: BoxFit.cover)
                : Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFF2A2550), Color(0xFF0F0D1F)],
                      ),
                    ),
                  ),
          ),
          const HomeSpeakerOverlay(),
          SafeArea(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('community_posts')
                  .where('isSupportRequest', isEqualTo: true)
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Colors.white));
                }
                final posts = snapshot.data?.docs ?? [];
                if (posts.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SupportIcon(config: config, size: 56, fallbackColor: Colors.white70),
                          const SizedBox(height: 16),
                          const Text(
                            'No community support requests yet. Check back soon, or add one from the Common Room.',
                            style: TextStyle(color: Colors.white70, fontSize: 15),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${posts.length} request${posts.length == 1 ? '' : 's'}',
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: _isSupportingAll ? null : () => _supportAll(posts),
                            icon: _isSupportingAll
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70))
                                : SupportIcon(config: config, size: 16, fallbackColor: Colors.white70),
                            label: const Text('Support All'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white70,
                              side: const BorderSide(color: Colors.white30),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                        itemCount: posts.length,
                        itemBuilder: (context, index) {
                          final doc = posts[index];
                          final post = doc.data();
                          final content = (post['content'] as String?) ?? '';
                          final userName = (post['userName'] as String?) ?? 'Member';
                          final imageUrl = (post['hasImage'] == true) ? (post['imageUrl'] as String?) : null;
                          final supportedBy = List<String>.from(post['supportedBy'] ?? const []);
                          final alreadySupported = supportedBy.contains(currentUserId);
                          final supportCount = (post['supportTapCount'] as num?)?.toInt() ?? 0;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(userName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                if (content.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(content, style: const TextStyle(color: Colors.white70)),
                                ],
                                if (imageUrl != null && imageUrl.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Image.network(imageUrl, fit: BoxFit.cover),
                                  ),
                                ],
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    IconButton(
                                      onPressed: alreadySupported ? null : () => _supportPost(doc),
                                      icon: SupportIcon(
                                        config: config,
                                        size: 22,
                                        fallbackColor: alreadySupported ? Colors.amberAccent : Colors.white70,
                                      ),
                                    ),
                                    Text(
                                      '$supportCount',
                                      style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(width: 8),
                                    TextButton.icon(
                                      onPressed: () => _toggleRepliesExpanded(doc.id),
                                      icon: const Icon(Icons.chat_bubble_outline, size: 18, color: Colors.white70),
                                      label: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                                        stream: _repliesCollection(doc.id).snapshots(),
                                        builder: (context, replySnap) {
                                          final count = replySnap.data?.docs.length ?? 0;
                                          return Text('Replies ($count)', style: const TextStyle(color: Colors.white70));
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                                if (_expandedReplyPostIds.contains(doc.id)) ...[
                                  const Divider(color: Colors.white24, height: 20),
                                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                                    stream: _repliesCollection(doc.id)
                                        .orderBy('timestamp', descending: false)
                                        .snapshots(),
                                    builder: (context, replySnap) {
                                      final replies = replySnap.data?.docs ?? [];
                                      return Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          for (final replyDoc in replies)
                                            _buildReplyTile(doc.id, replyDoc),
                                          const SizedBox(height: 8),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: TextField(
                                                  controller: _replyControllerFor(doc.id),
                                                  style: const TextStyle(color: Colors.white),
                                                  decoration: const InputDecoration(
                                                    hintText: 'Write a reply...',
                                                    hintStyle: TextStyle(color: Colors.white38),
                                                    isDense: true,
                                                  ),
                                                ),
                                              ),
                                              IconButton(
                                                icon: const Icon(Icons.send, size: 18, color: Colors.white70),
                                                onPressed: () => _submitReply(doc.id),
                                              ),
                                            ],
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ],
                              ],
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
        ],
      ),
    );
  }

  Widget _buildReplyTile(String postId, QueryDocumentSnapshot<Map<String, dynamic>> replyDoc) {
    final reply = replyDoc.data();
    final content = (reply['content'] as String?) ?? '';
    final userName = (reply['userName'] as String?) ?? 'Member';
    final likedBy = List<dynamic>.from(reply['likedBy'] ?? const []);
    final likes = (reply['likes'] as num?)?.toInt() ?? 0;
    final currentUserId = _effectiveCurrentUserId();
    final isOwnReply = (reply['userId'] == currentUserId) || (reply['authorUid'] == currentUserId);
    final alreadyLiked = likedBy.map((e) => e.toString()).contains(currentUserId);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(userName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12)),
                Text(content, style: const TextStyle(color: Colors.white70, fontSize: 13)),
              ],
            ),
          ),
          IconButton(
            iconSize: 16,
            icon: Icon(
              alreadyLiked ? Icons.favorite : Icons.favorite_border,
              color: alreadyLiked ? Colors.redAccent : Colors.white54,
            ),
            onPressed: () => _toggleReplyLike(postId, replyDoc.id, likedBy),
          ),
          Text('$likes', style: const TextStyle(color: Colors.white54, fontSize: 12)),
          if (isOwnReply)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 16, color: Colors.white54),
              onSelected: (value) {
                if (value == 'edit') {
                  _showEditReplyDialog(postId, replyDoc.id, content);
                } else if (value == 'delete') {
                  _deleteReply(postId, replyDoc.id);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
        ],
      ),
    );
  }
}
