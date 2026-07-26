# 2026-07-25 V52 Topics Hotfix and Release Split

## Current Release State
- Topics hotfix committed on branch `v52/wip-overlay-stats`.
- Root repo commit at this checkpoint: `8a724b8`.
- Android release build number used for Play: `1.0.17+54`.
- iOS release build number used for App Store Connect: `1.0.17+52`.

## What Was Fixed
- Restored the section content grid below the featured item in the Topics section detail view.
- Preserved the v52 viewer upgrades already present in the same screen.

## Store / Review Notes
- Apple accepted the fixed iOS binary into App Store Connect processing as build `1.0.17 (52)`.
- Google required higher versionCode progression, and accepted Android build `1.0.17+54`.
- App Store Connect and Play Console do not need matching build numbers across platforms for this hotfix.
- RevenueCat and entitlement wiring are not affected by the Android/iOS build-number split.

## Google Play Declaration Note
- Google Play surfaced a red warning for the advertising declaration.
- Root cause was AD_ID and related AdServices permissions merged into the Android release manifest.
- Android manifest was patched with merge-removal directives for AD_ID and AdServices permissions, then rebuilt as v54.
- v54 AAB was verified to contain no AD_ID/AdServices permissions and was accepted by Play upload.

## Artifacts
- Android bundle: `release/app-release-1.0.17+54.aab`
- Previous Android hotfix bundle: `release/app-release-1.0.17+53.aab`
- iOS IPA: `release/harmony_user_app-1.0.17+52.ipa`

## Resume Fast Path
1. If you need another Play upload, keep build number incrementing above 54.
2. If you need another App Store upload, keep iOS build numbers aligned with whatever Apple expects next.
3. If resuming months later, start from this file first, then check the current branch status.