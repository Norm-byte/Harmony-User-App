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
