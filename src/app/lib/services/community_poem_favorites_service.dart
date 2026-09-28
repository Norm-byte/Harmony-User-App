import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Stores a user's saved Community Focus posts without changing the source post.
class CommunityPoemFavoritesService {
  CommunityPoemFavoritesService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  String? get currentUserId {
    final uid = _auth.currentUser?.uid.trim() ?? '';
    return uid.isEmpty ? null : uid;
  }

  CollectionReference<Map<String, dynamic>> savedPosts(String uid) =>
      _firestore
          .collection('users')
          .doc(uid)
          .collection('saved_support_posts');

  static bool canSavePost(Map<String, dynamic> post, String currentUid) {
    final uid = currentUid.trim();
    return uid.isNotEmpty && post['isSupportRequest'] == true;
  }

  static Map<String, dynamic> snapshotForSave({
    required String postId,
    required Map<String, dynamic> post,
  }) {
    final timestamp = post['timestamp'];
    return {
      'postId': postId,
      'sourceUserId': (post['userId'] ?? '').toString(),
      'sourceAuthorUid': (post['authorUid'] ?? '').toString(),
      'userName': (post['userName'] ?? 'Member').toString(),
      'content': (post['content'] ?? '').toString(),
      'imageUrl': post['hasImage'] == true ? post['imageUrl'] : null,
      if (timestamp is Timestamp) 'sourceTimestamp': timestamp,
      'savedAt': FieldValue.serverTimestamp(),
    };
  }

  Future<void> savePost({
    required String postId,
    required Map<String, dynamic> post,
  }) async {
    final uid = currentUserId;
    if (uid == null) {
      throw StateError('Sign in to save poems to your list.');
    }
    if (!canSavePost(post, uid)) {
      throw StateError('You can only save another member’s poem here.');
    }
    final reference = savedPosts(uid).doc(postId);
    await _firestore.runTransaction((transaction) async {
      final existing = await transaction.get(reference);
      if (existing.exists) return;
      transaction.set(
        reference,
        snapshotForSave(postId: postId, post: post),
      );
    });
  }

  Future<void> removePost(String postId) async {
    final uid = currentUserId;
    if (uid == null) {
      throw StateError('Sign in to edit your saved poems list.');
    }
    await savedPosts(uid).doc(postId).delete();
  }
}
