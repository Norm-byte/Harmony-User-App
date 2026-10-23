# iOS 96 investigation and mandatory release-safety gate

## Current status — 23 October 2026, after 14:00 BST

### Final user acceptance and upload-only authorization

- User reports selecting an image and creating a Common Room post while Airplane Mode was enabled; after disabling Airplane Mode, the post appeared on Android as expected. This is a successful user-observed reconnect/post-delivery test. It does not prove the image reached Storage while offline or establish the exact moment of server acknowledgement (Wi-Fi can remain enabled in Airplane Mode).
- User explicitly requests checkpoint commit/push and upload-only of iOS100 to App Store Connect. Cleared-lane non-recurrence is accepted as an unresolved documented issue, not a verified scheduling fix. Memory-only pending writes are not durable across process termination; that limitation remains documented.
- Code checkpoint: 1b3877e on v86-stable-events. All temporary diagnostic tracing removed; 47 tests passed. Build100 user checks passed: Home live publish, Poetry entry, Camera/Photos/Vault, saved-poem image display, short offline/reconnect, cold-offline relaunch/reconnect and observed live count at 14:00.
- Upload is separate from review submission. Do not withdraw, replace, release, or submit the current Apple review item. Android88 unchanged. Capture actual IPA identity/hash and uploader result; do not retry a completed upload solely because its receipt was not read.

### Build100 cold-offline/reconnect user test (14:15 BST)

- User later reports no recurrence of cleared :15/:45 playback throughout the day and previous evening. User explicitly accepts recording this as unresolved/non-reproduced rather than blocking upload100 on a 24-hour test. Do not claim a proven scheduling fix. No lane/scheduler change is authorized.
- User requests final offline-write check, followed by notes commit/push and upload-only iOS100 to App Store Connect. Existing Apple review submission must remain untouched. Password only through secure hidden macOS dialog, never chat.
- Safe pending-write test: while online select a disposable saved text-only favourite (not the painting), then in Airplane Mode remove it from My Favourite Poems; reconnect without terminating the app; verify server deletion and restore favourite online if desired. This exercises ordinary queued delete, not savePost transaction (transactions require network). Memory-only pending writes do NOT survive app termination, so do not describe this as durable offline write support.

- User reports following the procedure exactly: online -> Airplane Mode -> force-close Harmony only -> cold-launch while offline -> restore network -> check Home/Poetry/image actions. User reports the entire flow was smooth/successful.
- This verifies the tested cold-offline launch and reconnect experience on build100, in addition to the earlier 30-second airplane round-trip and 14:00 live-count pass. No destructive cache clear, uninstall, device reboot, app-data clear, or attempted offline post/upload.
- Evidence is user-observed; device logs were not captured for each sub-step. Do not claim every pending-write/offline-write path was tested.

- Current source is clean of temporary tracing and built/installed as local iOS build 100. The old entries below describing installed 96/97/98/99 are chronological history, not current state.
- Build 100 changes the iOS default Firestore client to memory-only persistence, routes Home `app_config/home_screen` through the existing isolated memory client, and adjusts My Harmony saved-poem image resolution after public-feed automatic image expiry. Temporary `HARMONY_READ_TRACE` code is removed.
- Validation: 47 Flutter tests pass; focused analyzer reports existing issues but no errors in changed files; clean signed iOS build 100 was installed and tested. On build100, user confirmed Home live update, Poetry, Camera/Photos and My Harmony checks. User confirmed Airplane Mode reconnect round trip and successful image post. User confirmed accurate/smooth 13:00 and 14:00 live-count events. The 14:00 monitor recorded two thumbprints, two active sessions at event start, 100 reads without error; iPhone logged event selection/dismissal. These are strong device observations, not a guarantee against intermittent regressions.
- User confirmed on build 99: Home updates live in foreground and after lock/unlock; Poetry opens; Camera/Photos open; My Harmony saved poem image displays; Airplane Mode reconnect check for Home/Poetry/image actions passes; 13:00 counter event displayed smoothly. User confirmed 06:00 correct display while asleep, so evidence is limited. 02:00 server recorded two taps; 11:00 and 13:00 paired sessions/tap totals corroborated by Firestore. Build100 itself still needs relevant connected feature checks, including next 14:00 event if user performs it.
- Outstanding release concerns: a prior cleared `:15`/`:45` iOS playback report has not been root-caused despite those defaults being absent server-side; investigate stale pending/delivered iOS notification state separately. Memory-only behavior has passed the user's short airplane-mode/reconnect operation checks, but a cold-launch/offline and pending-write matrix remains untested. Native WatchStream target-id errors still recur without established mapping to a specific feature. No unique SDK root cause is proven.
- User's desired sequence: leave current Apple review submission untouched; Android build88 untouched; checkpoint/push the source after tests; continue iOS100 checks, resolve/triage cleared-lane concern, then prepare upload-only IPA if release gates are accepted. Do not replace/submit the existing Apple review item before it completes.

