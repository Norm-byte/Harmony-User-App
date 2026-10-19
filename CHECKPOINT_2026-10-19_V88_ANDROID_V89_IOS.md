# 19 October 2026 — Android 88 / iOS 89 release checkpoint

## Source and distribution
- Branch: `v86-stable-events`.
- Build 88 source: `bdb7b0b`; tag `checkpoint-2026-10-19-v88-overnight-passed`.
- Build 89 source: `58a9a3b`; tag `checkpoint-2026-10-19-v89-ios-device-tested`.
- Both source checkpoints pushed to GitHub; working tree clean before this note.
- Android remains build 1.0.17+88. User reports Google approved the submitted build. No build 89 Android package was made or installed.
- iOS build 1.0.17+89 installed on user's iPhone and uploaded successfully to Apple at 17:50 BST on 19 October.
- Apple delivery UUID: `18e8e178-a3d8-467c-a1da-9a61152f80f8`.
- First build 89 upload failed authentication (-22938); retry with a new app-specific password succeeded. No rebuild was needed.
- Upload is NOT review submission or release. User still needs to replace build 88 with 89 and resubmit; that action has not been verified here.
- Local artifacts: `release/app-release-1.0.17+88.aab`, `release/harmony_user_app-1.0.17+88.ipa`, `release/harmony_user_app-1.0.17+89.ipa` (release binaries are not implied to be backed up by source pushes).

## Fix history and boundaries
1. V85 Android prepared roughly seven days of events with three alarm attempts per event and repeatedly cancelled/rearmed roughly 450 alarms. Device investigation established overload/lockscreen instability. V86 restored V84 event/notification/native alarm files, retaining V85 UI features. The iOS metadata-listener change was also reverted; its causal role was suspected, not proven.
2. `36470aa`: generate daily Thumbprint defaults for today and tomorrow, retaining only starts within the next 24 hours. Date-qualified IDs use the occurrence date. This fixes the old today-only midnight gap without restoring seven-day scheduling. iOS retains its 40-alert cap.
3. `bdb7b0b`: Favourites routes YouTube to the same `TopicsFullscreenYoutubeScreen` used by Topics. Open category listens to FavoritesService rather than retaining a stale displayed list. Legacy empty youtubeUrl falls back to url; removal errors have feedback. User confirmed viewer and removal on phones. Four focused tests added.
4. `58a9a3b`: counter settings stream is created once per overlay state; LiveStatsConfigGate retains last good settings through null/error, explicitly honours Admin off, and displays connecting before settings are known. Counter reads use server source and timeouts, do not overlap, and distinguish unavailable from a verified zero. Presence writes use one batch and are independent of reads; geo enrichment is no longer on the heartbeat's critical path. Disposal/event-ID guards and HARMONY_LIVE_STATS diagnostics added. No alarm or notification scheduling changes in build 89.
5. Same build 89: poem popup opens immediately using already loaded preview/config/mode rather than awaiting config/profile/overall queries before opening. Selector retains personal/overall mode with loading/error feedback; preference write acknowledgement does not block the displayed choice. User confirmed expansion.

