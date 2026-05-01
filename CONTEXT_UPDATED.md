# Project Context & History

## Pause Log (April 30, 2026 - Mid-Flow Hold Before Final RevenueCat Validation and Next Bundle)
**Status at pause:** User requested a break and asked to keep everything exactly as-is. Work is stable and intentionally paused mid-flow.

### Locked State To Preserve
1. Noticeboard ghost-event fix remains active and user-verified.
2. Home reels launcher restored with clearer icon + text affordance and smooth open behavior retained.
3. RevenueCat/deals mapping hardening is committed:
    - App now accepts entitlement IDs or product IDs for deal matching.
    - Multiple IDs per deal are supported (comma/pipe/space separated).
4. Working tree is clean at pause point.

### Resume-First Checklist (Next Session)
1. Validate RevenueCat dashboard API key/project alignment to clear 401 Invalid API Key.
2. Confirm the two live tiers map correctly:
    - Starter: 10 messages/day
    - Harmony 100: 100 messages/day
3. Run fresh install smoke check and verify Common Room daily counter reset behavior.
4. Build release bundle with required flag:
    - flutter build appbundle --no-tree-shake-icons

### Intent
1. Do not alter unrelated behavior before RevenueCat validation and final bundle completion.
2. Continue directly from this checkpoint on return.

## Checkpoint (April 30, 2026 - Reels Restore, Noticeboard Stable, Commit-All Fallback)
**Status:** User validated clean home experience after fresh install; reels launch control restored and smooth launch behavior retained.

### Confirmed In-Session Outcome
1. Fresh device install completed and app launched successfully.
2. Home featured card reels launcher was restored with clearer affordance (icon + "Reels" label).
3. Reels launch smoothness improvements remain active (prewarm path retained).
4. Ghost noticeboard behavior remains resolved; user confirmed no stale noticeboards visible.

### Recordkeeping Decision
1. User requested a commit-all fallback record of current working state.
2. Commit scope should preserve the full attempt trail in git history while excluding transient local cache artifacts.

### Operational Note
1. RevenueCat 401/Invalid API Key logs are environment/configuration concerns and separate from this reels/noticeboard UI and scheduling fix set.

## Checkpoint (April 25, 2026 - Bulletin Source Fixed)
**Status:** Home bulletin regression resolved and confirmed by user.

### Confirmed Resolution
1. User confirmed the home-screen bulletin now correctly displays text from App Content input.
2. Bulletin is no longer showing event noticeboard text.
3. This behavior is now considered the expected baseline and must not regress.

### Implementation Notes (Locked Intent)
1. App bulletin reader on Home uses dedicated App Content fields:
    - `appContentShowBulletin`
    - `appContentBulletinText`
2. App Content admin publisher writes dedicated fields and neutralizes legacy bulletin fields to avoid cross-talk.
3. Admin hosting was rebuilt and deployed so live publish flow matches source changes.

### Next Active Validation
1. Resume event playback test path while phone is in another app (Calculator).
2. Expected behavior for notification path:
    - Notification appears at event time.
    - User taps notification.
    - Event playback displays correctly.
    - App returns user to prior screen/app after event.
3. Next timed validation slot prepared: 21:30.

## Pause Log (April 23, 2026 - Final Night Checkpoint)
**Status at pause:** Functional flow is partially recovered after rollback to a prior approved baseline. Event playback and return path improved; residual pre-event visual artifact remains.

### What Is Confirmed From Final 23:15 Run
1. Event selection and trigger fired on time (`HARMONY_STRICT_V3` at 23:15).
2. Event payload was captured and consumed (`captureLaunchEventId` then `consume_launch_payload`).
3. User-observed outcome matched logs: slight pre-event flash/swirl, event played, then returned to Calculator.
4. Return behavior is currently the strongest validated gain compared to the earlier regression loop.

### Residual Issue To Fix Next Session
1. Pre-event flash/black swirl still occurs during Harmony foreground handoff.
2. Log evidence points to Android `SnapshotStartingWindow` and app-transition surfaces on task 490 during 23:15:04-23:15:05.
3. A non-fatal method-channel mismatch is present:
    - `MissingPluginException` for `is_device_locked` on channel `com.harmonybyintent.harmony_user_app/dormant_alarm`.

### Locked Intent For Tomorrow (Do Not Drift)
1. Keep rollback baseline as reference point (no broad UI/theme experimentation).
2. Make one targeted fix pass only:
    - Fix `is_device_locked` method-channel implementation mismatch.
    - Re-test one controlled event.
