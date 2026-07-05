const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();

async function assertSuperAdmin(context) {
    if (!context.auth || !context.auth.uid) {
        throw new functions.https.HttpsError('unauthenticated', 'You must be signed in.');
    }

    const callerDoc = await admin.firestore().collection('admin_users').doc(context.auth.uid).get();
    if (!callerDoc.exists) {
        throw new functions.https.HttpsError('permission-denied', 'Admin profile not found.');
    }

    const callerData = callerDoc.data() || {};
    if (callerData.role !== 'super-admin' || callerData.isActive !== true) {
        throw new functions.https.HttpsError('permission-denied', 'Only active super-admins can provision operators.');
    }

    return callerData;
}

exports.provisionAdminOperator = functions.https.onCall(async (data, context) => {
    const callerData = await assertSuperAdmin(context);

    const email = String(data.email || '').trim().toLowerCase();
    const displayName = String(data.displayName || '').trim();
    const initialPassword = String(data.initialPassword || '').trim();
    const permissions = Array.isArray(data.permissions)
        ? data.permissions.map((value) => String(value))
        : [];

    if (!email || !displayName || !initialPassword) {
        throw new functions.https.HttpsError('invalid-argument', 'Email, display name, and initial password are required.');
    }

    if (permissions.length === 0) {
        throw new functions.https.HttpsError('invalid-argument', 'At least one permission is required.');
    }

    let authUser;
    let existed = false;

    try {
        authUser = await admin.auth().getUserByEmail(email);
        existed = true;
        authUser = await admin.auth().updateUser(authUser.uid, {
            password: initialPassword,
            displayName,
        });
    } catch (error) {
        if (error.code === 'auth/user-not-found') {
            authUser = await admin.auth().createUser({
                email,
                password: initialPassword,
                displayName,
            });
        } else {
            throw error;
        }
    }

    const existingAdminDoc = await admin.firestore().collection('admin_users').doc(authUser.uid).get();
    const existingAdminData = existingAdminDoc.exists ? existingAdminDoc.data() || {} : {};
    if (existingAdminData.role === 'super-admin') {
        throw new functions.https.HttpsError('failed-precondition', 'That email already belongs to a super-admin account.');
    }

    const payload = {
        uid: authUser.uid,
        email,
        displayName,
        role: 'admin',
        isActive: true,
        permissions,
        invitedBy: callerData.email || context.auth.token.email || null,
        initialPassword,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    if (!existingAdminDoc.exists || !existingAdminData.createdAt) {
        payload.createdAt = admin.firestore.FieldValue.serverTimestamp();
    }

    await admin.firestore().collection('admin_users').doc(authUser.uid).set(payload, { merge: true });

    return {
        ok: true,
        existed,
        uid: authUser.uid,
        email,
    };
});

exports.sendPushNotification = functions.https.onCall(async (data, context) => {
    // Check authentication (optional but recommended)
    // if (!context.auth) {
    //     throw new functions.https.HttpsError('unauthenticated', 'The function must be called while authenticated.');
    // }

    const title = data.title;
    const body = data.body;
    const topic = data.topic || 'all_users';

    if (!title || !body) {
        throw new functions.https.HttpsError('invalid-argument', 'Title and Body are required.');
    }

    const message = {
        notification: {
            title: title,
            body: body,
        },
        topic: topic,
    };

    try {
        const response = await admin.messaging().send(message);
        return { success: true, message: `Successfully sent message: ${response}` };
    } catch (error) {
        console.error('Error sending message:', error);
        // Return the error details to the client for debugging
        return { 
            success: false, 
            message: `Error sending notification: ${error.message || error.code || error}` 
        };
    }
});

exports.aggregateTrendingIntent = functions.firestore
    .document('users/{userId}/registered_events/{registrationId}')
    .onCreate(async (snap, context) => {
        const newData = snap.data();
        const eventId = newData.eventId;
        const newIntent = newData.intent;

        if (!eventId) return null;

        // Determine collection based on event ID prefix or try both
        // Global events usually start with 'global_event_'
        const isGlobal = eventId.startsWith('global_event_');
        const collectionName = isGlobal ? 'global_events' : 'events';
        
        const eventRef = admin.firestore().collection(collectionName).doc(eventId);

        return admin.firestore().runTransaction(async (transaction) => {
            const eventDoc = await transaction.get(eventRef);
            if (!eventDoc.exists) {
                // Fallback: Check the other collection if not found (just in case)
                // This handles legacy or misnamed IDs
                return; 
            }

            const eventData = eventDoc.data();
            
            // 1. Increment Participant Count
            const currentCount = eventData.participantCount || 0;
            const updates = {
                participantCount: currentCount + 1
            };

            // 2. Handle Trending Intent (if configured)
            if (eventData.useTrendingIntent === true && newIntent) {
                const sanitizedIntent = newIntent.trim().toLowerCase();
                const statsRef = eventRef.collection('intent_stats').doc(sanitizedIntent);
                
                const statsDoc = await transaction.get(statsRef);
                let newIntentCount = 1;
                
                if (statsDoc.exists) {
                    newIntentCount = (statsDoc.data().count || 0) + 1;
                    transaction.update(statsRef, { count: newIntentCount });
                } else {
                    transaction.set(statsRef, { count: 1, intent: newIntent });
                }

                // Check for new champion
                const currentChampionCount = eventData.mostPopularIntentCount || 0;
                if (newIntentCount > currentChampionCount) {
                    updates.intent = newIntent;
                    updates.mostPopularIntent = newIntent;
                    updates.mostPopularIntentCount = newIntentCount;
                }
            }
            
            transaction.update(eventRef, updates);
        });
    });

function toUtcDayStart(date) {
    return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
}

function toUtcWeekMonday(date) {
    const dayStart = toUtcDayStart(date);
    const weekday = dayStart.getUTCDay(); // 0=Sun,1=Mon,...
    const daysSinceMonday = (weekday + 6) % 7;
    return new Date(dayStart.getTime() - daysSinceMonday * 24 * 60 * 60 * 1000);
}

function weekKey(date) {
    const y = date.getUTCFullYear();
    const m = String(date.getUTCMonth() + 1).padStart(2, '0');
    const d = String(date.getUTCDate()).padStart(2, '0');
    return `${y}-${m}-${d}`;
}

function addDays(date, days) {
    return new Date(date.getTime() + days * 24 * 60 * 60 * 1000);
}

function isDeterministicDraftSlot(docId) {
    return typeof docId === 'string' && docId.startsWith('draft_slot_');
}

function isDeterministicPublishedSlot(docId) {
    return typeof docId === 'string' && docId.startsWith('slot_');
}

exports.autoSystemWeeklyRollover = functions.pubsub
    .schedule('every 5 minutes')
    .timeZone('UTC')
    .onRun(async () => {
        const db = admin.firestore();
        const settingsRef = db.collection('system_settings').doc('auto_system');
        const settingsSnap = await settingsRef.get();
        const settings = settingsSnap.exists ? settingsSnap.data() || {} : {};

        if (settings.enabled !== true) {
            return null;
        }

        const now = new Date();
        const thisWeekStart = toUtcWeekMonday(now);
        const nextWeekStart = addDays(thisWeekStart, 7);
        const nextNextWeekStart = addDays(nextWeekStart, 7);

        const thisWeekKey = weekKey(thisWeekStart);
        const nextWeekKey = weekKey(nextWeekStart);

        // Fetch next-week slot docs (both draft and published) once; both operations use these.
        const nextWeekSnapshot = await db
            .collection('events')
            .where('startTimeUTC', '>=', nextWeekStart.toISOString())
            .where('startTimeUTC', '<', nextNextWeekStart.toISOString())
            .get();

        const nextWeekDraftDocs = [];
        let hasNextWeekPublishedSlots = false;

        nextWeekSnapshot.forEach((doc) => {
            const data = doc.data() || {};
            const docId = doc.id;
            if (isDeterministicDraftSlot(docId) && data.isDraft === true) {
                nextWeekDraftDocs.push({ id: docId, data });
            }
            if (
                isDeterministicPublishedSlot(docId) &&
                data.isPublished === true &&
                data.isDraft !== true
            ) {
                hasNextWeekPublishedSlots = true;
            }
        });

        // Stage 1: Pre-publish next week when we enter the show-before window
        // for the first 00:00 slot (defaulting to 60 minutes).
        if (!hasNextWeekPublishedSlots && nextWeekDraftDocs.length > 0) {
            const maxShowBeforeMinutes = nextWeekDraftDocs.reduce((max, entry) => {
                const value = Number(entry.data.noticeBoardShowBeforeMinutes);
                if (Number.isFinite(value) && value > max) return value;
                return max;
            }, 60);

            const prePublishAt = new Date(
                nextWeekStart.getTime() - Math.max(0, maxShowBeforeMinutes) * 60 * 1000,
            );

            if (
                now >= prePublishAt &&
                settings.lastPrepublishWeekKey !== nextWeekKey
            ) {
                const batch = db.batch();

                for (const entry of nextWeekDraftDocs) {
                    const publishedId = entry.id.replace('draft_slot_', 'slot_');
                    const publishedRef = db.collection('events').doc(publishedId);
                    const draftRef = db.collection('events').doc(entry.id);

                    const nextData = {
                        ...entry.data,
                        id: publishedId,
                        isPublished: true,
                        isDraft: false,
                        updatedAt: new Date().toISOString(),
                    };

                    batch.set(publishedRef, nextData, { merge: true });
                    batch.delete(draftRef);
                }

                batch.set(
                    settingsRef,
                    {
                        lastPrepublishWeekKey: nextWeekKey,
                        lastPrepublishAt: admin.firestore.FieldValue.serverTimestamp(),
                    },
                    { merge: true },
                );

                await batch.commit();
            }
        }

        // Stage 2: Cleanup prior week published slot docs only after a safety buffer.
        // Buffer avoids clipping late Sunday slot playback windows.
        const cleanupBufferHours = 3;
        const cleanupAfter = new Date(
            thisWeekStart.getTime() + cleanupBufferHours * 60 * 60 * 1000,
        );

        if (
            now >= cleanupAfter &&
            settings.lastCleanupWeekKey !== thisWeekKey
        ) {
            const previousWeekStart = addDays(thisWeekStart, -7);
            const previousWeekSnapshot = await db
                .collection('events')
                .where('startTimeUTC', '>=', previousWeekStart.toISOString())
                .where('startTimeUTC', '<', thisWeekStart.toISOString())
                .get();

            const batch = db.batch();
            let deleteCount = 0;

            previousWeekSnapshot.forEach((doc) => {
                const data = doc.data() || {};
                if (
                    isDeterministicPublishedSlot(doc.id) &&
                    data.isPublished === true
                ) {
                    batch.delete(doc.ref);
                    deleteCount++;
                }
            });

            batch.set(
                settingsRef,
                {
                    lastCleanupWeekKey: thisWeekKey,
                    lastCleanupAt: admin.firestore.FieldValue.serverTimestamp(),
                    lastCleanupDeletedCount: deleteCount,
                },
                { merge: true },
            );

            await batch.commit();
        }

        return null;
    });
