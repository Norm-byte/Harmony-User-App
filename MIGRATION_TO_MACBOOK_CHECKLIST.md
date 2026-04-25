# Migration to MacBook Checklist (Windows -> macOS)

Date prepared: 2026-04-23

## Goal
Move this project safely from the current Windows workspace to a new MacBook Pro (M5 Pro), finish the next fix, then continue daily development from macOS with iOS capability.

## Phase 1: Finish Pending Work Before Migration
1. Complete one targeted fix pass for the current alarm flow issue (`is_device_locked` method-channel mismatch).
2. Validate with one controlled timed event run.
3. If validation passes:
   - Create commit with focused message.
   - Build fresh Android App Bundle (`.aab`).
   - Record bundle path and timestamp in handoff notes.

## Phase 2: Source-of-Truth Backup on Windows
1. Ensure all wanted local changes are committed (or intentionally stashed with notes).
2. Push branch to remote Git repository.
3. Create one full zipped backup of the project root as a safety snapshot.
4. Export key operational notes:
   - Current known-good commit hash.
   - Current APK/AAB build outputs.
   - Firebase project IDs and app IDs used.
   - Play Console release status.

## Phase 3: MacBook Environment Setup
1. Install core tooling:
   - Xcode (latest stable)
   - Xcode Command Line Tools
   - Homebrew
   - Git
   - Flutter SDK
   - Android Studio (for Android SDK/AVD tooling)
   - CocoaPods
2. Verify toolchain:
   - `flutter doctor -v`
   - Resolve all critical iOS and Android warnings.
3. Configure accounts:
   - Apple Developer account sign-in in Xcode
   - Google/Firebase CLI auth if needed

## Phase 4: Project Transfer to MacBook
1. Clone project from remote Git (preferred) to a clean working folder.
2. If cloning is blocked, copy from zip backup and then connect Git remote.
3. In project root, run dependency bootstrap:
   - User app: `flutter pub get`
   - Admin app: `flutter pub get`
   - Cloud functions: `npm install` (if node modules are required)
4. For iOS setup in user app:
   - `cd ios`
   - `pod install`
   - Return to app root and run `flutter clean` then `flutter pub get`

## Phase 5: Platform Validation on MacBook
1. Android smoke test:
   - Build debug APK
   - Install to Android test device
   - Confirm event flow still works
2. iOS smoke test:
   - Open Runner in Xcode
   - Set Team and signing
   - Build and run on physical iPhone
   - Confirm login, event trigger, playback, and dismiss/return behavior

## Phase 6: Handoff Separation (Daughter Admin Workflow)
1. Keep this current Windows machine as operations/admin workstation if desired.
2. Use branch discipline:
   - Main development on MacBook
   - Admin-only urgent content edits can be done on dedicated branch
   - Merge via pull requests to avoid drift
3. Keep shared runbooks in repository so both machines follow the same process.

## Risk Controls
1. Never migrate with untracked critical changes only on C drive.
2. Do not rely on build output folders as source-of-truth.
3. Confirm signing keys/credentials are available before final cutover.
4. Keep one known-good commit hash written in handoff notes before moving.

## Tomorrow Execution Order
1. Fix and validate the pending alarm issue.
2. Commit and build new AAB.
3. Push to remote.
4. Start Mac setup and clone from remote.
5. Run smoke tests on Android and iOS.