3. If result is acceptable, immediately prepare commit and Android App Bundle before migration.

### Operational Notes
1. Release install may fail with signature mismatch if device currently has debug-signed build.
2. Debug install path is currently the reliable in-place validation route.
3. Keep test cycles minimal; user requested closure-first execution.

### Tomorrow Fast-Start Checklist
1. Pull latest workspace state and verify no unintended file drift.
2. Fix `is_device_locked` channel parity between Dart and Android native layer.
3. Build/install (debug) and run one timed event validation.
4. If pass criteria met, build release AAB and prepare commit.
5. Execute migration checklist to move project from Windows to MacBook.

## Pause Log (April 21, 2026 - Live Deploy Verification Checkpoint)
**Status at pause:** Clean reinstall completed and live behavior validated with build markers.

### Locked Deployment State
1. App version on device confirmed after full uninstall/reinstall:
    - `versionName=1.0.11`
    - `versionCode=30`
2. Login screen marker visible: `Build 1.0.11`.
3. Login no longer shows `Redeem VIP Code` button.

### Confirmed Outcomes This Session
1. Locked-phone event playback stability improved and verified in-device.
2. My Harmony default tab restore delivered.
3. Community view density improved (more messages visible per screen).
4. Community counter reset observed at `100` after clean sign-in.
5. Public-facing VIP wording removed from primary user login flow.
6. Username/email exposure hardened in outbound write paths (login + chat/community/support sanitization pass).

### Current UX Notes (Do Not Regress)
1. Keep current compact community layout as baseline.
2. Keep current login behavior and build marker approach for deployment verification until next stabilization pass.
3. Keep current quota fallback behavior for elevated users.

### Next Resume Tasks
1. Replace temporary build markers once post-break validation is complete.
2. Continue refining Community presentation toward text-first/no-card visual style if requested.
3. Confirm final preferred display name source (`Admin1`) is consistently surfaced in all posting surfaces.


## Current Status (April 11, 2026 - Auth, Events, Access Fixes Verified)
**Milestone:** Auth overhaul retained, event visibility restored, access overlays removed, and new Android release prepared and uploaded.
**Status:** **User App fixed state verified live on Samsung device; Android release bundle v1.0.8+14 was built and uploaded to Play Console.**

### What Was Implemented (User App)
1. **Firebase Auth Introduced (Email + Password):**
    - Added proper sign-up and login flow.
    - Returning users are now recognized and routed directly from splash to home.
    - Added forgot-password flow (Firebase managed).

2. **VIP Flow Preserved, But Hidden in UX:**
    - VIP code field removed from visible sign-up UI.
    - VIP/beta users can enter their code in the password field.
    - App checks VIP codes first; valid code bypasses subscription and grants access as before.

3. **Account Controls in Settings:**
    - Real sign-out implemented via Firebase Auth.
    - Real password change implemented via Firebase Auth.

4. **Versioning / Play Console Incident:**
    - Version code `11` already existed.
    - `12` was also consumed during draft upload attempts.
    - Final successful release set to `version: 1.0.7+13`.

5. **Post-Release Regression Fixes (Now Verified):**
    - National noticeboard events no longer disappear due to stale slot-doc dates with missing recurrence metadata.
    - Community and Topics no longer show in-app subscription lock overlays.
    - VIP state is restored on login from Firestore.
    - VIP/Beta accounts are prevented from changing password in-app.

6. **Device Verification Outcome:**
    - Clean reinstall on Samsung device confirmed the app is now behaving correctly.
    - Temporary event triage logging was removed after verification.

### Media Capability Check (for upcoming content plan)
- **MPEG-4 / MP4 support:** Confirmed in user app players.
- **Topics tab video display:** Supported.
- **Home viewer video display:** Supported.
- **Image thumbnails for video content:** Supported when thumbnail URLs are provided (recommended for all testimonial clips).

