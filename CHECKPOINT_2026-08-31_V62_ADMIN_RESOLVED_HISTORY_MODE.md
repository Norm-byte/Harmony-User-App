# Checkpoint - 2026-08-31 - V62 Admin Resolved History Mode

## Scope
This checkpoint captures the admin moderation workflow hardening and resolved-tab UX improvements completed on branch `v52/wip-overlay-stats`.

## Admin Commit
- Repository: `src/admin`
- Commit: `2d58845`
- Message: `Admin moderation resolved workflow + history mode UX`

## What Is Live
- Admin hosting deployed: https://harmony-by-intent.web.app
- Firestore rules deployed from `src/admin/firestore.rules`

## Delivered Moderation Capabilities
- Moderation queue decisions now produce audit records in `moderation_cases`.
- Resolved tab supports search by case number.
- Resolved tab includes reporter and reported-user identity fields.
- Decision styling:
  - Agree: green-tinted card and badge
  - Disagree: red-tinted card and badge
- Decision filter control: Both / Agree / Disagree.
- History mode in Resolved:
  - Tap a card to scope to that user’s historical resolved incidents.
  - Summary text shows: `Showing X cases for ...`.
  - Back control returns to full list.
- Resolved card actions:
  - Edit case note
  - Manage User (routes via existing admin callback)
  - View History (when multiple incidents exist)

## Data and Safety Fixes
- Added `moderation_cases` access rules for active admins.
- Decision flow reordered so case write occurs before upheld-notification send.
- Error surfacing improved: decision failures now show red snackbar with error.

## V62 Context
- Aligns with the current v62 release cycle context for iOS/Android and admin moderation operations.

## Notes for Next Iteration
- Consider moving notification send to backend function for stronger trust boundary.
- Optionally add a top-level count ribbon in Resolved for current filter + history scope.
