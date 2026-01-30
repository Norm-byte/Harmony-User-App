# Project Context & History

## Current Status (Jan 18, 2026) - **VERSION 1 LOCKED**
**Milestone Reached:** The code is completely stable and version controlled locally.

- **Version Control:** 
  - Git repository initialized in harmony-by-intent root.
  - **Critical Fix:** .gitignore was aggressively updated to exclude uild_trash, uild_trash_01, uild_temp directories which were causing Windows "Filename too long" errors during commits.
  - src/admin is tracked as a submodule.
- **Admin App (Edge/Web):**
  - **Monetization Tab:** REDESIGNED. Now includes a Deal Editor, Preview Mode, and **VIP Security**.
    - Security Logic: Access requires a code found in dmin_users or ip_codes Firestore collections.
  - **Event Scheduler:** Fixed display issues (replaced old "This Week" toggles with proper date headers).
  - **General:** Validated and running on Edge.
- **User App (Android):**
  - **Event Service:** Fixed compilation error (duplicate _eventGracePeriod).
  - **General:** Validated and running on physical Samsung Android device.

## Critical Handover Notes for Next AI
1.  **Git Status:** The repo is clean on master. If you need to make risky changes, create a new branch.
2.  **File System Constraints:** This is a Windows environment.
    - **Do NOT** create deep nested build folders or "trash" folders like src/app/build_trash_01. They break Git.
    - If git add fails with "Filename too long", check .gitignore and ensure src/app/build_trash_*/ is ignored.
3.  **App Structure:**
    - src/admin: Flutter Web project (Submodule).
    - src/app: Flutter Android/iOS project.
4.  **Architecture:**
    - **Admin:** Uses Repository pattern partially. MonetizationTab has self-contained logic for _checkVipAccess.
    - **User:** Uses Provider or Service locators.

## Recent Technical Changes
- **src/admin/lib/ui/tabs/monetization_tab.dart**: Complete rewrite. Added _checkVipAccess.
- **src/app/lib/services/event_service.dart**: Removed duplicate variable declaration.
- **.gitignore**: Updated to include deep nest ignores.

## Previous History (Jan 11, 2026)
- **User App:** Logo Zoom implemented (Transform.scale).
- **Admin App:** Welcome Screen Manager implemented.
- **Critical Warning:** Project may be in OneDrive (check path). If "changes not showing", run lutter clean.

## Instructions for Future AI Agents
1.  **Read this file first.**
2.  If asked to "restore" code, check the Git commit history for "Version 1".
3.  **Monetization Security:** The password logic is CLIENT-SIDE in the Admin app (monetization_tab.dart). It checks against Firestore documents.
