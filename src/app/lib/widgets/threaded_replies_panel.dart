import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'translatable_text.dart';

class ThreadedRepliesPanel extends StatelessWidget {
  final String postId;
  final bool isExpanded;
  final String currentUserId;
  final String currentAuthUid;
  final Stream<QuerySnapshot> repliesStream;
  final Future<String> Function(String userId, String rawName)
      resolveDisplayName;
  final VoidCallback onToggleExpanded;
  final VoidCallback onComposeReply;
  final Future<void> Function(String replyId, Map<String, dynamic> reply)
    onEditReply;
  final Future<void> Function(String replyId, Map<String, dynamic> reply)
    onDeleteReply;
  final Future<void> Function(String replyId, Map<String, dynamic> reply)
    onLikeReply;
  final Future<void> Function(String replyId, Map<String, dynamic> reply)
    onReportReply;

  const ThreadedRepliesPanel({
    super.key,
    required this.postId,
    required this.isExpanded,
    required this.currentUserId,
    required this.currentAuthUid,
    required this.repliesStream,
    required this.resolveDisplayName,
    required this.onToggleExpanded,
    required this.onComposeReply,
    required this.onEditReply,
    required this.onDeleteReply,
    required this.onLikeReply,
    required this.onReportReply,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: repliesStream,
      builder: (context, replySnapshot) {
        final replyCount = replySnapshot.hasData ? replySnapshot.data!.docs.length : 0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                GestureDetector(
                  onTap: onToggleExpanded,
                  child: Row(
                    children: [
                      Icon(
                        isExpanded ? Icons.chat_bubble : Icons.chat_bubble_outline,
                        size: 13,
                        color: Colors.white54,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$replyCount',
                        style: const TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                GestureDetector(
                  onTap: onComposeReply,
                  child: const Row(
                    children: [
                      Icon(Icons.reply, size: 13, color: Colors.amber),
                      SizedBox(width: 4),
                      Text(
                        'Reply',
                        style: TextStyle(color: Colors.amber, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (isExpanded)
              _RepliesList(
                repliesSnapshot: replySnapshot,
                currentUserId: currentUserId,
                currentAuthUid: currentAuthUid,
                resolveDisplayName: resolveDisplayName,
                onEditReply: onEditReply,
                onDeleteReply: onDeleteReply,
                onLikeReply: onLikeReply,
                onReportReply: onReportReply,
              ),
          ],
        );
      },
    );
  }
}

class _RepliesList extends StatelessWidget {
  static const int _maxInlineReplies = 3;

  final AsyncSnapshot<QuerySnapshot> repliesSnapshot;
  final String currentUserId;
  final String currentAuthUid;
  final Future<String> Function(String userId, String rawName)
      resolveDisplayName;
  final Future<void> Function(String replyId, Map<String, dynamic> reply)
      onEditReply;
  final Future<void> Function(String replyId, Map<String, dynamic> reply)
      onDeleteReply;
    final Future<void> Function(String replyId, Map<String, dynamic> reply)
      onLikeReply;
    final Future<void> Function(String replyId, Map<String, dynamic> reply)
      onReportReply;

  const _RepliesList({
    required this.repliesSnapshot,
    required this.currentUserId,
    required this.currentAuthUid,
    required this.resolveDisplayName,
    required this.onEditReply,
    required this.onDeleteReply,
    required this.onLikeReply,
    required this.onReportReply,
  });

  DateTime? _replyTime(Map<String, dynamic> reply) {
    final primary = reply['timestamp'];
    if (primary is Timestamp) return primary.toDate();
    if (primary is int) {
      // Support historical docs that stored epoch milliseconds directly.
      return DateTime.fromMillisecondsSinceEpoch(primary);
    }
    if (primary is String) {
      final parsed = DateTime.tryParse(primary);
      if (parsed != null) return parsed;
    }
    final fallback = reply['createdAt'];
    if (fallback is Timestamp) return fallback.toDate();
    if (fallback is int) {
      return DateTime.fromMillisecondsSinceEpoch(fallback);
    }
    if (fallback is String) {
      final parsed = DateTime.tryParse(fallback);
      if (parsed != null) return parsed;
    }
    return null;
  }

  String _replyUserId(Map<String, dynamic> reply) {
    return (reply['userId'] ??
            reply['authorId'] ??
            reply['senderId'] ??
            reply['uid'] ??
            '')
        .toString()
        .trim();
  }

  String _replyAuthorUid(Map<String, dynamic> reply) {
    return (reply['authorUid'] ?? reply['uid'] ?? '').toString().trim();
  }

  String _replyDisplayName(Map<String, dynamic> reply) {
    return (reply['userName'] ??
            reply['name'] ??
            reply['senderName'] ??
            reply['displayName'] ??
            'Member')
        .toString();
  }

  String _replyContent(Map<String, dynamic> reply) {
    return (reply['content'] ??
            reply['text'] ??
            reply['message'] ??
            reply['body'] ??
            '')
        .toString();
  }

  Widget _buildReplyTile(BuildContext context, QueryDocumentSnapshot replyDoc) {
    final reply = replyDoc.data() as Map<String, dynamic>;
    final timestamp = _replyTime(reply);
    final userId = _replyUserId(reply);
    final replyAuthorUid = _replyAuthorUid(reply);
    final rawName = _replyDisplayName(reply);
    final replyContent = _replyContent(reply);
    final likedBy = List<dynamic>.from(reply['likedBy'] ?? const []);
    final isLiked = likedBy.contains(currentUserId) ||
      (currentAuthUid.isNotEmpty && likedBy.contains(currentAuthUid));
    final likesCount = (reply['likes'] is num)
      ? (reply['likes'] as num).toInt()
      : int.tryParse('${reply['likes']}') ?? 0;
    final isOwner = <String>{currentUserId.trim(), currentAuthUid.trim()}
        .where((v) => v.isNotEmpty)
        .any((currentId) => currentId == userId || currentId == replyAuthorUid);

    return FutureBuilder<String>(
      future: resolveDisplayName(userId, rawName),
      builder: (context, nameSnapshot) {
        final displayName = nameSnapshot.data ?? 'Member';
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 8,
                backgroundColor: Colors.white10,
                child: Text(
                  displayName.isNotEmpty ? displayName[0].toUpperCase() : 'M',
                  style: const TextStyle(color: Colors.white, fontSize: 8),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          displayName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (timestamp != null)
                          Text(
                            DateFormat('MMM d, h:mm a').format(timestamp),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.45),
                              fontSize: 10,
                            ),
                          ),
                        if (isOwner)
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: PopupMenuButton<String>(
                              padding: EdgeInsets.zero,
                              icon: Icon(
                                Icons.more_horiz,
                                size: 15,
                                color: Colors.white.withValues(alpha: 0.55),
                              ),
                              color: Colors.grey.shade900,
                              onSelected: (value) async {
                                if (value == 'edit') {
                                  await onEditReply(replyDoc.id, reply);
                                } else if (value == 'delete') {
                                  await onDeleteReply(replyDoc.id, reply);
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Row(
                                    children: [
                                      Icon(Icons.edit_outlined, color: Colors.white70, size: 16),
                                      SizedBox(width: 8),
                                      Text('Edit reply', style: TextStyle(color: Colors.white70)),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(Icons.delete_outline, color: Colors.redAccent, size: 16),
                                      SizedBox(width: 8),
                                      Text('Delete reply', style: TextStyle(color: Colors.redAccent)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    TranslatableText(
                      replyContent,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        GestureDetector(
                          onTap: () async => onLikeReply(replyDoc.id, reply),
                          child: Row(
                            children: [
                              Icon(
                                isLiked
                                    ? Icons.thumb_up
                                    : Icons.thumb_up_outlined,
                                size: 13,
                                color: isLiked
                                    ? Colors.greenAccent
                                    : Colors.white54,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '$likesCount',
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 14),
                        GestureDetector(
                          onTap: () async => onReportReply(replyDoc.id, reply),
                          child: Row(
                            children: [
                              Icon(
                                Icons.more_horiz,
                                color: Colors.white.withValues(alpha: 0.55),
                                size: 16,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showAllRepliesSheet(
    BuildContext context,
    List<QueryDocumentSnapshot> replies,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111111),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(sheetContext).size.height * 0.72,
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'All replies (${replies.length})',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                const Divider(height: 1, color: Colors.white10),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    itemCount: replies.length,
                    itemBuilder: (context, index) => _buildReplyTile(context, replies[index]),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!repliesSnapshot.hasData || repliesSnapshot.data!.docs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 6, left: 26),
        child: Text(
          'No replies yet.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 11),
        ),
      );
    }

    final replies = List<QueryDocumentSnapshot>.from(repliesSnapshot.data!.docs)
      ..sort((a, b) {
        final aData = a.data() as Map<String, dynamic>;
        final bData = b.data() as Map<String, dynamic>;
        final aTime = _replyTime(aData);
        final bTime = _replyTime(bData);
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return -1;
        if (bTime == null) return 1;
        return aTime.compareTo(bTime);
      });

    final inlineReplies = replies.length > _maxInlineReplies
        ? replies.take(_maxInlineReplies).toList()
        : replies;
    final hasMoreReplies = replies.length > _maxInlineReplies;

    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 26),
      child: Column(
        children: [
          ...inlineReplies.map((replyDoc) => _buildReplyTile(context, replyDoc)),
          if (hasMoreReplies)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => _showAllRepliesSheet(context, replies),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 2),
                  minimumSize: const Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'View all replies (${replies.length})',
                  style: const TextStyle(color: Colors.amber, fontSize: 11),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
