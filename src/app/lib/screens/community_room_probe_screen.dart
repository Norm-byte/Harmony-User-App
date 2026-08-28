import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../widgets/gradient_scaffold.dart';

class CommunityRoomProbeScreen extends StatelessWidget {
  const CommunityRoomProbeScreen({super.key});

  double _imageAspectRatio(Map<String, dynamic> post) {
    final width = (post['imageWidth'] as num?)?.toDouble() ?? 0;
    final height = (post['imageHeight'] as num?)?.toDouble() ?? 0;
    if (width > 0 && height > 0) {
      return (width / height).clamp(0.45, 1.8);
    }
    return 0.72;
  }

  Future<void> _showExpandedImage(BuildContext context, String imageUrl) async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.94),
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(12),
          child: Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: Center(
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(
        title: const Text('COMMON ROOM PROBE'),
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
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

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Probe could not load posts: ${snapshot.error}',
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final docs = snapshot.data?.docs ?? const [];
          if (docs.isEmpty) {
            return const Center(
              child: Text(
                'No Common Room posts yet.',
                style: TextStyle(color: Colors.white70),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final post = docs[index].data();
              final imageUrl = (post['imageUrl'] ?? '').toString();
              final hasImage = (post['hasImage'] ?? false) == true && imageUrl.isNotEmpty;
              final ts = (post['timestamp'] as Timestamp?)?.toDate();
              final userName = (post['userName'] ?? 'Member').toString();
              final content = (post['content'] ?? '').toString();

              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: Colors.white12,
                          child: Text(
                            userName.isNotEmpty ? userName[0].toUpperCase() : 'M',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            userName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        if (ts != null)
                          Text(
                            DateFormat('MMM d, h:mm a').format(ts),
                            style: const TextStyle(color: Colors.white54),
                          ),
                      ],
                    ),
                    if (content.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        content,
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ],
                    if (hasImage) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Colors.amber.withValues(alpha: 0.7)),
                        ),
                        child: const Text(
                          'PROBE IMAGE RENDER',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          width: double.infinity,
                          color: Colors.black.withValues(alpha: 0.22),
                          child: AspectRatio(
                            aspectRatio: _imageAspectRatio(post),
                            child: Image.network(
                              imageUrl,
                              fit: BoxFit.contain,
                              alignment: Alignment.center,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () => _showExpandedImage(context, imageUrl),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.amber,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          icon: const Icon(Icons.open_in_full),
                          label: const Text(
                            'VIEW FULL PHOTO',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}