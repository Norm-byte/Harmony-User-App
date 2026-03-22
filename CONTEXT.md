# Project Context & History

## Current Status (March 20, 2026 - Mid-Day/Waiting) - **VERSION 4+ (Main Branch)**
**Milestone Reached:** Internal Testers Setup Complete. App Release Active.
**Current Blocker:** Google Play Store Propagation (Waiting for "Cannot find app" error to resolve).

- **Google Play Status:**
  - **Internal Testing:** List created ("Internal Team"). Email added & invitation accepted.
  - **Device Config:** Samsung Phone has **"Internal app sharing"** enabled in Play Store Developer Settings (Success!).
  - **Issue:** The Play Store link currently opens to a blank white screen or "Cannot find app". This is standard propagation delay for a first release.
  - **Action:** Wait 1-2 hours for Google servers to sync the listing.

- **RevenueCat Status:**
  - **Ready:** Configuration is 100% complete and correct.
  - **Next Step:** Verify "Harmony Starter" text update on the fresh install.

- **Immediate Next Steps (When Resuming):**
  1.  **Wait:** Give Google Play servers time to process the new internal track.
  2.  **Retry Install:** Open the Tester Link again on the Samsung phone.
  3.  **Verify Paywall:** Confirm text is correct.
  4.  **Test Purchase:** Use the License Testing account to buy the subscription.

- **Store Compliance (UGC):**
  - **Implemented:** "Report & Block" feature.
  - **Pending:** Terms of Use (EULA) update.

- **RevenueCat Status:**
  - **Code:** User App (`src/app`) fully implemented.
  - **Dashboard:** Paywall design pending (User waiting on AI gen / DUNS/Merchant).
  - **Logic:** `UsageService` ready to accept limits based on entitlement.

- **Version Control:**
  - **Latest Commit:** `1ac939a` (Implement persistent video thumbnails...).
  - **Current Changes (v4+):** 
    - **User App:** Fixed "Join my intent" text -> "Join your intent".
    - **User App:** Improved Video Player to prioritize **Streaming** over downloading for non-cached files. This ensures immediate playback for short, strict-time events.
  - **Previous Major Versions:**
    - **v4:** Admin deployment updates and fixes (`80266f7`).
    - **v3:** Threaded Support Inbox, Quick Replies, Dashboard Fixes (`627d7cc`).
    - **v2:** Fix PDF shim and admin functionality (`28cd2b2`).
    - **v1:** Admin Dashboard & Monetization secure (`3054d37`).

- **Admin App (Edge/Web):**
  - **Media Library:** 
    - **NEW:** Persistent video thumbnails (JPEG generation on upload).
    - **NEW:** Improved file type detection for BMP/WBMP.
  - **Support Inbox:** Threaded support, Quick Replies (added in v3).
  - **Dashboard:** Fixes and improvements (v3).
  - **Deployment:** Updates and fixes (v4).
  - **Monetization Tab:** Includes VIP Security & Deal Editor (from v1).
  - **General:** Validated and running on Edge.

- **User App (Android):**
  - **General:** Validated and running on physical Samsung Android device.
  - **Note:** Maintain awareness of v4 deployment updates.

## Critical Handover Notes for Next AI
1.  **Git Status:** The repo is active on `main`. Be careful with changes as recent commits involve complex media handling.
2.  **File System Constraints:** This is a Windows environment.
    - **Do NOT** create deep nested build folders or "trash" folders like `src/app/build_trash_01`.
    - If `git add` fails with "Filename too long", check `.gitignore`.
3.  **App Structure:**
    - `src/admin`: Flutter Web project (Submodule).
    - `src/app`: Flutter Android/iOS project.
4.  **Architecture:**
    - **Admin:** Uses Repository pattern partially. MonetizationTab has self-contained logic for _checkVipAccess.
    - **User:** Uses Provider or Service locators.

## Recent Technical Changes
- **src/admin/lib/ui/tabs/media_library_tab.dart** (inferred): Likely updated for persistent video thumbnails and file type detection.
- **src/admin/lib/ui/tabs/support_tab.dart** (inferred): Likely updated for Threaded Support Inbox and Quick Replies.
- **src/admin/lib/ui/tabs/web_pdf_shim.dart**: Fixed in v2.

## Previous History (Jan 18, 2026)
- **v1 Locked:** Admin Dashboard & Monetization secure.
- **User App:** Logo Zoom implemented (Transform.scale).
- **Critical Warning:** Project may be in OneDrive (check path). If "changes not showing", run `flutter clean`.

## Instructions for Future AI Agents
1.  **Read this file first.**
2.  **Respect the Git History:** Build upon the v4+ changes.
3.  **Monetization Security:** The password logic is CLIENT-SIDE in the Admin app (monetization_tab.dart). It checks against Firestore documents.
