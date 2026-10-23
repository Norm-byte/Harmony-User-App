import 'package:flutter_test/flutter_test.dart';
import 'package:harmony_user_app/services/community_poem_favorites_service.dart';

void main() {
  group('saved poem image retention', () {
    const saved = {'imageUrl': 'https://example.com/saved.jpg'};

    test('automatic public expiry retains the personal saved image', () {
      expect(CommunityPoemFavoritesService.savedImageUrl(
        saved: saved,
        livePost: {'hasImage': false, 'imageStatus': 'expired_auto'},
      ), saved['imageUrl']);
    });

    test('saved image remains when the original post is no longer available', () {
      expect(CommunityPoemFavoritesService.savedImageUrl(saved: saved),
          saved['imageUrl']);
    });

    test('explicit removal and moderation do not restore saved images', () {
      for (final status in ['removed_by_owner', 'removed_by_admin', 'blocked']) {
        expect(CommunityPoemFavoritesService.savedImageUrl(
          saved: saved,
          livePost: {'hasImage': false, 'imageStatus': status},
        ), isNull);
      }
    });

    test('legacy explicit removal without status remains hidden', () {
      expect(CommunityPoemFavoritesService.savedImageUrl(
        saved: saved, livePost: {'hasImage': false},
      ), isNull);
    });

    test('active images prefer saved snapshot, with legacy live fallback', () {
      const live = {'hasImage': true, 'imageUrl': 'https://example.com/live.jpg'};
      expect(CommunityPoemFavoritesService.savedImageUrl(
        saved: saved, livePost: live,
      ), saved['imageUrl']);
      expect(CommunityPoemFavoritesService.savedImageUrl(
        saved: {}, livePost: live,
      ), live['imageUrl']);
    });

    test('admin-restored source image remains visible in saved poems', () {
      expect(CommunityPoemFavoritesService.savedImageUrl(
        saved: saved,
        livePost: {
          'hasImage': true,
          'imageStatus': 'restored_admin',
          'imageUrl': 'https://example.com/restored.jpg',
        },
      ), saved['imageUrl']);
    });

    test('expiry cannot invent an image for a text-only saved poem', () {
      expect(CommunityPoemFavoritesService.savedImageUrl(
        saved: {}, livePost: {'imageStatus': 'expired_auto', 'hasImage': false},
      ), isNull);
    });
  });

  group('CommunityPoemFavoritesService', () {
    test('a signed-in user can save their own or another member’s poem', () {
      expect(
        CommunityPoemFavoritesService.canSavePost(
          {
            'userId': 'author-1',
            'authorUid': 'author-1',
            'isSupportRequest': true,
          },
          'reader-1',
        ),
        isTrue,
      );
      expect(
        CommunityPoemFavoritesService.canSavePost(
          {'userId': 'author-1', 'isSupportRequest': true},
          'author-1',
        ),
        isTrue,
      );
      expect(
        CommunityPoemFavoritesService.canSavePost(
          {'userId': 'author-1', 'isSupportRequest': true},
          '',
        ),
        isFalse,
      );
      expect(
        CommunityPoemFavoritesService.canSavePost(
          {'userId': 'author-1', 'isSupportRequest': false},
          'reader-1',
        ),
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
