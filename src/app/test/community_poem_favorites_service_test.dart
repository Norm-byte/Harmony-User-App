import 'package:flutter_test/flutter_test.dart';
import 'package:harmony_user_app/services/community_poem_favorites_service.dart';

void main() {
  group('CommunityPoemFavoritesService', () {
    test('only another signed-in author can be saved', () {
      expect(
        CommunityPoemFavoritesService.canSavePost(
          {'userId': 'author-1', 'authorUid': 'author-1'},
          'reader-1',
        ),
        isTrue,
      );
      expect(
        CommunityPoemFavoritesService.canSavePost(
          {'userId': 'author-1'},
          'author-1',
        ),
        isFalse,
      );
      expect(
        CommunityPoemFavoritesService.canSavePost(
          {'authorUid': 'reader-1'},
          'reader-1',
        ),
        isFalse,
      );
      expect(
        CommunityPoemFavoritesService.canSavePost({'userId': 'author-1'}, ''),
        isFalse,
      );
    });

    test('saved snapshot carries read-only source details and stable post id', () {
      final snapshot = CommunityPoemFavoritesService.snapshotForSave(
        postId: 'poem-1',
        post: {
          'userId': 'author-1',
          'authorUid': 'author-1',
          'userName': 'Poet',
          'content': 'A saved poem',
          'hasImage': true,
          'imageUrl': 'https://example.com/poem.jpg',
        },
      );

      expect(snapshot['postId'], 'poem-1');
      expect(snapshot['sourceUserId'], 'author-1');
      expect(snapshot['sourceAuthorUid'], 'author-1');
      expect(snapshot['userName'], 'Poet');
      expect(snapshot['content'], 'A saved poem');
      expect(snapshot['imageUrl'], 'https://example.com/poem.jpg');
      expect(snapshot.containsKey('savedAt'), isTrue);
    });

    test('image is omitted from snapshot when source has no image', () {
      final snapshot = CommunityPoemFavoritesService.snapshotForSave(
        postId: 'poem-2',
        post: {'content': 'Text only', 'hasImage': false},
      );

      expect(snapshot['imageUrl'], isNull);
    });
  });
}
