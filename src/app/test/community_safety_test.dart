import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:harmony_user_app/services/community_rules_acceptance_service.dart';
import 'package:harmony_user_app/services/community_safety_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CommunitySafetyUtils', () {
    test('resolves current and legacy author identifiers', () {
      expect(CommunitySafetyUtils.authorId({'authorUid': 'uid-1'}), 'uid-1');
      expect(CommunitySafetyUtils.authorId({'userId': 'user-2'}), 'user-2');
      expect(
        CommunitySafetyUtils.authorId({'authorUid': ' ', 'senderId': 'sender-3'}),
        'sender-3',
      );
    });

    test('filters only authors present in the block list', () {
      expect(
        CommunitySafetyUtils.isBlocked(
          {'authorUid': 'blocked-1'},
          {'blocked-1'},
        ),
        isTrue,
      );
      expect(
        CommunitySafetyUtils.isBlocked({'userId': 'clear-1'}, {'blocked-1'}),
        isFalse,
      );
    });
  });

  group('CommunityRulesAcceptanceService', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('persists signed-out acceptance by local identity and rules version', () async {
      final service = CommunityRulesAcceptanceService(
        authUidProvider: () => null,
        localUserIdProvider: () => 'local-user-7',
      );

      expect(await service.hasAccepted('1'), isFalse);
      await service.recordAcceptance('1');
      expect(await service.hasAccepted('1'), isTrue);
      expect(await service.hasAccepted('2'), isFalse);

      final otherIdentity = CommunityRulesAcceptanceService(
        authUidProvider: () => null,
        localUserIdProvider: () => 'local-user-8',
      );
      expect(await otherIdentity.hasAccepted('1'), isFalse);
    });

    test('acceptance requires the exact non-empty current version', () {
      expect(
        CommunityRulesAcceptanceService.isCurrentVersionAccepted('1', '1'),
        isTrue,
      );
      expect(
        CommunityRulesAcceptanceService.isCurrentVersionAccepted('1', '2'),
        isFalse,
      );
      expect(
        CommunityRulesAcceptanceService.isCurrentVersionAccepted('1', ''),
        isFalse,
      );
    });
  });
}