### Apple Testing Setup (For Return)
1. **Mac Required:** iOS/TestFlight distribution requires a Mac with Xcode installed.
2. **Apple Developer Program:** Active paid Apple Developer account is required.
3. **App Store Connect App Record:** Create or confirm the iOS app entry, bundle identifier, app name, and internal testing users.
4. **Xcode Signing:** Open the iOS project in Xcode and set the correct Team, Bundle ID, signing certificate, and provisioning profile.
5. **Flutter iOS Build Dependencies:** CocoaPods installed on the Mac and able to run `pod install` for the `ios/` project.
6. **Firebase iOS Setup:** Add the iOS app in Firebase and place the correct `GoogleService-Info.plist` in the Runner project if not already configured.
7. **Capabilities / Permissions Check:** Verify notification permissions, background modes if needed, and any required Associated Domains or Sign In settings.
8. **Physical iPhone or TestFlight Group:** For real testing, use either a connected iPhone for local install or TestFlight internal testers via App Store Connect.
9. **Archive + Upload Flow:** On Mac, build/archive from Xcode or use Flutter iOS release build, then upload through Xcode Organizer / Transporter to TestFlight.
10. **Post-Upload Test Steps:** Confirm login, notifications, event noticeboards, VIP behavior, media playback, and subscription/paywall behavior on iPhone.

### Next Planned Work (When Returning)
1. Review Apple testing prerequisites and prepare iOS signing/TestFlight setup.
2. Add subscriber testimonial ingestion flow (email-received clips -> upload pipeline -> curated publish).
3. Ensure each video record stores both `videoUrl` and `thumbnailUrl`.
4. Validate end-to-end rendering in Home viewer and Topics tab on production data.

### Notes for Any Future Agent
- Do **not** reduce Android build number; always increment above latest Play-used code.
- Current known published build baseline: **13**.
- Current latest uploaded Android release candidate: **1.0.8+14**.
- Auth is now Firebase-based (not anonymous local-only identity).

## Current Status (March 24, 2026 - User App Recurrence & Visibility Logic)
**Milestone:** Fixing critical bugs in the User App regarding event display (Recurrence & Visibility).
**Status:** **User App v1.0.4+5 Built & Ready for Upload.**

### Critical Issues & Fixes
1.  **"5 Notice Boards" Bug (Fixed in v1.0.4+4):**
    - **Issue:** Daily recurrence logic in `event_service.dart` was forcing all future instances to the current day, resulting in 5 identical notice boards stacking up.
    - **Fix:** Corrected the loop to respect the original event date and only project forward correctly.

2.  **"No Events / Missing Current Event" Bug (Fixed in v1.0.4+5):**
    - **Issue:** After fixing the "5 Notice Boards," the app started hiding events immediately after their start time passed (e.g., hiding the 23:00 event at 23:01), even if they should be visible for an hour.
    - **Root Cause:** The logic `if (localEnd.isBefore(localNow))` was too aggressive. It pushed the Daily/Weekly event to the *next* occurrence immediately.
    - **Fix:** Refined logic to check `localEnd.add(visibilityAfter).isBefore(localNow)`. This ensures the event remains visible for its full duration + buffer (e.g., the 1-hour notice board period) before switching to tomorrow's instance.

3.  **Auto-System Verification:**
    - **Status:** **Verified Working.** The Admin App correctly auto-publishes Week 4 drafts when the system is enabled.

### "MyHarmony Participation" Feature (Proposed)
- **Concept:** Allow users to feel "Joined In" with a global community during hourly chimes.
- **New Feature Idea:** A toggle in "My Harmony" to choose between:
    - **Full Immersion:** Video + Audio + Intent (Current behavior).
    - **Audio Only / Ambient:** Background audio playout without blocking the screen (for less intrusive participation).
- **Status:** **Discussion Phase.** To be implemented after current stability fixes.

### User vs. Admin Responsibility
- **Clarification:** The **Admin App** sets the schedule (Start Time, End Time, Recurrence). The **User App** is responsible for interpreting that schedule relative to the user's current time.
- **Conclusion:** The current issues (missing events, stacking notice boards) are **User App logic issues**, not Admin App data issues. The fix lies in `src/app/lib/services/event_service.dart`.

### Next Steps (When You Return)
1.  **Upload v1.0.4+5:** Upload the rebuild `app-release.aab` to Google Play Internal Test.
2.  **Verify on Device:** Confirm that:
    - The "5 Notice Boards" are gone.
    - The current hourly chime/notice board **is** visible.
    - The 23:00 event (or current hour) plays correctly.
3.  **Future:** Discuss implementation of "MyHarmony Participation" (Audio Only mode).

### Technical Stack
- **User App:** Flutter 3.x, Android App Bundle (.aab).
- **Logic Key:** `EventService.dart` > `_processDocs` > Recurrence & Visibility Block.

## Previous Context (March 23, 2026 - Admin Media Library Fixes - Part 2)
**Milestone:** Resolving "broken" PDF thumbnails, narrow preview width, and activating the "Auto-System."
**Status:** **Implemented & Deployed.**