## Device evidence and limitations
- Build 88: user confirmed untouched midnight and 01:00 rollover tests on 19 October, plus Favourites and other UI features.
- Later build 88 iPhone counter: 13:00 visible but zero; 14:00 and 15:00 absent. Admin showLiveStats stayed true. Counter file was identical to V84; do NOT claim the midnight/Favourites changes altered it.
- Existing counter hid itself when settings were unavailable and silently reset to zero on read/write errors. These weaknesses were corrected; exact original device/network trigger was NOT established.
- Initial passive iPhone log capture produced only its startup header. An active logging process alone is not proof useful diagnostics were captured.
- Build 89: user confirmed correct counter at 16:00 and successful both-phone checks at 17:00 and 17:30. 16:30 iPhone visual result was not confirmed. Poem expansion confirmed after updated build 89 install.
- Android 88 missed automatic 16:00 launch; user opened manually. Available logs show non-alarm playback at 16:00:17. Newly published slot not reaching dormant device is only a hypothesis, not a demonstrated cause. User notes last-minute publication previously worked.
- Android alarm snapshot at 16:10: 75 scheduled attempts, corresponding to 25 events x 3; 16:30 and 17:00 armed. No evidence of the former ~450-alarm overload returning. This is a snapshot, not an indefinite reliability guarantee.
- Android 17:00 logs: alarm received 16:59:55 while locked; playback 17:00:00.474; backup attempts suppressed; lockscreen restoration complete 17:00:24.530. User confirmed later successful tests.
- Android remains unchanged because later tests passed; isolated 16:00 miss remains unresolved, not “fixed itself”.
- Final build 89 suite: all 40 tests pass. Counter gate tests cover initial unavailable state, errors/null retention, explicit off/on, and one subscription through 30 rebuilds/disposal. These tests do not prove end-to-end iPhone/network reliability or separately automate the poem popup.
- Targeted counter analyzer clean; My Harmony has pre-existing analyzer warnings. IPA build warns about default launch image; build/export/upload nevertheless succeeded.

## If symptoms recur — start here
1. Establish actual installed build and platform. Android production remains 88; iPhone test build is 89. Do not confuse source pubspec 89 with Android installation.
2. Record event ID/date/time, locked/foreground state, whether notification and media worked, and exact counter state: absent / connecting / unavailable / number. Screenshot if possible. Record Wi-Fi/mobile connectivity, without assuming Mac and phone shared failures.
3. For counter: inspect app_config/home_screen showLiveStats and HARMONY_LIVE_STATS logs (settings failed, read failed/read ok, presence failed/acknowledged). Compare event_live_viewers parent and sessions. Sessions are removed on exit; an empty later collection does not prove no earlier viewers. Another user's session is not proof the iPhone registered.
4. For Android: attach adb before event; capture DormantAlarmReceiver/MainActivity/flutter, dumpsys alarm, scheduling and receiver timestamps, duplicate suppression and lockscreen restoration. Separate not armed / not delivered / failed launch / playback failure. Inspect alarm count and rescheduling frequency, not only total published slots.
5. Do not reinstall/reopen as the first diagnostic step: this can clear intermittent state without explaining it. Do not change published slots or scheduling to treat a counter-only issue.
6. Repeat locked/resume tests and longer soak testing. A handful of passes supports submission but is not certainty against intermittent recurrence.

## Monitoring / credential notes
- Read-only server monitor: `/tmp/harmony_counter_monitor.js`; log `/tmp/harmony_counter_monitor.log`; configured end 20 October 22:00 BST. Was restarted at 15:53 on 19 October after stopping; verify process before relying on it.
- Original monitor missed events because it read only first 300 parent docs. It now queries recent updatedAt records. Mac sleep was previously blamed without evidence; caffeinate was active. Do not repeat that assumption.
- iPhone log: `/tmp/harmony_ios_20261019_counter.log`.
- Android captures: `/tmp/harmony_android_20261019.log`, `/tmp/harmony_android_live_20261019.log`, `/tmp/harmony_android_alarm_20261019.txt`. Android USB disconnected after 17:02, ending logcat; not evidence of app crash. Temporary logs are not durable backups.
- Mac/capture processes are not required for local scheduled phone alerts. Connectivity still matters for remote updates, media downloads and live stats.
- Apple upload: hidden-answer macOS dialog; pass password through environment to altool with `-p @env:APPPW`, then unset it. Never request secrets in chat or save them in notes. Account: admin@auralogical.com. Authentication failure is distinct from package validation.

## Next action
- User to select processed Apple build 89 in place of 88 and resubmit, then confirm status.
- Leave Google Android 88 unchanged; continue ordinary device observation and capture any recurrence before making targeted changes.