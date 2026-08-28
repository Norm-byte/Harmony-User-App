# Noticeboard Recovery Checkpoint - 2026-08-28

## Status
- Noticeboards are currently back and visible again across testers.
- Keep current state stable while store review is active.

## Regression Signal Observed
- Events tab showed no noticeboards on both Android and iOS.
- Cross-platform impact suggested shared backend/state or stream filtering behavior rather than platform UI-only break.

## Exact Code Change Applied (Minimal)
File changed:
- src/app/lib/services/event_service.dart

Change made:
- Removed Firestore listener pre-filter where isPublished == true on both event streams:
  - events
  - global_events

Why:
- Strict publish/draft gating already exists in app logic via isPublishedForUserApp().
- Listener-level bool equality can exclude otherwise valid docs when stored value format varies.
- Removing listener pre-filter restores intake while preserving strict app-side rules.

## Safety Verification Completed
- Noticeboard rule tests passed:
  - cd /Users/normansmith/Harmony-User-App/src/app
  - flutter test test/event_service_noticeboard_rules_test.dart
- Android build/install/relaunch succeeded on device R5CR50L7E7Y.
- User/tester confirmation: noticeboards returned.

## Traceability
- Repo branch: v52/wip-overlay-stats
- Head commit at checkpoint capture: 46c589b
- Checkpoint captured: 2026-08-27 23:07:26 UTC / 2026-08-28 00:07:26 BST

## Immediate Rollback Commands (If Issue Reappears)
- Show current diff for this file only:
  - cd /Users/normansmith/Harmony-User-App
  - git diff -- src/app/lib/services/event_service.dart

- Revert this file to current branch HEAD version:
  - cd /Users/normansmith/Harmony-User-App
  - git restore --source=HEAD -- src/app/lib/services/event_service.dart

- Revert this file to known checkpoint commit version (cb658cd):
  - cd /Users/normansmith/Harmony-User-App
  - git restore --source=cb658cd -- src/app/lib/services/event_service.dart

- Re-apply recovery behavior quickly (manual edit target):
  - In src/app/lib/services/event_service.dart, remove these two lines if present:
    - .where('isPublished', isEqualTo: true) under events listener
    - .where('isPublished', isEqualTo: true) under global_events listener

## Fast Redeploy Commands (Android Validation)
- cd /Users/normansmith/Harmony-User-App/src/app
- flutter build apk --debug
- flutter install -d R5CR50L7E7Y --use-application-binary build/app/outputs/flutter-apk/app-debug.apk
- ~/Library/Android/sdk/platform-tools/adb -s R5CR50L7E7Y shell am start -n com.harmonybyintent.harmony_user_app/com.harmonybyintent.harmony_user_app.MainActivity

## Operational Guardrail
- Avoid additional edits in events_screen.dart, home_screen.dart, and event_service.dart unless required.
- If noticeboards drop again, check data first (published slot docs + current show window) before refactoring UI.
