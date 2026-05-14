# harmony_user_app

Harmony by Intent User App

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Known-Good iOS Recovery

If iOS gets into a bad install state (cannot delete app, second-tap white screen,
or install/uninstall hangs), use this sequence:

1. Connect and unlock the iPhone.
2. From `src/app`, run:

```bash
./scripts/ios_recover_install.sh 00008110-0014749A3E39401E
```

Notes:
- This uses `build/ios/iphoneos/Runner.app` and avoids IPA profile verification issues.
- If `Runner.app` is missing, create it once with:

```bash
flutter run -d 00008110-0014749A3E39401E
```
