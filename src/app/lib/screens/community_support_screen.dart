import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
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
                                  ],
                                ),
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
}