### Critical Changes (Admin App)
1.  **PDF Preview Width:**
    - **Issue:** The PDF preview popup was fixed at `1000px` width, looking very narrow on large screens.
    - **Fix:** Updated `_showMediaDetails` in `media_library_tab.dart` to use **90% of screen width** (`MediaQuery.of(context).size.width * 0.9`). This ensures it scales appropriately.

2.  **PDF Thumbnails:**
    - **Issue:** Using raw byte buffers (`Uint8List`) caused silent failures when passing data to the browser's PDF engine (`pdf.js`).
    - **Fix:** Switched to using **Blob URLs** (`html.Url.createObjectUrl`). This is the standard, robust way to handle binary files in the browser. Added extensive `console.log` statements for debugging future issues.
    - **Note:** This fix applies to **new uploads only**. Old content must be re-uploaded to generate thumbnails.

3.  **Auto-System (Publishing Logic):**
    - **Issue:** The "Auto-System" would reset when leaving the page and only "simulated" actions without actually publishing.
    - **Fix 1:** Added **persistence** using `SharedPreferences`. The "Auto-System" toggle state is now saved on the device.
    - **Fix 2:** Removed "Simulation Mode". The system now **actively publishes** events if it detects Week 4 has drafts (`isDraft: true`).
    - **Result:** When the Admin Dashboard is opened with the system active, it will automatically green-light the waiting amber weeks.

4.  **Deployment:**
    - The Admin App has been **re-deployed to Firebase Hosting** (`https://harmony-by-intent.web.app`).

### Outstanding Verification (When You Return)
- **Verify "Auto-System":** Confirm that logging into the Dashboard (with Auto-System ON) successfully publishes the "Amber" Week 4 content.
- **Verify PDF Thumbnails:** Upload a **new** PDF file and confirm the thumbnail appears.
- **Verify PDF Width:** Open a PDF preview and confirm it fills most of the screen.

### Next Steps (After Verification)
1.  **User App & Google Play:**
    - **Build User App Bundle:** Run `flutter build appbundle` for the User App.
    - **Upload to Play Console:** Guide the user through uploading the `.aab` file to **Google Play Console Internal Testing**.
    - **Testing:** Download the app from the Play Store to test real purchase flows via RevenueCat.

### Technical Stack
- **Flutter Web (Admin):** `src/admin`
- **PDF Viewer:** `IFrameElement` (Native Browser) with `#toolbar=0`.
- **Thumbnail Gen:** `ThumbnailGenerator` using **Blob URLs** & `pdf.js`.
- **Auto-System:** Client-side logic in `DashboardTab.dart`, triggered on init/toggle.

### File Modifications
- `src/admin/lib/ui/tabs/media_library_tab.dart`: Updated dialog width and PDF viewer implementation.
- `src/admin/lib/utils/thumbnail_generator.dart`: Rewritten to use Blob URLs for robustness.
- `src/admin/lib/ui/tabs/dashboard_tab.dart`: Implemented persistence and active publishing logic.


## Previous Context (March 20, 2026)
- **Store Status:** Internal Testing (Google Play) active. Waiting on propagation.
- **RevenueCat:** Configuration 100% complete.
- **User App:** Version 4+ active with improved video player.

## Pause Log (April 12, 2026 - Break Handoff)
**Status at pause:** Stable enough for break; core issue loop resolved.

### What Is Confirmed Working
1. User app event flow is functioning again with current-week publication logic.
2. Event playback works and returns correctly after event completion.
3. Overlay UX was corrected from intrusive to subtle:
    - Only a subtle transparent `Exit Event` button is shown.
    - Overpowering top overlay controls were removed.

### Latest Locked Code State
1. App commit (overlay refinement): `74a1f8a`
2. Prior stabilization commit (event playback + exit control restoration): `a8eff94`

### Release Artifact Built For Upload
1. Version in `src/app/pubspec.yaml`: `1.0.8+16`
2. AAB path:
    `C:\Harmony by Intent project\harmony by intent\harmony-by-intent\src\app\build\app\outputs\bundle\release\app-release.aab`
3. Build timestamp: `2026-04-12 18:40:54`

### Device State At Pause
1. Samsung device had latest local debug install verified during session.
2. Safe to disconnect device for break.

### Resume Checklist
1. Upload the `1.0.8+16` AAB to Play Console (Internal Testing).
2. After processing, optionally install from Play Store to verify store-delivered binary.
3. If any visual regressions appear, first compare against commit `74a1f8a`.
