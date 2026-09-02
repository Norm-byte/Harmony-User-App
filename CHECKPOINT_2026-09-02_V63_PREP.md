# V63 Preparation Checkpoint - 2026-09-02

## Status
- Validated fixes are committed from this checkpoint before any new Admin Stats control work.
- Android debug and iPhone signed release test builds are installed and verified.

## Validated User-App Changes
- Learn More page header is inside `SafeArea`; its back action has a full usable touch target on Android and iPhone.
- Worldwide cards are titled `International Notice Board`.
- Noticeboard lists rebuild when a Firestore `participantCount` changes.
- The event overlay reports only real active viewer sessions. It excludes backend bridge records and never substitutes a joined-account value.

## International Noticeboard Counts
- Grey International card: joined active members for that event.
  - Auto-join enabled active Firebase accounts are included.
  - An opted-out active member is included only after manually joining.
- Grey National card: users in the viewer's region.
- Blue strip on both card types: total active Firebase member accounts worldwide.
- RevenueCat anonymous IDs are excluded from both values.
- The required `registered_events.eventId` collection-group index is deployed.
- Count functions deployed to `harmony-by-intent`:
  - `syncWorldwideParticipantCountOnPublish`
  - `syncWorldwideParticipantCountOnAutoJoinChange`
  - `aggregateTrendingIntent`

## Admin Changes
- Worldwide Events preview heading matches the user app: `International Notice Board`.
- Admin Hosting deployment succeeded on 2026-09-02.

## Validation Evidence
- `flutter test test/event_service_noticeboard_rules_test.dart`: 9 tests passed.
- `flutter analyze lib/screens/event_overlay_screen.dart`: no issues.
- `flutter analyze lib/screens/events_screen.dart`: no issues.
- Android build/install/launch succeeded on `R5CR50L7E7Y`.
- iPhone signed release build/install/launch succeeded on `00008110-0014749A3E39401E`.
- National event live-viewer counter was confirmed correct after isolation.
- International count correction was confirmed working by user.

## Next Work: Separate Admin Stats Control
- Do not alter event live-viewer calculations.
- Add a separate, explicit Admin Stats control for the blue worldwide-total strip only.
- It should support live total plus an optional admin-entered additional amount, with the two components remaining distinct in data and UI.
- Keep International joined-event and National regional counts live and unmodified by that control.