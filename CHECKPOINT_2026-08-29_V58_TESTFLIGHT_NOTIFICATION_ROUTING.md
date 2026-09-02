# CHECKPOINT 2026-08-29 - V58 TestFlight Notification Routing

## Intent
Apply one surgical backend-only fix for community like/reply notification delivery regression observed on TestFlight user accounts.

## Symptom Observed
- User A likes User B post: User B did not receive notification.
- Reverse direction could still deliver.
- Logs showed multiple sends in topic mode for single-token owners.

## Root Cause (Confirmed from Logs)
Single-token branch in Cloud Functions helper was using topic-first routing (`mode: topic_single_token`) with `successCount: 0`, causing delivery gaps when topic subscription state was not reliable.

## Change Scope (Surgical)
- File changed: `src/cloud_functions/index.js`
- Function changed: `sendCommunityNotificationToOwner(...)`
- Only branch changed: `tokens.length === 1`

### New Behavior for Single-Token Owners
1. Send direct to token first (`mode: token`).
2. If token is invalid, prune invalid token and fallback to topic (`mode: topic_after_token_invalid`).
3. If token send errors for other reasons, fallback to topic (`mode: topic_after_token_error`).

## Non-Goals / Unchanged
- No client app code changed in this step.
- No changes to multicast behavior (`tokens.length > 1`).
- No changes to no-token topic fallback (`tokens.length === 0`).
- No changes to iOS/Android binaries in this checkpoint step.

## Validation Prior to Deploy
- `node --check src/cloud_functions/index.js` passed.
- VS Code diagnostics: no errors in `src/cloud_functions/index.js`.

## Next Step
Deploy only these functions:
- notifyOnCommunityPostLike
- notifyOnCommunityReply
- notifyOnCommunityReplyLike

## Rollback Strategy
If delivery still fails after deploy and retest, pause and revert only the single-token branch logic in `sendCommunityNotificationToOwner(...)`, then reassess with fresh logs.
