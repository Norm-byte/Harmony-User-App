# iOS Event Audio Parity Checkpoint (2026-07-06)

Status: Locked
Scope: iOS event audio parity with Android baseline

## Objective
Ensure home background mute does NOT suppress event overlay playback audio on iOS.

## Confirmed Outcome (Live Device)
- Device: iPhone 14 (UDID: 00008110-0014749A3E39401E)
- State at trigger: App on Home screen, background audio muted
- Event window: 21:45
- Result: Event played with audible audio

## Code Changes Included
- iOS audio session activation at app startup and via method channel:
  - src/app/ios/Runner/AppDelegate.swift
- iOS event media path hardening in native content viewer:
  - src/app/lib/widgets/media/content_viewer_native.dart
  - Ensures playback session activation on iOS before media init
  - iOS-only volume guard for event overlay context (autoPlay=true, controls=false)
- Home mute/event volume decoupling:
  - src/app/lib/screens/home_screen.dart

## Related UX/Auth Fixes Included In This Checkpoint
- Welcome/login flow and sign-out marker persistence:
  - src/app/lib/screens/welcome_screen.dart
  - src/app/lib/screens/settings_screen.dart

## No-Regression Gate (Must Pass Before Next Release Build)
1. iOS: Home background mute ON, next event must play audible audio.
2. iOS: Home background mute OFF, event still plays audible audio.
3. Android: Keep current expected behavior unchanged.
4. Home speaker toggle must only control background audio (not event overlay audio).
5. Settings event volume slider still controls event loudness when non-zero.

## Fast Revalidation Script (Manual)
1. Launch app on iOS.
2. Set Home background mute ON.
3. Wait for next scheduled event.
4. Verify event audio is audible.
5. Repeat once with Home background mute OFF.

## Notes
- If iOS deploy appears stuck at "Installing and launching...", keep device unlocked and foreground the app once.
- If uninstall/install hangs with CoreDevice connection invalidation, reboot device and redeploy.
