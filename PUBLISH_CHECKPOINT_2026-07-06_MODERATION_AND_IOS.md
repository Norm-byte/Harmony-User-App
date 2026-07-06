# Publish Checkpoint — 2026-07-06 (Moderation + iOS)

Status: Ready for next build cycle

## Included in this checkpoint
- iOS event-audio parity fix already validated on-device.
- Admin moderation queue hardening and operational workflow updates.
- User-app moderation enforcement updates:
  - Reported users are moved to `under_review` immediately.
  - `under_review` and `suspended` users are blocked from community posting/messaging.
  - Admin resolve/dismiss flows can reinstate or keep suspension based on action.
- Admin/user moderation communication path via user messages collection.

## Validation notes
- iOS test confirmed: home background audio muted did not block event audio playback.
- Moderation queue and live feed load issue was observed as resolved on latest visit.

## Commit topology
- Admin repo commit created in `src/admin`.
- Main app repo commit includes:
  - user-app moderation files
  - updated admin sub-repo pointer
  - this checkpoint note

## Regression gates before store upload
1. iOS event playback audible while home audio is muted.
2. Report action sends target user into `under_review` restriction immediately.
3. Admin can resolve/dismiss/suspend from moderation queue and state updates are reflected.
4. Restored users regain posting/messaging privileges.
5. Dashboard moderation alert count reflects pending queue items.

## Build/upload reminder
- Android: generate and upload updated AAB.
- iOS: generate and upload updated build to App Store Connect.
- Keep this checkpoint commit SHA recorded in release notes for rollback traceability.
