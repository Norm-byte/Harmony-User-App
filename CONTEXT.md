# Project Context & History

## Current Status (Jan 11, 2026)
- **User App:**
    - **Logo Zoom:** Implemented and verified on Android. Using `Transform.scale` with a `loadingBuilder` to prevent flicker. Configurable via Admin.
    - **Deployment:** Recently required a full `clean` and `build` to see changes.
- **Admin App:**
    - **Welcome Screen Manager:** Implemented. Allows setting logo zoom scale (0.4 - 3.0).
    - **Media Library:** Fixed CORS issues using `WebImage` widget. Added Rename functionality.
    - **Firebase:** `FirestoreEventRepository` is working, but `FirebaseService` is a stub.

## Critical Handover Notes for Next AI
1.  **Immediate Goal:** The user wants to continue with the **Backlog**, specifically the **Group Function** (Community Groups).
2.  **Next Task:** Implement **Community Groups Management** in the Admin App.
    -   Create `CommunityGroup` model.
    -   Create `FirestoreGroupRepository`.
    -   Create UI to manage groups (CRUD).
3.  **Technical Debt:** `FirebaseService` in Admin is a stub. It should be wired up properly to support these new features if needed, or we continue using Repositories pattern.
4.  **Minor Issue:** User App has a brief flicker of the "old logo" size on startup. User said to address this "later".

## Recent Technical Changes
- **`src/admin/lib/ui/tabs/welcome_screen_manager.dart`**: Added implementation.
- **`src/app/lib/screens/welcome_screen.dart`**: Synced with Admin config.
- **`src/admin/lib/ui/widgets/web_image_impl.dart`**: Created for CORS-safe image display.

## Next Steps (Planned)
1.  **Admin - Community Groups:** Create the data model and Admin UI to manage the groups currently hardcoded in `CommunityGroupsScreen.dart` (User App).
2.  **Admin - Firebase Wiring:** Ensure the backend support is solid for new collections.
3.  **User App - Logo Flicker:** Fix the startup flicker eventually.

## Previous History (Jan 3, 2026)
- **Project Location:** `C:\Users\norms\OneDrive\Desktop\CommunityApps\harmony by intent`
- **Critical Warning:** This project is hosted in **OneDrive**. This causes file locking/sync issues.
- **Solution:** Always run `flutter clean` before `flutter run` if changes don't appear. Long term: Move project to `C:\HarmonyApp` (outside OneDrive).

## Recent Features Implemented
1.  **Favorites Persistence:** Added `shared_preferences` to save favorites across restarts.
2.  **Landscape Fix:** Fixed `WelcomeScreen` overflow using `LayoutBuilder`.
3.  **Favorites Interaction:** 
    - Rebuilt `FavoriteItemCard` as a standalone widget.
    - Fixed tap hit-testing issues.
    - Added "Unfavorite" (X button) functionality.
    - **VERIFIED:** Favorites now persist and play correctly (Jan 1, 2026).

## Known Issues
- **"Ghost" Updates:** Due to OneDrive, sometimes the build uses cached files. **Always run `flutter clean` if changes don't appear.**


## Instructions for Future AI Agents
1.  **Read this file first.**
2.  If the user reports "changes not showing", run `flutter clean`.
3.  The "My Harmony" favorites list is in `src/app/lib/screens/settings_screen.dart`.
4.  The individual card widget is `src/app/lib/widgets/favorite_item_card.dart`.