## User-required working method

This app is live. This is the only acceptable way forward for this investigation:

- A small diff is not sufficient evidence of a safe fix. Check affected dependencies and connected features before accepting it.
- Use one explicitly identified, reversible experiment at a time. Record the hypothesis, exact changes, observed outcome, and regression checks. Do not stack failed or unverified workarounds.
- Do not claim causation from unchanged source, a passing unit suite, a successful launch, or a recovered feature alone. Separate observations, hypotheses, and verified conclusions.
- Preserve data, authentication, Poetry rules acceptance, upload allowances, and server-side enforcement. Do not bypass safeguards to make UI open.
- No Android rebuild/install, admin publish, production configuration/rules changes, or Apple review changes as part of this iOS investigation without separate authorization.
- Never withdraw/replace the submission already in Apple review. Upload-only and review submission are separate actions; obtain the intended release gate before either.
- Before accepting a candidate, test Home live publication, Home after background/resume, Poetry entry, Common Room Camera and Photos selection, Vault selection, and the live event counter. Check scheduling/deletion independently where implicated.
- Document untested items and failures explicitly. A failed relevant check blocks release even if the target feature works.

## Current baseline (23 October, approximately 01:55 BST)

- Branch: v86-stable-events. Committed/pushed baseline: 2af6448 (iOS counter build 95).
- Android remains build 88; leave it unchanged.
- User confirmed build 95 reached App Store Connect. It is NOT to be put forward as the final candidate with the observed defects. The precise build selected in the existing Apple review submission has not been verified; do not guess between 88/89.
- Local source version and installed iPhone candidate: 1.0.17 (96), clean of temporary Home snapshot diagnostics.
- Uncommitted production candidate changes: Home config uses the existing isolated iOS memory-cache Firestore client; pubspec build number 96. No Home fix committed or uploaded yet.
- Home candidate had repeated server-backed live publishes in the same process, including foreground and lock/unlock checks; user also confirmed immediate Home publishing on the clean installed build.
- All 40 app tests passed after Home logging cleanup; focused Home analysis had existing warnings/info and no errors. These do not establish device-wide regression safety.

## Release blockers / evidence limits

- User reports Home 'Say it with a Poem' no longer opens.
- Common Room Add Post opens and Vault image selection works, but Camera/Photos source actions do not open the native picker despite 21 remaining monthly uploads.
- Poetry entry awaits CommunityRulesAcceptanceService.hasAccepted(), which reads the default Firestore client before navigation.
- Camera/Photos await _canUploadMoreImages(), which reads users/{uid}/usage_media/{month} through MediaVaultService's default Firestore client before calling image_picker.
- These are plausible shared-client stalls, NOT yet confirmed by per-operation device traces. Vault stream may render cached data; this is not proof of healthy fresh reads.
- Rules-acceptance and media-vault service source matches v84. Home content listener/rendering and Firebase/Firestore configuration matched v84 apart from unrelated tab labels before the local Home client change. This does NOT rule out indirect regressions or retained device state.
- Prior iOS native logs show WatchStream 'Target id not found: 430'. No verified mapping to Home/Poetry/quota targets and no proven unique SDK root cause.
- User also reports cleared :15/:45 events played on this iPhone while Android/v84 testers did not. Server reads showed those repeating defaults absent. Cause remains unresolved. Do not change lanes as a diagnostic shortcut.

## Immediate next steps
## Monitoring

### Later 06:00 / 11:00 user reports (23 October)

- User reports seeing the 11:00 count at 4 on iPhone, representing Android's viewer plus two Thumbprint taps; this supports expected cross-device display. Event server document shows thumbprintCount=2, updated 11:00:24.917 BST; iPhone logs show the 11:00 event selected and dismissed at 11:00:45.
- User slept through 06:00. Earlier device log showed the slot selected/played and the user subsequently reported that 06:00 displayed the correct count, but this is not a simultaneous user-observed test. Server monitor saw two live session records and no REST errors, but no thumbprintCount field was created. Record it as limited evidence, not a complete counter test.

### 02:00 test outcome

