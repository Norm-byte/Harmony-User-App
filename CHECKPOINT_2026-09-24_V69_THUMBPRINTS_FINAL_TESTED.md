# v69 Thumbprints Final Checkpoint

Date: 2026-09-24
Branch: `v52/wip-overlay-stats`
Android build: `1.0.17+68`

## Verified

- Admin Thumbprints tab is deployed at `https://harmony-by-intent.web.app`.
- Thumbprints slots support National and International scopes, weekly slot loading, daily repeating defaults, separate visual media and chime audio, and published-over-draft status.
- Hide Legacy Events and Noticeboard Studio Feed are separate server-backed toggles.
- When both are off, legacy National/International Events remain available.
- When Hide Legacy is on and Studio Feed is off, the Events tab is hidden.
- When Studio Feed is on, Events remains as the destination and displays published Studio cards only.
- My Harmony is independent of noticeboard toggles.
- My Impact shows Thumbprints Tapped; My Intents and Past Intents remain separate.
- Thumbprints mode suppresses legacy National/International playback and gives Thumbprints priority for matching slots.
- Thumbprint tap writes the event aggregate and signed-in user count, shows the animated popup, and uses a large press target with staged haptic feedback.
- Event duration is enforced by the existing hard timer using the configured `durationSeconds`.
- Android v68 was tested with the 03:00/03:15/03:30/04:00 Thumbprints flow and the correct Thumbprints event source.
- iOS signed release `Runner.app` was installed and launched through the known-good recovery script.

## Packaging Rules

- Always inspect the generated Android APK/AAB with `aapt` and require `versionCode=68`.
- If Samsung reports `versionCode=67`, uninstall `com.harmonybyintent.harmony_user_app` and install the generated APK directly with adb.
- For iOS device testing, use a signed release build. Do not install a debug Runner.app with `devicectl` outside Flutter/Xcode.
- Known-good iOS recovery:

```bash
cd src/app
flutter build ios --release --no-tree-shake-icons
./scripts/ios_recover_install.sh 00008110-0014749A3E39401E
```

- Do not upload to App Store Connect until the signed release archive is confirmed locally and the Apple credential prompt is available.

## Deferred

- PDF fit/zoom remains deferred.
- Noticeboard Studio card delivery is Events-only; cards never appear in My Harmony.
