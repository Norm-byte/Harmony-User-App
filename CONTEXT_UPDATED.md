# Project Context & History

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