- User confirmed the installed clean iOS96 displayed the correct live count at 02:00 on 23 October.
- Server samples inspected shortly after the event show two session records, followed by thumbprintCount 1 (server timestamp 02:00:04.256 BST) and 2 (02:00:07.125 BST). The 71 samples available at inspection had no recorded read errors; the bounded monitor had not yet reached its scheduled end. Session records alone do not establish device identity.
- iPhone process 5043 logged the matching 02:00 event and dismissal at 02:00:10. No reinstall/restart performed for this test.
- Counter regression check passed for this event; Poetry entry, Camera/Photos and cleared-lane behavior remain release blockers. This success does not establish health of the default Firestore client.

1. Preserve the installed candidate through existing 02:00 event; no reboot, reinstall, client reset, cache clear, or code deployment immediately before it.
2. Review user observation and bounded server monitor, distinguishing server evidence from on-screen behavior.
3. Diagnose shared default-client behavior using stage-level traces of Poetry entry and Camera/Photos prechecks; compare successful isolated-client reads with default-client operations if needed. Do not call a fresh process or reinstall a fix.
4. Test a single reversible shared-client hypothesis only after capturing evidence. No per-feature client migrations or quota/rules bypasses as a substitute for diagnosis.
5. Repeat connected feature regression checks, then clean-candidate device validation before any commit/upload decision.

## Monitoring

### Local99 saved-poem display test (not release acceptance)

- User explicitly requested saved personal poem images survive public expiry until user removes their saved item.
- Implemented shared savedImageUrl resolver in CommunityPoemFavoritesService, used by both My Harmony support_intents and saved_support_posts popups. Auto-expired existing source uses saved imageUrl; active source prefers saved image with live legacy fallback; explicitly removed/non-active source status hides image; absent original retains existing saved-snapshot behavior.
- No Storage copy, quota charge, schema/rules/backend deployment, feed-rendering change or live data modification. Current public image-expiry function removes document fields but does NOT delete the underlying Storage object; exact painting saved URL returned HTTP200. Do not describe a missing Firestore field as deletion of the Storage file.
- Six new resolver regression tests; full suite 46 passed, focused resolver analysis clean. Installed LOCAL build99 with data preserved, retaining build98 client experiment and tracing flags unchanged. Source pubspec remains96; no commit/upload.
- User subsequently confirmed the requested saved-poem display test worked on local99 after being asked to check both My Harmony sections. Text+painting restoration is user-confirmed; no independent per-popup screenshot captured. Existing favourite removal and personal poem delete controls unchanged and not yet retested.
- Scope limit: this resolves known automatic public-expiry display suppression. It is NOT a new durable-storage/backup guarantee or a complete moderation-cascade implementation. Original-post absence cannot distinguish routine deletion from legal/moderation takedown with current schema; no new claim of global enforcement should be made. Any broader storage lifecycle/administrative takedown guarantee requires a separate design and approval.
- Default memory-client experiment still requires sustained, background/resume, offline/relaunch and pending-write regression checks; build99 not release-ready.

### Experiment98 user/device outcome around 02:15

- User confirmed Poetry entry, device Photos and Camera now open. Screenshot shows a test photo post with confirmation it was shared and saved to Vault.
- Trace corroboration in process5238: gallery quota gate 34ms, native Photos picker completed 2136ms; camera quota gate 47ms, native Camera completed 8346ms (includes user interaction). Later quota reads completed 37–56ms. These are successes for the experiment, not sustained/offline release acceptance.
- New observation: My Harmony Poems / My Favourite Poems popups open text but some previously saved images missing. No renderer patch applied.
- Read-only account metadata: 9 support_intents and 3 saved_support_posts. The only image-bearing favourite has a live source post marked hasImage=false, imageStatus=expired_auto, no live imageUrl, while the saved snapshot retains an imageUrl. Both popup renderers deliberately prefer the existing live post, displaying no image if its hasImage is false. Another personal poem has active live image data. Need identify which poem user viewed before claiming all images missing or a new regression.
- Backend cleanupExpiredCommunityImages sets hasImage=false, imageStatus=expired_auto and deletes live imageUrl; do not change retention or resurrect removed/expired images as an unverified display fix. This is separate from the client experiment. Need clarify intended saved-image retention policy if expired-image behaviour is the reported case.

### Confirmed trace result and single-variable experiment 98

