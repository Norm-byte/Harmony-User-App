# V85 release checkpoint — 9 October 2026

- Root branch: `v85-post-launch-fixes`.
- App checkpoint before this note: `bf359ae`; Android reliability: `43367a4`; blocker refinement: `9cbb089`; Topics/personal intents: `e238123`.
- Admin branch: `v81-global-blocks-poetry-rules`, commit `83b8b27` (owner-only personal-intent rules, deployed).
- Version: 1.0.17 (85).

## Completed and protected

- Events tab renamed Notices (display labels only).
- Topics YouTube portrait creator card, combined Watch/Like/Dislike destination and amber rotation hint; Home viewer and MP4 player unchanged.
- Slot-free Add Intent, separate owner-only personal storage, unified newest-first list, filter/edit/delete and tap-to-read popup. No registration migration or participant-count side effects.
- Discreet block-author button on other users' poem cards; blocked users shown by public username, alphabetically and scrollably. Blocking behavior and poem/favourite-poem viewers unchanged.
- Android seven-day occurrence lookahead, persisted alarm payloads, boot/package-update recovery, schedule-before-reconcile, offline/incomplete-snapshot preservation.
- Existing iPhone-only project configuration and permission-key ordering now committed at user's request.

## Validation

- Complete Flutter test suite: 35 tests passed.
- Android native alarm queue: 378 attempts scheduled through seven-day window; app-update recovery restored 378.
- Real Samsung reboot: 2026-10-09 14:57:31 recovery log confirmed `Recovery restored=378`.
- Real event delivery after reboot still requires observation; reboot recovery alone is not proof of playback.
- No Thumbprint republish needed for the installed Android change.
- iOS notification behavior retained: 24-hour window, 40-alert cap. No further iPhone install performed during release preparation.

## Release artifacts (local, ignored by Git)

- Android AAB: `release/app-release-1.0.17+85.aab`.
  - SHA256: `23701a1eb4485289f3236edd8caded60a0786962e21ac2b6e65f49a14ac2fc7b`.
- iOS IPA: `release/harmony_user_app-1.0.17+85.ipa`.
  - SHA256: `3743bf69dc22b837c18c04ded45f7c4c322d4352d0ccf742764a774b4d43725c`.
  - Verified bundle ID `com.harmonybyintent.harmonyUserApp`, version 1.0.17, build 85, device family [1].
  - Flutter archive succeeded but IPA export failed; fresh direct Xcode export to `build/ios/ipa/v85-export` succeeded.
- APK and device-installable iOS test app also retained locally in `release`.

## Apple delivery

- Upload succeeded, 9 October 2026 at 15:15 (local log time).
- Delivery UUID: `72f9b0dc-76d5-4e5d-843b-2ac3f8eedd4b`.
- Only uploaded binary: no App Store review submission, no replacement of currently selected review build, no TestFlight external review submission, no automatic distribution changes.
- App Store Connect processing still needs confirmation. Apple may require export-compliance acknowledgement before the build can be selected later.
- Android AAB not uploaded to Google Play.

## Retained limits / follow-up

- Android safety cap: 450 native attempts (normally three attempts per event), earliest first; seven-day coverage depends on enabled-slot density.
- Offline/unopened phones cannot receive later Admin edits; retain last confirmed schedule until refreshed. No server push/update-at-fire guarantee was added.
- iOS coverage can expire while unopened; returning to Harmony refreshes scheduling.
- Observe post-reboot event delivery and store processing before submitting either store release.