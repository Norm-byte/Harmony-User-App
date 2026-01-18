# Harmony by Intent

This is the project folder for "Harmony by Intent". Drop your simpler version here and I will implement it inside this workspace.

Structure created:
- src/ (code files)
- assets/ (images, static files)
- README.md (this file)
- .gitignore (common ignores)

Next steps:
- Upload your simpler version into this folder (you can drag & drop into the Explorer).
- Tell me which file is the app entry point and I will start implementing and wiring files.
Project Directive: Worldwide Healing Event Application

AI Instruction: Start with Admin App

Your primary task is to write the complete, integrated Flutter/Dart codebase for this project, utilizing Firebase for the backend and Gemini for AI services. Begin development strictly with the Admin Web Application, followed by the User Mobile Application, and finally, the necessary Firebase Cloud Functions.

1. Overall Application Purpose

The application's purpose is to facilitate synchronized, worldwide healing and positive intent events. The app must feel professional, harmonious, and symmetrical, adhering to a Tartarian aesthetic (Deep Blues, Muted Golds/Brass, Terracotta). It must manage user access via IAP and a strict trial gate, and provide both a secure administration platform and a seamless, real-time mobile experience.

2. Technology Stack & Data Context

Frontends: Flutter for both the User (Mobile) and Admin (Web) Applications.

Backend: Firebase (Firestore, Auth, Storage, FCM) for all data and real-time synchronization.

AI: Gemini 2.0 must be used for Content Moderation, Intent Analysis, and generating automated Post-Event Analysis drafts.

Synchronization: Events must start simultaneously worldwide, relying on NTP Time synchronization (U-07.2) against the server's startTimeUTC.

3. Development Priority 1: Admin Web Application

The Admin App must be built first to manage all content and event scheduling.

Content & Event Management (A-10, A-11)

Central Workspace: The Admin App must use a unified screen with three linked sections: Event Upload, Content Editors, and an Integrated Preview.

Reusable Event Index (A-15): The Admin must be able to save full event cards (Title, Sound URL, Visual URL, Intent Description) and load them for reuse in future events.

Scheduling: The Admin sets the Reference Location/Time, which the system converts to a definitive startTimeUTC for worldwide synchronization.

Content Editors: Must support Rich Text editing and allow the Admin to upload media files to Firebase Storage or embed scalable video content via YouTube URL (A-13).

Integrated Preview (A-14): A mandatory panel that displays content exactly as the user will see it (including the three-card layout and persistent comment area) before publishing.

Post-Event Commentary Automation (A-04.2)

The system requires a QuoteLibrary (Firestore Collection) for storing positive, pre-written statements.

The Post-Event Finalization Tool requires the Admin to select the adminAnalysisText from three options: Manual Input, Repository Selection (from QuoteLibrary), or AI-Generated Draft (using Gemini to summarize the event's raw Intent Data).

System Automation & Reporting (A-50, A-40)

Automated Scheduler (A-50): A console to define recurring event time slots (e.g., Daily 14:00 UTC). The system must use a random selection from the Reusable Event Index for automated events.

Dashboard (A-40): Display Worldwide User Growth and Popular Intent Distribution graphs for site health monitoring.

User Management (A-20): Tools to view user profiles, Delete Comments, and Suspend User access.

Legal Docs Mgmt (A-30): Tool to upload and set the Active Version of the Terms & Conditions, which gates subscription access in the User App.

4. Development Priority 2: User Mobile Application

The User App provides the live experience, strictly gating functionality based on subscription status.

Access Control and Trial Gating (U-17, U-18.1)

Trial users have FULL READ ACCESS to all content and the live comment feed.

Trial users are RESTRICTED from Submitting Comments and joining the event ("Join In" tracking).

The trial is strictly limited to 2 events (eventsConsumedCount). A clear Limit Gating Message (U-20) must appear when the limit is reached.

Full access requires a successful IAP payment AND acceptance of the Active T&C (U-30).

Core Event Experience (U-07)

Worldwide Synchronization (U-07.2): Critical. The app must use NTP to ensure the 60-second event starts precisely at the server's startTimeUTC.

Live Stats Overlay (U-07.6): Display real-time Worldwide User Count and Worldwide Intent Score using a floating, semi-transparent overlay.

Comment Transparency (U-07.9): The fixed, persistent comment section at the bottom of the screen must transition to higher transparency during the 60-second event to minimize distraction.

Intent Submission: Tapping "Join In" (U-09.2) must trigger a prompt that pre-populates the comment box with: @Username - Intent for [Event Title]: to ensure a focused intent statement.

Data & Display

Post-Events Page (U-16): Displays completed events with a detailed view showing the Event Intent Breakdown Graph (symmetrical radial chart) and the Admin Written Analysis (U-16.6).

My Page (U-14): Displays personalized stats alongside Worldwide User Growth and Popular Intent Distribution graphs.

5. Development Priority 3: Backend & AI Functions

Gemini-01 Intent Analysis: A Firestore Trigger Cloud Function must analyze every new comment (post-moderation) to assign a sentiment/intent category (e.g., "Harmony," "Growth").

Gemini-04 Content Moderation: All submitted comments must pass a Gemini moderation check before being written to the database and displayed to users.

Subscription Webhooks (B-11): Cloud Functions must be configured to securely receive and process Server-to-Server notifications from Apple/Google to manage the user's subscriptionStatus reliably.

The final application must use generous padding, subtle shadows, and light gradients to achieve a professional, balanced, and calm user experience across all platforms.