- Build97 process 5225: preferences completed immediately; poetry.acceptance.get remained pending after eight seconds on three attempts. Gallery and Camera both remained pending in images.quota.get and quota_gate; native picker stages were never reached. Initial quota read completed in 451ms, followed by watch-stream target 430 error. This confirms blocking read stages, not a unique SDK cause.
- Local build98 installed approximately 02:13 BST. Same tracing as 97, plus ONE compile-time-gated main.dart change: default Firestore persistenceEnabled=false on iOS, immediately after Firebase.initializeApp and before providers start queries. Flag HARMONY_DEFAULT_MEMORY_EXPERIMENT=true; HARMONY_READ_TRACE=true. Does not clear disk cache, bypass rules/quotas, change Android or deploy backend.
- Forty tests passed; built/installed with data preserved. Source pubspec still 96, installed experimental binary 98. Not committed/uploaded/accepted.
- Initial process5238 Poetry acceptance traces completed in 38ms and 45ms. Native watch-stream target-not-found errors STILL occur (target38), so do not claim this removes the underlying stream fault or proves persistence is the unique root cause. Camera/Photos and sustained regression matrix still pending.
- This changes global iOS offline persistence semantics: offline/relaunch behavior and pending writes must be assessed before release. If unsuccessful, remove this experiment rather than layering another change.

### Local trace experiment after 02:00 (approximately 02:07 BST)

- Installed build 97 is a LOCAL DIAGNOSTIC, not an accepted fix or release candidate. Source pubspec still declares the prior candidate 96; build command explicitly overrides to 97 with HARMONY_READ_TRACE=true. Do not confuse the installed binary with clean 96.
- Added FirestoreReadTrace wrapper to record start/complete/error/still_pending after eight seconds, without canceling/retrying/changing operation results. No quota or rules bypass.
- Stages: poetry.button.preferences, poetry.acceptance.get, images.quota.get, images.camera/gallery.quota_gate, images.camera/gallery.native_picker.
- Temporary uncommitted edits: Home screen, Common Room screen, rules acceptance service, media vault service; new firestore_read_trace.dart. These are instrumentation only on top of the previously tested Home candidate.
- All 40 tests passed and diagnostic iOS build compiled. Installed with devicectl preserving app data; Apple/Android untouched. Reinstallation starts a fresh process, which may temporarily recover a stall: success immediately after install alone is not a fix.
- Await user tapping Home Poetry button and Common Room Add Post -> Photos (Camera separately if possible). Read fresh HARMONY_READ_TRACE entries in the existing native log. Remove tracing after experiment and record outcome before applying any recovery change.

- Existing 02:00 event ID: repeating_national_0200_20261023.
- Read-only monitor: /tmp/harmony_0200_probe_20261023.js, output /tmp/harmony_0200_probe_20261023.log.
- Scheduled sampling: 01:59:40–02:03:00 BST on 23 October. Server monitor is independent of iPhone USB connection. Authentication/read errors must be reported, not treated as absent event activity.
- Existing 03:00 event `repeating_national_0300_20261023` was verified on clean99: 100 server samples, zero read errors, count reached 2 (server timestamp 03:00:03.987 BST); user has not yet supplied a separate on-screen count report for that event.
- The 03:30 lane was absent. Do not ask users to test a nonexistent event; verify the configured slot before every future monitor.
- Confirmed existing next lanes: national_0600 and national_0900. 06:00 monitor armed: /tmp/harmony_0600_probe_20261023.js, output /tmp/harmony_0600_probe_20261023.log, sampling 05:59:40–06:03 BST on 23 October. It is read-only and independent of USB.
- User-confirmed 06:00 test on local build99: correct live count displayed. Server monitor completed 100 samples with zero REST read errors and saw two active session records at event start. User did not report any Thumbprint taps for this event; don't infer a tap result from the session records.
- iPhone native log shows `WatchStream: Not found: Target id not found: 38` at 06:00:00 and again after event dismissal. Event still played and user saw correct viewer count; stream error remains an observed signal, not a diagnosed counter failure.
- User reports 13:00 event was accurate and smooth on local build99. Read-only monitor observed thumbprintCount 1 at 13:00:04.127 BST, then 2 at 13:00:06.238; two sessions were present during the increments and there were no REST read errors. Supports the user's observation; not by itself a full release gate.
- Clean diagnostics-free build100 14:00 event: user reports smooth/accurate live count. Server monitor sampled 100 times with zero read errors; thumbprintCount reached 2 at 14:00:03.681 BST, with two sessions visible at event start. iPhone logged event selection at 14:00:00 and normal dismissal at 14:00:14. This passes the live-counter check on the clean candidate.
- Airplane Mode round-trip test on build99 (user-confirmed, about 12:06 BST): after reconnect, user says Home/Poetry/image actions all opened and worked. Trace shows camera native picker completed ~1.56s; gallery quota read/gate completed 44–45ms and gallery picker completed ~1.71s. This is a pass for the tested reconnect actions, not prolonged offline behavior; no image was submitted.
- Native iPhone capture: /tmp/harmony_ios_native_20261022.log. Inspect bounded tail windows; this file is large. Verify recent writes after USB reconnect.
- iPhone 14 UDID: 00008110-0014749A3E39401E.