const functions = require('firebase-functions');
const admin = require('firebase-admin');
const vision = require('@google-cloud/vision');
const nodemailer = require('nodemailer');
const { onObjectFinalized } = require('firebase-functions/v2/storage');
admin.initializeApp();
const visionClient = new vision.ImageAnnotatorClient();

const SAFE_SEARCH_LEVEL_RANK = {
    UNKNOWN: 0,
    VERY_UNLIKELY: 1,
    UNLIKELY: 2,
    POSSIBLE: 3,
    LIKELY: 4,
    VERY_LIKELY: 5,
};

function normalizeLikelihood(value, fallback) {
    const normalized = String(value || '').trim().toUpperCase();
    if (!normalized) return fallback;
    if (normalized === 'DISABLED') return 'DISABLED';
    return Object.prototype.hasOwnProperty.call(SAFE_SEARCH_LEVEL_RANK, normalized)
        ? normalized
        : fallback;
}

function isAtOrAboveLikelihood(actual, threshold) {
    if (threshold === 'DISABLED') return false;
    const actualRank = SAFE_SEARCH_LEVEL_RANK[actual] || 0;
    const thresholdRank = SAFE_SEARCH_LEVEL_RANK[threshold] || 99;
    return actualRank >= thresholdRank;
}

async function loadModerationPolicy() {
    const defaults = {
        adultThreshold: 'VERY_LIKELY',
        violenceThreshold: 'VERY_LIKELY',
        racyThreshold: 'DISABLED',
        requireAdultNotVeryUnlikelyForViolence: true,
    };

    try {
        const doc = await admin.firestore().collection('system_settings').doc('moderation_policy').get();
        const data = doc.exists ? (doc.data() || {}) : {};
        return {
            adultThreshold: normalizeLikelihood(data.adultThreshold, defaults.adultThreshold),
            violenceThreshold: normalizeLikelihood(data.violenceThreshold, defaults.violenceThreshold),
            racyThreshold: normalizeLikelihood(data.racyThreshold, defaults.racyThreshold),
            requireAdultNotVeryUnlikelyForViolence:
                data.requireAdultNotVeryUnlikelyForViolence !== false,
        };
    } catch (error) {
        console.error('MODERATION_POLICY_LOAD_ERROR', error?.message || error);
        return defaults;
    }
}


function logCommunityNotification(event, payload) {
    console.log(`[community_notify] ${event}`, payload || {});
}

function isNotRegisteredMessagingError(error) {
    return String(error?.errorInfo?.code || '').trim() === 'messaging/registration-token-not-registered';
}

function messagingErrorDetails(error) {
    return {
        code: String(error?.errorInfo?.code || error?.code || '').trim() || 'unknown',
        message: String(error?.errorInfo?.message || error?.message || '').trim() || 'unknown',
    };
}

function collectOwnerTokens(ownerData) {
    const tokenSet = new Set();

    const single = String(ownerData?.fcmToken || '').trim();
    if (single) {
        tokenSet.add(single);
    }

    const multi = Array.isArray(ownerData?.fcmTokens) ? ownerData.fcmTokens : [];
    for (const item of multi) {
        const token = String(item || '').trim();
        if (token) {
            tokenSet.add(token);
        }
    }

    return Array.from(tokenSet);
}

async function pruneInvalidOwnerTokens({ ownerUid, invalidTokens }) {
    const uid = String(ownerUid || '').trim();
    if (!uid || !Array.isArray(invalidTokens) || invalidTokens.length === 0) {
        return;
    }

    const normalized = invalidTokens
        .map((token) => String(token || '').trim())
        .filter(Boolean);
    if (normalized.length === 0) {
        return;
    }

    try {
        const userRef = admin.firestore().collection('users').doc(uid);
        const userSnap = await userRef.get();
        const currentSingle = String(userSnap.data()?.fcmToken || '').trim();

        const payload = {
            fcmTokens: admin.firestore.FieldValue.arrayRemove(...normalized),
            fcmTokenInvalidatedAt: admin.firestore.FieldValue.serverTimestamp(),
        };

        if (currentSingle && normalized.includes(currentSingle)) {
            payload.fcmToken = admin.firestore.FieldValue.delete();
        }

        await userRef.set(payload, { merge: true });
    } catch (cleanupError) {
        console.error('Error pruning invalid FCM tokens:', cleanupError);
    }
}

async function sendCommunityNotificationToOwner({ ownerUid, ownerData, message, context }) {
    const tokens = collectOwnerTokens(ownerData);
    const configuredTopic = String(ownerData?.notificationTopic || '').trim();
    const userTopic = configuredTopic || `user_${ownerUid}`;

    if (tokens.length === 0) {
        const topicMessage = {
            ...message,
            topic: userTopic,
        };

        await admin.messaging().send(topicMessage);
        return { mode: 'topic', count: 0, topic: topicMessage.topic };
    }

    if (tokens.length === 1) {
        const tokenMessage = {
            ...message,
            token: tokens[0],
        };

        try {
            await admin.messaging().send(tokenMessage);
            return { mode: 'token', count: 1, total: 1 };
        } catch (error) {
            const topicMessage = {
                ...message,
                topic: userTopic,
            };

            if (isNotRegisteredMessagingError(error)) {
                await pruneInvalidOwnerTokens({ ownerUid, invalidTokens: [tokens[0]] });

                const topicMessageId = await admin.messaging().send(topicMessage);
                return {
                    mode: 'topic_after_token_invalid',
                    count: 0,
                    topic: topicMessage.topic,
                    total: 1,
                    tokenError: messagingErrorDetails(error),
                    topicMessageId,
                };
            }

            try {
                const topicMessageId = await admin.messaging().send(topicMessage);
                return {
                    mode: 'topic_after_token_error',
                    count: 0,
                    topic: topicMessage.topic,
                    total: 1,
                    tokenError: messagingErrorDetails(error),
                    topicMessageId,
                };
            } catch (topicError) {
                if (isNotRegisteredMessagingError(topicError)) {
                    await pruneInvalidOwnerTokens({ ownerUid, invalidTokens: [tokens[0]] });
                }
                const wrapped = new Error('Token send failed and topic fallback failed');
                wrapped.details = {
                    tokenError: messagingErrorDetails(error),
                    topicError: messagingErrorDetails(topicError),
                    ownerUid,
                    tokenTotal: tokens.length,
                    topic: topicMessage.topic,
                    context,
                };
                throw wrapped;
            }
        }
    }

    const multicastMessage = {
        ...message,
        tokens,
    };

    const response = await admin.messaging().sendEachForMulticast(multicastMessage);
    const invalidTokens = [];
    response.responses.forEach((result, index) => {
        if (!result.success && isNotRegisteredMessagingError(result.error)) {
            invalidTokens.push(tokens[index]);
        }
    });

    if (invalidTokens.length > 0) {
        await pruneInvalidOwnerTokens({ ownerUid, invalidTokens });
    }

    if (response.successCount === 0) {
        const topicMessage = {
            ...message,
            topic: userTopic,
        };
        await admin.messaging().send(topicMessage);
        return {
            mode: 'topic_after_multicast_zero_success',
            count: 0,
            topic: topicMessage.topic,
            invalidTokens: invalidTokens.length,
        };
    }

    return {
        mode: 'multicast',
        count: response.successCount,
        total: tokens.length,
        invalidTokens: invalidTokens.length,
    };
}

async function clearInvalidFcmTokenIfNeeded({ error, ownerUid, context }) {
    const code = String(error?.errorInfo?.code || '').trim();
    if (code !== 'messaging/registration-token-not-registered') {
        return;
    }

    const uid = String(ownerUid || '').trim();
    if (!uid) {
        return;
    }

    try {
        await admin.firestore().collection('users').doc(uid).set(
            {
                fcmToken: admin.firestore.FieldValue.delete(),
                fcmTokenInvalidatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            { merge: true },
        );
        logCommunityNotification('fcm_token_cleared_not_registered', {
            ownerUid: uid,
            ...context,
        });
    } catch (cleanupError) {
        console.error('Error clearing invalid FCM token:', cleanupError);
    }
}

function parseModeratedPath(objectName) {
    const normalized = String(objectName || '').trim();
    if (!normalized) return { supported: false, type: 'unknown' };

    const roomPrefix = 'chat_room_media/community_room/';
    if (normalized.startsWith(roomPrefix)) {
        const rest = normalized.slice(roomPrefix.length);
        const parts = rest.split('/').filter(Boolean);
        if (parts.length >= 2) {
            const uid = parts[0];
            const imageFile = parts.slice(1).join('/');
            return {
                supported: true,
                type: 'common_room',
                uid,
                imageFile,
            };
        }
    }

    const vaultPrefix = 'user_vault_media/';
    if (normalized.startsWith(vaultPrefix)) {
        const rest = normalized.slice(vaultPrefix.length);
        const parts = rest.split('/').filter(Boolean);
        if (parts.length >= 2) {
            const uid = parts[0];
            const fileName = parts.slice(1).join('/');
            const imageId = fileName.toLowerCase().endsWith('.jpg')
                ? fileName.slice(0, -4)
                : fileName;
            return {
                supported: true,
                type: 'vault',
                uid,
                imageFile: fileName,
                imageId,
            };
        }
    }

    return { supported: false, type: 'unknown' };
}

async function logModerationEvent(payload) {
    const { status, ...rest } = payload || {};
    await admin.firestore().collection('moderation_queue').add({
        ...rest,
        source: 'safe_search_storage_finalize',
        status: status || 'pending',
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });
}

async function clearCommonRoomImageRefs(storagePath) {
    const db = admin.firestore();
    const postsSnap = await db
        .collection('community_posts')
        .where('imageStoragePath', '==', storagePath)
        .limit(50)
        .get();

    if (postsSnap.empty) {
        return 0;
    }

    const batch = db.batch();
    postsSnap.docs.forEach((doc) => {
        batch.set(
            doc.ref,
            {
                hasImage: false,
                imageUrl: null,
                imageStatus: 'moderated_deleted',
                isModerated: true,
                moderatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            { merge: true },
        );
    });
    await batch.commit();
    return postsSnap.size;
}

async function clearVaultImageRef(uid, imageId) {
    if (!uid || !imageId) return false;
    const vaultRef = admin
        .firestore()
        .collection('users')
        .doc(uid)
        .collection('vault_images')
        .doc(imageId);

    await vaultRef.set(
        {
            status: 'moderated_deleted',
            isModerated: true,
            downloadUrl: null,
            moderatedAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
    );
    return true;
}

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

async function assertAdminPermission(context, permission, purpose) {
    if (!context.auth || !context.auth.uid) {
        throw new functions.https.HttpsError('unauthenticated', 'You must be signed in.');
    }

    const callerDoc = await admin.firestore().collection('admin_users').doc(context.auth.uid).get();
    if (!callerDoc.exists) {
        throw new functions.https.HttpsError('permission-denied', 'Admin profile not found.');
    }

    const callerData = callerDoc.data() || {};
    if (callerData.isActive !== true) {
        throw new functions.https.HttpsError('permission-denied', 'Only active operators can perform this action.');
    }

    if (callerData.role === 'super-admin') {
        return callerData;
    }

    const permissions = Array.isArray(callerData.permissions)
        ? callerData.permissions.map((value) => String(value))
        : [];

    if (!permissions.includes(permission)) {
        throw new functions.https.HttpsError('permission-denied', `You do not have permission to ${purpose}.`);
    }

    return callerData;
}

function alertNotificationConfigRef() {
    return admin.firestore().collection('admin_alert_settings').doc('notifications');
}

function normalizedAlertRecipients(rawRecipients) {
    if (!Array.isArray(rawRecipients)) return [];
    return [...new Set(rawRecipients
        .map((value) => String(value || '').trim().toLowerCase())
        .filter((email) => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)))];
}

exports.saveAlertNotificationSettings = functions.https.onCall(async (data, context) => {
    await assertAdminPermission(context, 'alert_notifications', 'manage alert notifications');

    const enabled = data.enabled === true;
    const recipients = normalizedAlertRecipients(data.recipients);
    if (enabled && recipients.length === 0) {
        throw new functions.https.HttpsError('invalid-argument', 'Add at least one recipient before enabling alert notifications.');
    }

    await alertNotificationConfigRef().set({
        enabled,
        recipients,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedBy: context.auth.uid,
    }, { merge: true });
    return { ok: true, enabled, recipients };
});

async function sendAlertNotification({ subject, text }) {
    const configSnap = await alertNotificationConfigRef().get();
    const config = configSnap.exists ? (configSnap.data() || {}) : {};
    const recipients = normalizedAlertRecipients(config.recipients);
    const smtpPassword = String(process.env.IONOS_SMTP_PASSWORD || '').trim();
    if (config.enabled !== true || recipients.length === 0 || !smtpPassword) return null;

    const transporter = nodemailer.createTransport({
        host: 'smtp.ionos.co.uk',
        port: 587,
        secure: false,
        auth: { user: 'admin@auralogical.com', pass: smtpPassword },
    });

    await transporter.sendMail({
        from: 'Harmony by Intent Alerts <admin@auralogical.com>',
        to: recipients.join(','),
        replyTo: 'admin@auralogical.com',
        subject,
        text,
    });
    return null;
}

exports.notifyAdminsOnModerationAlert = functions.runWith({ secrets: ['IONOS_SMTP_PASSWORD'] }).firestore
    .document('moderation_queue/{reportId}')
    .onCreate(async (snap) => {
        const report = snap.data() || {};
        if (String(report.status || '').toLowerCase() !== 'pending') return null;
        if (String(report.type || '').toLowerCase() === 'safe_search_passed') return null;

        const reason = String(report.reason || 'Not specified').trim();
        const context = String(report.context || report.source || 'User report').trim();
        const reporter = String(report.reporterName || report.userName || 'Unknown user').trim();
        const explanation = String(report.reportExplanation || '').trim();
        return sendAlertNotification({
            subject: `Harmony alert: ${context}`,
            text: `A new moderation alert is waiting.\n\nReporter: ${reporter}\nReason: ${reason}\nExplanation: ${explanation || 'Not provided'}\n\nOpen the Harmony Admin dashboard to review it.`,
        });
    });

exports.notifyAdminsOnSupportAlert = functions.runWith({ secrets: ['IONOS_SMTP_PASSWORD'] }).firestore
    .document('support_inbox/{messageId}')
    .onCreate(async (snap) => {
        const message = snap.data() || {};
        if (message.read === true) return null;
        const sender = String(message.userName || message.name || 'User').trim();
        const content = String(message.content || message.message || message.text || '').trim();
        return sendAlertNotification({
            subject: 'Harmony alert: new support message',
            text: `A new support message is waiting.\n\nFrom: ${sender}\nMessage: ${content || 'Open the Harmony Admin dashboard to review it.'}`,
        });
    });

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

exports.provisionAppUserAccount = functions.https.onCall(async (data, context) => {
    const callerData = await assertAdminPermission(context, 'app_accounts', 'manage app accounts');

    const email = String(data.email || '').trim().toLowerCase();
    const initialPassword = String(data.initialPassword || '').trim();
    const fullName = String(data.fullName || '').trim();
    const username = String(data.username || '').trim();
    const usernameLower = username.toLowerCase();
    const isVip = data.isVip === true;
    const vipQuotaTier = String(data.vipQuotaTier || 'tier_beta').trim() || 'tier_beta';

    if (!email || !initialPassword || !username) {
        throw new functions.https.HttpsError('invalid-argument', 'Email, password, and username are required.');
    }

    if (!usernameLower || usernameLower === 'guest' || usernameLower === 'member') {
        throw new functions.https.HttpsError('invalid-argument', 'Please choose a valid username.');
    }

    let authUser;
    let existed = false;

    try {
        authUser = await admin.auth().getUserByEmail(email);
        existed = true;

        const existingAdminDoc = await admin.firestore().collection('admin_users').doc(authUser.uid).get();
        if (existingAdminDoc.exists) {
            throw new functions.https.HttpsError(
                'failed-precondition',
                'This email belongs to an admin/operator account and cannot be provisioned as an app user. Use a separate email for app-user testing.',
            );
        }

        authUser = await admin.auth().updateUser(authUser.uid, {
            password: initialPassword,
            displayName: username,
        });
    } catch (error) {
        if (error.code === 'auth/user-not-found') {
            authUser = await admin.auth().createUser({
                email,
                password: initialPassword,
                displayName: username,
            });
        } else {
            throw error;
        }
    }

    const db = admin.firestore();
    const userRef = db.collection('users').doc(authUser.uid);
    const usernameRef = db.collection('usernames').doc(usernameLower);

    await db.runTransaction(async (tx) => {
        const [userSnap, usernameSnap] = await Promise.all([
            tx.get(userRef),
            tx.get(usernameRef),
        ]);

        if (usernameSnap.exists) {
            const usernameData = usernameSnap.data() || {};
            const ownerUid = String(usernameData.ownerUid || '').trim();
            if (ownerUid && ownerUid !== authUser.uid) {
                throw new functions.https.HttpsError('already-exists', 'That username is already claimed.');
            }
        }

        const userData = userSnap.exists ? (userSnap.data() || {}) : {};
        const previousUsernameLower = String(
            userData.usernameLower || userData.username || userData.userName || userData.displayName || userData.name || '',
        ).trim().toLowerCase();

        if (previousUsernameLower && previousUsernameLower !== usernameLower) {
            const previousUsernameRef = db.collection('usernames').doc(previousUsernameLower);
            const previousUsernameSnap = await tx.get(previousUsernameRef);
            if (previousUsernameSnap.exists) {
                const previousOwnerUid = String(previousUsernameSnap.data()?.ownerUid || '').trim();
                if (previousOwnerUid === authUser.uid) {
                    tx.delete(previousUsernameRef);
                }
            }
        }

        tx.set(usernameRef, {
            username,
            usernameLower,
            ownerUid: authUser.uid,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            createdAt: usernameSnap.exists
                ? (usernameSnap.data()?.createdAt || admin.firestore.FieldValue.serverTimestamp())
                : admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });

        const userPayload = {
            email,
            fullName,
            username,
            usernameLower,
            userName: username,
            displayName: username,
            name: username,
            isVip,
            vipQuotaTier: isVip ? vipQuotaTier : null,
            status: isVip ? 'active' : (String(userData.status || '').trim() || 'trial'),
            invitedBy: callerData.email || context.auth.token.email || null,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        };

        if (!userSnap.exists) {
            userPayload.createdAt = admin.firestore.FieldValue.serverTimestamp();
            userPayload.joinDate = admin.firestore.FieldValue.serverTimestamp();
        }

        tx.set(userRef, userPayload, { merge: true });
    });

    return {
        ok: true,
        existed,
        uid: authUser.uid,
        email,
        username,
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
        android: {
            priority: 'high',
            notification: {
                channelId: 'high_importance_channel',
                sound: 'default',
            },
        },
        apns: {
            headers: {
                'apns-priority': '10',
                'apns-push-type': 'alert',
            },
            payload: {
                aps: {
                    alert: {
                        title,
                        body,
                    },
                    sound: 'default',
                },
            },
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

exports.notifyOnCommunityPostLike = functions.firestore
    .document('community_posts/{postId}')
    .onUpdate(async (change, context) => {
        const before = change.before.data() || {};
        const after = change.after.data() || {};

        const beforeLikedBy = Array.isArray(before.likedBy) ? before.likedBy : [];
        const afterLikedBy = Array.isArray(after.likedBy) ? after.likedBy : [];

        if (afterLikedBy.length <= beforeLikedBy.length) {
            logCommunityNotification('post_like_skipped_not_added', { postId: context.params.postId });
            return null;
        }

        const newlyAddedLikerUid = afterLikedBy.find((uid) => !beforeLikedBy.includes(uid));
        if (!newlyAddedLikerUid) {
            logCommunityNotification('post_like_skipped_no_new_uid', { postId: context.params.postId });
            return null;
        }

        const ownerUid = String(after.authorUid || after.userId || after.uid || '').trim();
        if (!ownerUid || ownerUid === newlyAddedLikerUid) {
            logCommunityNotification('post_like_skipped_owner_invalid_or_self', {
                postId: context.params.postId,
                ownerUid,
                likerUid: newlyAddedLikerUid,
            });
            return null;
        }

        const ownerDoc = await admin.firestore().collection('users').doc(ownerUid).get();
        if (!ownerDoc.exists) {
            logCommunityNotification('post_like_skipped_owner_missing', { postId: context.params.postId, ownerUid });
            return null;
        }

        const ownerData = ownerDoc.data() || {};
        if (ownerData.notifyOnCommentLikes === false) {
            logCommunityNotification('post_like_skipped_opt_out', { postId: context.params.postId, ownerUid });
            return null;
        }

        const likerDoc = await admin.firestore().collection('users').doc(newlyAddedLikerUid).get();
        const likerData = likerDoc.exists ? likerDoc.data() || {} : {};
        const likerName = String(likerData.name || likerData.username || 'Someone').trim() || 'Someone';

        const message = {
            notification: {
                title: 'Your post got a like',
                body: `${likerName} liked your post in Community.`,
            },
            data: {
                type: 'community_post_like',
                postId: context.params.postId,
                likerUid: String(newlyAddedLikerUid),
            },
            android: {
                priority: 'high',
                notification: {
                    channelId: 'high_importance_channel',
                    sound: 'default',
                },
            },
            apns: {
                headers: {
                    'apns-priority': '10',
                    'apns-push-type': 'alert',
                },
                payload: {
                    aps: {
                        alert: {
                            title: 'Your post got a like',
                            body: `${likerName} liked your post in Community.`,
                        },
                        sound: 'default',
                    },
                },
            },
        };

        try {
            const delivery = await sendCommunityNotificationToOwner({
                ownerUid,
                ownerData,
                message,
                context: {
                    trigger: 'notifyOnCommunityPostLike',
                    postId: context.params.postId,
                },
            });

            logCommunityNotification('post_like_sent', {
                postId: context.params.postId,
                ownerUid,
                likerUid: newlyAddedLikerUid,
                mode: delivery.mode,
                successCount: delivery.count,
                tokenTotal: delivery.total || undefined,
                tokenErrorCode: delivery.tokenError?.code,
                tokenErrorMessage: delivery.tokenError?.message,
                topicMessageId: delivery.topicMessageId,
            });
            return null;
        } catch (error) {
            console.error('Error sending community like notification:', error);
            await clearInvalidFcmTokenIfNeeded({
                error,
                ownerUid,
                context: {
                    trigger: 'notifyOnCommunityPostLike',
                    postId: context.params.postId,
                },
            });
            return null;
        }
    });

exports.notifyOnCommunityReply = functions.firestore
    .document('community_posts/{postId}/replies/{replyId}')
    .onCreate(async (snap, context) => {
        const reply = snap.data() || {};
        const postId = String(context.params.postId || '').trim();
        if (!postId) {
            logCommunityNotification('reply_create_skipped_no_post_id', { replyId: context.params.replyId });
            return null;
        }

        const postDoc = await admin.firestore().collection('community_posts').doc(postId).get();
        if (!postDoc.exists) {
            logCommunityNotification('reply_create_skipped_post_missing', { postId });
            return null;
        }

        const postData = postDoc.data() || {};
        const ownerUid = String(postData.authorUid || postData.userId || postData.uid || '').trim();
        const replierUid = String(reply.authorUid || reply.userId || reply.uid || '').trim();

        if (!ownerUid || !replierUid || ownerUid === replierUid) {
            logCommunityNotification('reply_create_skipped_owner_invalid_or_self', {
                postId,
                replyId: context.params.replyId,
                ownerUid,
                replierUid,
            });
            return null;
        }

        const ownerDoc = await admin.firestore().collection('users').doc(ownerUid).get();
        if (!ownerDoc.exists) {
            logCommunityNotification('reply_create_skipped_owner_missing', { postId, ownerUid });
            return null;
        }

        const ownerData = ownerDoc.data() || {};
        if (ownerData.notifyOnCommentLikes === false) {
            logCommunityNotification('reply_create_skipped_opt_out', { postId, ownerUid });
            return null;
        }

        const replierDoc = await admin.firestore().collection('users').doc(replierUid).get();
        const replierData = replierDoc.exists ? replierDoc.data() || {} : {};
        const replierName = String(replierData.name || replierData.username || reply.userName || 'Someone').trim() || 'Someone';
        const replyContent = String(reply.content || reply.text || '').trim();
        const preview = replyContent.length > 80 ? `${replyContent.slice(0, 77)}...` : replyContent;

        const message = {
            notification: {
                title: 'New reply to your comment',
                body: preview ? `${replierName} replied: ${preview}` : `${replierName} replied to your comment in Community.`,
            },
            data: {
                type: 'community_comment_reply',
                postId,
                replyId: String(context.params.replyId || ''),
                replierUid,
            },
            android: {
                priority: 'high',
                notification: {
                    channelId: 'high_importance_channel',
                    sound: 'default',
                },
            },
            apns: {
                headers: {
                    'apns-priority': '10',
                    'apns-push-type': 'alert',
                },
                payload: {
                    aps: {
                        alert: {
                            title: 'New reply on your post',
                            body: `${replierName} replied to your post in Community.`,
                        },
                        sound: 'default',
                    },
                },
            },
        };

        try {
            const delivery = await sendCommunityNotificationToOwner({
                ownerUid,
                ownerData,
                message,
                context: {
                    trigger: 'notifyOnCommunityReply',
                    postId,
                    replyId: String(context.params.replyId || ''),
                },
            });

            logCommunityNotification('reply_create_sent', {
                postId,
                replyId: context.params.replyId,
                ownerUid,
                replierUid,
                mode: delivery.mode,
                successCount: delivery.count,
                tokenTotal: delivery.total || undefined,
                tokenErrorCode: delivery.tokenError?.code,
                tokenErrorMessage: delivery.tokenError?.message,
                topicMessageId: delivery.topicMessageId,
            });
            return null;
        } catch (error) {
            console.error('Error sending community reply notification:', error);
            await clearInvalidFcmTokenIfNeeded({
                error,
                ownerUid,
                context: {
                    trigger: 'notifyOnCommunityReply',
                    postId,
                    replyId: String(context.params.replyId || ''),
                },
            });
            return null;
        }
    });

exports.notifyOnCommunityReplyLike = functions.firestore
    .document('community_posts/{postId}/replies/{replyId}')
    .onUpdate(async (change, context) => {
        const before = change.before.data() || {};
        const after = change.after.data() || {};

        const beforeLikedBy = Array.isArray(before.likedBy) ? before.likedBy : [];
        const afterLikedBy = Array.isArray(after.likedBy) ? after.likedBy : [];

        if (afterLikedBy.length <= beforeLikedBy.length) {
            logCommunityNotification('reply_like_skipped_not_added', {
                postId: context.params.postId,
                replyId: context.params.replyId,
            });
            return null;
        }

        const newlyAddedLikerUid = afterLikedBy.find((uid) => !beforeLikedBy.includes(uid));
        if (!newlyAddedLikerUid) {
            logCommunityNotification('reply_like_skipped_no_new_uid', {
                postId: context.params.postId,
                replyId: context.params.replyId,
            });
            return null;
        }

        const ownerUid = String(after.authorUid || after.userId || after.uid || '').trim();
        if (!ownerUid || ownerUid === newlyAddedLikerUid) {
            logCommunityNotification('reply_like_skipped_owner_invalid_or_self', {
                postId: context.params.postId,
                replyId: context.params.replyId,
                ownerUid,
                likerUid: newlyAddedLikerUid,
            });
            return null;
        }

        const ownerDoc = await admin.firestore().collection('users').doc(ownerUid).get();
        if (!ownerDoc.exists) {
            logCommunityNotification('reply_like_skipped_owner_missing', {
                postId: context.params.postId,
                replyId: context.params.replyId,
                ownerUid,
            });
            return null;
        }

        const ownerData = ownerDoc.data() || {};
        if (ownerData.notifyOnCommentLikes === false) {
            logCommunityNotification('reply_like_skipped_opt_out', {
                postId: context.params.postId,
                replyId: context.params.replyId,
                ownerUid,
            });
            return null;
        }

        const likerDoc = await admin.firestore().collection('users').doc(newlyAddedLikerUid).get();
        const likerData = likerDoc.exists ? likerDoc.data() || {} : {};
        const likerName = String(likerData.name || likerData.username || 'Someone').trim() || 'Someone';

        const message = {
            notification: {
                title: 'Your reply got a like',
                body: `${likerName} liked your reply in Community.`,
            },
            data: {
                type: 'community_reply_like',
                postId: context.params.postId,
                replyId: context.params.replyId,
                likerUid: String(newlyAddedLikerUid),
            },
            android: {
                priority: 'high',
                notification: {
                    channelId: 'high_importance_channel',
                    sound: 'default',
                },
            },
            apns: {
                headers: {
                    'apns-priority': '10',
                    'apns-push-type': 'alert',
                },
                payload: {
                    aps: {
                        alert: {
                            title: 'Someone liked your reply',
                            body: `${likerName} liked your reply in Community.`,
                        },
                        sound: 'default',
                    },
                },
            },
        };

        try {
            const delivery = await sendCommunityNotificationToOwner({
                ownerUid,
                ownerData,
                message,
                context: {
                    trigger: 'notifyOnCommunityReplyLike',
                    postId: String(context.params.postId || ''),
                    replyId: String(context.params.replyId || ''),
                },
            });

            logCommunityNotification('reply_like_sent', {
                postId: context.params.postId,
                replyId: context.params.replyId,
                ownerUid,
                likerUid: newlyAddedLikerUid,
                mode: delivery.mode,
                successCount: delivery.count,
                tokenTotal: delivery.total || undefined,
                tokenErrorCode: delivery.tokenError?.code,
                tokenErrorMessage: delivery.tokenError?.message,
                topicMessageId: delivery.topicMessageId,
            });
            return null;
        } catch (error) {
            console.error('Error sending community reply like notification:', error);
            await clearInvalidFcmTokenIfNeeded({
                error,
                ownerUid,
                context: {
                    trigger: 'notifyOnCommunityReplyLike',
                    postId: String(context.params.postId || ''),
                    replyId: String(context.params.replyId || ''),
                },
            });
            return null;
        }
    });

function isWorldwideAutoJoinEnabled(userData) {
    // Auto-join is on by default; only an explicit false opts an account out.
    return userData.autoJoinWorldwide !== false;
}

function isActiveMemberAccount(userId, userData, firebaseAccountIds) {
    if (!firebaseAccountIds.has(userId) || userId.startsWith('$RCAnonymousID:')) {
        return false;
    }

    return userData.isVip === true ||
        userData.isActive === true ||
        String(userData.status || '').trim().toLowerCase() === 'active';
}

async function listFirebaseAccountIds() {
    const accountIds = new Set();
    let pageToken;

    do {
        const page = await admin.auth().listUsers(1000, pageToken);
        page.users.forEach((user) => accountIds.add(user.uid));
        pageToken = page.pageToken;
    } while (pageToken);

    return accountIds;
}

function isWorldwideEventCurrentOrFuture(eventData, now = new Date()) {
    const start = parseEventDate(eventData.startTimeUTC) || parseEventDate(eventData.startTime);
    if (!start) return false;

    const configuredEnd = parseEventDate(eventData.endTime);
    const durationSeconds = Number(eventData.durationSeconds);
    const end = configuredEnd || new Date(
        start.getTime() + (Number.isFinite(durationSeconds) && durationSeconds > 0
            ? durationSeconds
            : 60 * 60) * 1000,
    );
    const visibilityAfterMinutes = Math.max(0, Number(eventData.noticeBoardVisibilityAfterMinutes || 0));
    return end.getTime() + visibilityAfterMinutes * 60 * 1000 >= now.getTime();
}

async function syncActiveMemberTotals() {
    const db = admin.firestore();
    const [usersSnap, firebaseAccountIds] = await Promise.all([
        db.collection('users').get(),
        listFirebaseAccountIds(),
    ]);
    const activeMemberRegionTotals = {};
    const activeMemberRegionOffsets = {};
    let activeMemberCount = 0;

    usersSnap.docs.forEach((userDoc) => {
        const userData = userDoc.data() || {};
        if (!isActiveMemberAccount(userDoc.id, userData, firebaseAccountIds)) {
            return;
        }
        activeMemberCount++;
        const timeZone = String(userData.timeZone || 'Unknown').trim() || 'Unknown';
        activeMemberRegionTotals[timeZone] = (activeMemberRegionTotals[timeZone] || 0) + 1;
        const offset = Number(userData.timeZoneOffset);
        if (Number.isFinite(offset)) {
            activeMemberRegionOffsets[timeZone] = offset;
        }
    });

    await db.collection('app_config').doc('home_screen').set(
        {
            worldwideUserTotal: activeMemberCount,
            worldwideUserTotalUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
            regionalUserTotals: activeMemberRegionTotals,
            regionalUserOffsets: activeMemberRegionOffsets,
            regionalUserTotalsUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
    );
    return { activeMemberCount, activeMemberRegionTotals };
}

async function syncWorldwideParticipantCount(eventId) {
    const db = admin.firestore();
    const eventRef = db.collection('global_events').doc(eventId);
    const [eventSnap, usersSnap, registrationsSnap, firebaseAccountIds] = await Promise.all([
        eventRef.get(),
        db.collection('users').get(),
        db.collectionGroup('registered_events').where('eventId', '==', eventId).get(),
        listFirebaseAccountIds(),
    ]);

    if (!eventSnap.exists) return null;

    const eventData = eventSnap.data() || {};
    const activeMemberIds = new Set();
    usersSnap.docs.forEach((userDoc) => {
        const userData = userDoc.data() || {};
        if (isActiveMemberAccount(userDoc.id, userData, firebaseAccountIds)) {
            activeMemberIds.add(userDoc.id);
        }
    });

    if (eventData.isPublished !== true ||
        eventData.isDraft === true ||
        !isWorldwideEventCurrentOrFuture(eventData)) {
        return null;
    }

    const participantIds = new Set();
    usersSnap.docs.forEach((userDoc) => {
        const userData = userDoc.data() || {};
        if (activeMemberIds.has(userDoc.id) &&
            isWorldwideAutoJoinEnabled(userData)) {
            participantIds.add(userDoc.id);
        }
    });

    registrationsSnap.docs.forEach((registrationDoc) => {
        const userId = registrationDoc.ref.parent.parent?.id;
        if (userId && activeMemberIds.has(userId)) participantIds.add(userId);
    });

    await eventRef.set(
        {
            participantCount: participantIds.size,
            participantCountUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
    );
    console.log('WORLDWIDE_PARTICIPANT_COUNT_SYNC', {
        eventId,
        activeMemberCount: activeMemberIds.size,
        joinedMemberCount: participantIds.size,
    });
    return participantIds.size;
}

exports.syncWorldwideParticipantCountOnPublish = functions.firestore
    .document('global_events/{eventId}')
    .onWrite(async (change, context) => {
        if (!change.after.exists) return null;

        const after = change.after.data() || {};
        if (after.isPublished !== true ||
            after.isDraft === true ||
            !isWorldwideEventCurrentOrFuture(after)) return null;

        const before = change.before.exists ? (change.before.data() || {}) : {};
        const relevantFields = [
            'isPublished',
            'isDraft',
            'startTimeUTC',
            'startTime',
            'endTime',
            'durationSeconds',
        ];
        const shouldSync = !change.before.exists || relevantFields.some(
            (field) => JSON.stringify(before[field] ?? null) !== JSON.stringify(after[field] ?? null),
        );

        if (!shouldSync) return null;
        return syncWorldwideParticipantCount(context.params.eventId);
    });

exports.syncWorldwideParticipantCountOnAutoJoinChange = functions.firestore
    .document('users/{userId}')
    .onWrite(async (change) => {
        const before = change.before.exists ? (change.before.data() || {}) : {};
        const after = change.after.exists ? (change.after.data() || {}) : {};
        await syncActiveMemberTotals();
        if (change.before.exists &&
            isWorldwideAutoJoinEnabled(before) === isWorldwideAutoJoinEnabled(after)) {
            return null;
        }

        const globalEvents = await admin.firestore().collection('global_events').get();
        await Promise.all(
            globalEvents.docs
                .filter((eventDoc) => {
                    const data = eventDoc.data() || {};
                    return data.isPublished === true &&
                        data.isDraft !== true &&
                        isWorldwideEventCurrentOrFuture(data);
                })
                .map((eventDoc) => syncWorldwideParticipantCount(eventDoc.id)),
        );
        return null;
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

        const eventExists = await admin.firestore().runTransaction(async (transaction) => {
            const eventDoc = await transaction.get(eventRef);
            if (!eventDoc.exists) {
                // Fallback: Check the other collection if not found (just in case)
                // This handles legacy or misnamed IDs
                return; 
            }

            const eventData = eventDoc.data();
            
            // 1. Increment Participant Count
            const updates = {};
            if (!isGlobal) {
                const currentCount = eventData.participantCount || 0;
                updates.participantCount = currentCount + 1;
            }

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
            
            if (Object.keys(updates).length > 0) {
                transaction.update(eventRef, updates);
            }
            return true;
        });

        if (isGlobal && eventExists) {
            await syncWorldwideParticipantCount(eventId);
        }
        return null;
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

function parseFeaturedItems(raw) {
    const list = Array.isArray(raw) ? raw : [];
    return list
        .filter((item) => item && typeof item === 'object')
        .map((item) => ({ ...item }))
        .filter((item) => typeof item.text === 'string' && item.text.trim().length > 0);
}

function parseFeaturedKeywords(raw) {
    const list = Array.isArray(raw) ? raw : [];
    const normalized = list
        .map((value) => String(value || '').trim().toLowerCase())
        .filter((value) => value.length > 0);
    return [...new Set(normalized)];
}

function parseSourceTimestamp(value) {
    if (!value) return null;
    if (value instanceof admin.firestore.Timestamp) {
        return value.toDate();
    }
    if (typeof value === 'string') {
        const parsed = new Date(value);
        if (!Number.isNaN(parsed.getTime())) return parsed;
    }
    return null;
}

function buildFeaturedDisplayText(item) {
    const rawText = String(item.text || '').replace(/\s+/g, ' ').trim();
    if (!rawText) return '';

    const sourceType = String(item.sourceType || 'manual').toLowerCase();
    const isCommentSource = sourceType.includes('comment');
    const maxLen = isCommentSource ? 180 : 260;
    const trimmed = rawText.length > maxLen ? `${rawText.slice(0, maxLen)}...` : rawText;

    if (!isCommentSource) {
        return trimmed;
    }

    const ts = parseSourceTimestamp(item.sourceTimestamp);
    if (!ts) {
        return trimmed;
    }

    const mm = String(ts.getUTCMonth() + 1).padStart(2, '0');
    const dd = String(ts.getUTCDate()).padStart(2, '0');
    const hh = String(ts.getUTCHours()).padStart(2, '0');
    const min = String(ts.getUTCMinutes()).padStart(2, '0');
    // Keep metadata compact to preserve pinned panel height in user app.
    return `${trimmed} [Feed ${mm}/${dd} ${hh}:${min} UTC]`;
}

exports.publishCommunityFeaturedCarousel = functions.pubsub
    .schedule('every 1 minutes')
    .timeZone('UTC')
    .onRun(async () => {
        const db = admin.firestore();
        const settingsRef = db.collection('app_config').doc('community_settings');
        const settingsSnap = await settingsRef.get();

        if (!settingsSnap.exists) {
            return null;
        }

        const settings = settingsSnap.data() || {};
        if (settings.showPinnedAdminMessage === false) {
            return null;
        }
        const enabled = settings.featuredCarouselEnabled === true;
        const autoPublish = settings.featuredAutoPublish === true;
        if (!enabled || !autoPublish) {
            return null;
        }

        const intervalSeconds = Math.max(
            30,
            Math.min(172800, Number(settings.featuredIntervalSeconds || 60) || 60),
        );
        const lastPublishedAt = settings.featuredLastPublishedAt instanceof admin.firestore.Timestamp
            ? settings.featuredLastPublishedAt.toDate()
            : null;

        if (lastPublishedAt) {
            const elapsedSeconds = Math.floor((Date.now() - lastPublishedAt.getTime()) / 1000);
            if (elapsedSeconds < intervalSeconds) {
                return null;
            }
        }

        const randomize = settings.featuredRandomize === true;
        const sourceMode = String(settings.featuredSourceMode || 'mixed').toLowerCase();
        const currentIndex = Number(settings.featuredCurrentIndex || 0) || 0;
        const adminIndex = Number(settings.featuredAdminIndex || currentIndex) || 0;
        const userIndex = Number(settings.featuredUserIndex || 0) || 0;
        const mixedUserStreak = Number(settings.featuredMixedUserStreak || 0) || 0;
        const mixedAdminEveryUsers = Math.max(
            1,
            Math.min(100, Number(settings.featuredMixedAdminEveryUsers || 5) || 5),
        );
        const keywords = parseFeaturedKeywords(settings.featuredKeywords);
        const includeManual = sourceMode !== 'keywords_only';
        const includeKeywords = sourceMode !== 'admin_only';
        const manualMessage = String(settings.admin_message_manual || '').trim();
        const manualItems = includeManual
            ? parseFeaturedItems(settings.featuredItems).filter((item) => item.active !== false)
            : [];

        const adminCandidates = [
            ...(includeManual && manualMessage
                ? [{
                    id: 'manual_admin_message',
                    text: manualMessage,
                    sourceType: 'manual_admin_message',
                    active: true,
                }]
                : []),
            ...manualItems,
        ];
        const userCandidates = [];

        if (includeKeywords && keywords.length > 0) {
            const postsSnap = await db
                .collection('community_posts')
                .orderBy('timestamp', 'desc')
                .limit(120)
                .get();

            postsSnap.forEach((doc) => {
                const data = doc.data() || {};
                const content = String(data.content || '').trim();
                if (!content) return;

                const lower = content.toLowerCase();
                const matchedKeyword = keywords.find((keyword) => lower.includes(keyword)) || '';
                if (!matchedKeyword) return;

                userCandidates.push({
                    id: `kw_${doc.id}`,
                    text: content,
                    sourceType: 'keyword_comment',
                    sourceKeyword: matchedKeyword,
                    sourcePostId: doc.id,
                    sourceTimestamp: data.timestamp || null,
                    active: true,
                });
            });
        }

        let selectedPool = [];
        let selectedPoolType = 'admin';
        let nextAdminIndex = adminIndex;
        let nextUserIndex = userIndex;
        let nextMixedUserStreak = mixedUserStreak;

        if (sourceMode === 'admin_only') {
            selectedPool = adminCandidates;
            selectedPoolType = 'admin';
        } else if (sourceMode === 'keywords_only') {
            selectedPool = userCandidates;
            selectedPoolType = 'user';
        } else {
            if (adminCandidates.length === 0 && userCandidates.length === 0) {
                return null;
            }

            const shouldUseAdmin = userCandidates.length === 0 ||
                (adminCandidates.length > 0 && mixedUserStreak >= mixedAdminEveryUsers);

            if (shouldUseAdmin && adminCandidates.length > 0) {
                selectedPool = adminCandidates;
                selectedPoolType = 'admin';
            } else if (userCandidates.length > 0) {
                selectedPool = userCandidates;
                selectedPoolType = 'user';
            } else {
                selectedPool = adminCandidates;
                selectedPoolType = 'admin';
            }
        }

        if (selectedPool.length === 0) {
            return null;
        }

        const selectedIndex = randomize
            ? Math.floor(Math.random() * selectedPool.length)
            : (((selectedPoolType === 'admin' ? adminIndex : userIndex) % selectedPool.length) + selectedPool.length) % selectedPool.length;

        if (!randomize) {
            if (selectedPoolType === 'admin') {
                nextAdminIndex = (selectedIndex + 1) % selectedPool.length;
            } else {
                nextUserIndex = (selectedIndex + 1) % selectedPool.length;
            }
        }

        if (sourceMode === 'mixed') {
            nextMixedUserStreak = selectedPoolType === 'admin'
                ? 0
                : Math.min(100000, mixedUserStreak + 1);
        } else {
            nextMixedUserStreak = 0;
        }

        const selected = selectedPool[selectedIndex];
        const selectedSourceType = String(selected.sourceType || 'manual').toLowerCase();
        const displayType = selectedSourceType.includes('comment') ? 'featured' : 'pinned';
        const publishText = buildFeaturedDisplayText(selected);

        if (!publishText) {
            return null;
        }

        await settingsRef.set(
            {
                admin_message: publishText,
                admin_message_display_type: displayType,
                featuredCurrentIndex: selectedPoolType === 'admin' ? nextAdminIndex : nextUserIndex,
                featuredAdminIndex: nextAdminIndex,
                featuredUserIndex: nextUserIndex,
                featuredMixedUserStreak: nextMixedUserStreak,
                featuredLastPublishedAt: admin.firestore.FieldValue.serverTimestamp(),
                featuredLastSourceType: selected.sourceType || 'manual',
                featuredLastKeyword: selected.sourceKeyword || null,
                featuredLastPostId: selected.sourcePostId || null,
                featuredLastPublishedPreview: publishText,
            },
            { merge: true },
        );

        return null;
    });

exports.moderateUploadedImageWithSafeSearch = onObjectFinalized(
    { region: 'europe-west4' },
    async (event) => {
        const object = event.data || {};
        const objectName = String(object.name || '').trim();
        const contentType = String(object.contentType || '').toLowerCase();
        const bucketName = String(object.bucket || '').trim();

        if (!objectName || !bucketName) return null;
        if (!contentType.startsWith('image/')) return null;

        const parsed = parseModeratedPath(objectName);
        if (!parsed.supported) return null;

        const gcsUri = `gs://${bucketName}/${objectName}`;

        let safeSearch;
        try {
            const [result] = await visionClient.safeSearchDetection({
                image: { source: { imageUri: gcsUri } },
            });
            safeSearch = result.safeSearchAnnotation || {};
        } catch (error) {
            console.error('SAFESEARCH_ERROR', { objectName, error: error?.message || error });
            await logModerationEvent({
                type: 'safe_search_error',
                objectName,
                bucketName,
                uid: parsed.uid || null,
                status: 'resolved',
                reason: 'SafeSearch processing error',
                details: error?.message || String(error),
            });
            return null;
        }

        const adult = String(safeSearch.adult || 'UNKNOWN');
        const violence = String(safeSearch.violence || 'UNKNOWN');
        const racy = String(safeSearch.racy || 'UNKNOWN');
        const policy = await loadModerationPolicy();
        const adultCritical = isAtOrAboveLikelihood(adult, policy.adultThreshold);
        const violenceCriticalBase = isAtOrAboveLikelihood(violence, policy.violenceThreshold);
        const violenceCritical = policy.requireAdultNotVeryUnlikelyForViolence
            ? (violenceCriticalBase && adult !== 'VERY_UNLIKELY')
            : violenceCriticalBase;
        const racyCritical = isAtOrAboveLikelihood(racy, policy.racyThreshold);
        const isFlagged = adultCritical || violenceCritical || racyCritical;

        const imageUrl = objectName
            ? `https://storage.googleapis.com/${bucketName}/${encodeURIComponent(objectName).replace(/%2F/g, '/')}`
            : null;

        if (!isFlagged) {
            console.log('SAFESEARCH_PASS', {
                objectName,
                bucketName,
                uid: parsed.uid || null,
                safeSearch: { adult, violence, racy },
                policy,
            });
            return null;
        }

        await logModerationEvent({
            type: 'safe_search_flagged_review',
            objectName,
            bucketName,
            uid: parsed.uid || null,
            storageType: parsed.type,
            reason: 'SafeSearch flagged image',
            content: `Image flagged by SafeSearch (adult=${adult}, violence=${violence}, racy=${racy})`,
            imageUrl,
            status: 'pending',
            safeSearch: { adult, violence, racy },
            moderationPolicy: policy,
        });

        return null;
    },
);

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

function parseEventDate(value) {
    if (!value) return null;
    if (value instanceof admin.firestore.Timestamp) {
        return value.toDate();
    }
    if (value instanceof Date) {
        return value;
    }
    if (typeof value === 'string') {
        const parsed = new Date(value);
        if (!Number.isNaN(parsed.getTime())) return parsed;
    }
    return null;
}

function calculateRegistrationExpiry(data) {
    const end = parseEventDate(data.endTime);
    const start = parseEventDate(data.startTime) || parseEventDate(data.timestamp);
    const baseEnd = end || (start ? new Date(start.getTime() + 60 * 60 * 1000) : null);
    if (!baseEnd) return null;

    const visibilityAfterMinutesRaw = Number(data.visibilityAfterMinutes || 0);
    const visibilityAfterMinutes = Number.isFinite(visibilityAfterMinutesRaw)
        ? Math.max(0, visibilityAfterMinutesRaw)
        : 0;

    return new Date(baseEnd.getTime() + visibilityAfterMinutes * 60 * 1000);
}

async function pruneRegisteredEventsForUser(userId, options = {}) {
    const {
        now = new Date(),
        eventIdFilter = null,
        dryRun = false,
    } = options;

    const db = admin.firestore();
    const regRef = db.collection('users').doc(userId).collection('registered_events');
    const snap = await regRef.get();

    if (snap.empty) {
        return { scanned: 0, removed: 0 };
    }

    const batch = db.batch();
    let scanned = 0;
    let removed = 0;

    snap.docs.forEach((doc) => {
        scanned++;
        const data = doc.data() || {};
        const eventId = String(data.eventId || '').trim();
        if (eventIdFilter && eventId !== eventIdFilter) {
            return;
        }

        const expiry = calculateRegistrationExpiry(data);
        if (!expiry) {
            return;
        }

        if (expiry.getTime() < now.getTime()) {
            removed++;
            if (!dryRun) {
                batch.delete(doc.ref);
            }
        }
    });

    if (!dryRun && removed > 0) {
        await batch.commit();
    }

    return { scanned, removed };
}

exports.cleanupExpiredRegisteredEventsForUser = functions.https.onCall(async (data, context) => {
    await assertSuperAdmin(context);

    const userId = String(data.userId || '').trim();
    if (!userId) {
        throw new functions.https.HttpsError('invalid-argument', 'userId is required.');
    }

    const eventId = String(data.eventId || '').trim();
    const dryRun = data.dryRun === true;
    const result = await pruneRegisteredEventsForUser(userId, {
        dryRun,
        eventIdFilter: eventId || null,
    });

    return {
        ok: true,
        userId,
        eventId: eventId || null,
        dryRun,
        scanned: result.scanned,
        removed: result.removed,
    };
});

exports.cleanupExpiredRegisteredEvents = functions.pubsub
    .schedule('every 15 minutes')
    .timeZone('UTC')
    .onRun(async () => {
        // Disabled 2026-09-03: registered_events is now the source for the
        // lifetime "Intents Added" counter on My Harmony, so we must stop
        // deleting rows once an event's visibility window closes. The My
        // Events carousel already filters expired entries client-side by
        // time, so no display regression from keeping old rows around.
        return null;
    });

function parseEventWindow(data) {
    const start = parseEventDate(data.startTimeUTC) || parseEventDate(data.startTime);
    if (!start) return null;

    let end = parseEventDate(data.endTime);
    if (!end) {
        const durationRaw = Number(data.durationSeconds || 0);
        const durationSeconds = Number.isFinite(durationRaw) && durationRaw > 0
            ? durationRaw
            : 3600;
        end = new Date(start.getTime() + durationSeconds * 1000);
    }

    return { start, end };
}

function londonNowParts(now) {
    const fmt = new Intl.DateTimeFormat('en-GB', {
        timeZone: 'Europe/London',
        year: 'numeric',
        month: '2-digit',
        day: '2-digit',
        hour: '2-digit',
        minute: '2-digit',
        hour12: false,
    });

    const parts = fmt.formatToParts(now);
    const get = (type) => parts.find((p) => p.type === type)?.value || '';
    const year = get('year');
    const month = get('month');
    const day = get('day');
    const hour = get('hour');
    const minute = get('minute');

    return {
        dateKey: `${year}${month}${day}`,
        hour,
        minute,
        minuteOfDay: Number(hour) * 60 + Number(minute),
    };
}

function londonShortZone(now) {
    const fmt = new Intl.DateTimeFormat('en-GB', {
        timeZone: 'Europe/London',
        timeZoneName: 'short',
    });
    const parts = fmt.formatToParts(now);
    const zone = parts.find((p) => p.type === 'timeZoneName')?.value || '';
    return String(zone).trim().toUpperCase();
}

function normalizeZone(raw) {
    return String(raw || '').trim().toUpperCase();
}

function formatMinuteOfDay(minuteOfDay) {
    const normalized = ((minuteOfDay % 1440) + 1440) % 1440;
    const hh = String(Math.floor(normalized / 60)).padStart(2, '0');
    const mm = String(normalized % 60).padStart(2, '0');
    return `${hh}:${mm}`;
}

function parseIsoDate(value) {
    const raw = String(value || '').trim();
    if (!raw) return null;
    const dt = new Date(raw);
    if (Number.isNaN(dt.getTime())) return null;
    return dt;
}

function pickCanonicalEventDoc(docs, now) {
    if (!Array.isArray(docs) || docs.length === 0) return null;

    const withStart = docs
        .map((doc) => {
            const data = doc.data() || {};
            return {
                doc,
                data,
                start: parseIsoDate(data.startTimeUTC),
            };
        })
        .filter((entry) => entry.start !== null);

    if (withStart.length === 0) {
        return docs[0];
    }

    const candidates = withStart
        .filter((entry) => entry.start.getTime() <= now.getTime())
        .sort((a, b) => b.start.getTime() - a.start.getTime());
    if (candidates.length > 0) {
        return candidates[0].doc;
    }

    withStart.sort((a, b) => a.start.getTime() - b.start.getTime());
    return withStart[0].doc;
}

function isActiveBySlotFallback(docId, data, now) {
    const match = /^slot_(\d{2})(\d{2})_(\d{8})$/.exec(String(docId || '').trim());
    if (!match) return false;

    const [, hh, mm, dateKey] = match;
    const slotMinuteOfDay = Number(hh) * 60 + Number(mm);
    const durationRaw = Number(data.durationSeconds || 0);
    const durationSeconds = Number.isFinite(durationRaw) && durationRaw > 0
        ? durationRaw
        : 60;
    const windowMinutes = Math.max(1, Math.ceil(durationSeconds / 60));
    const preWarmMinutes = 1;

    const london = londonNowParts(now);
    if (london.dateKey !== dateKey) return false;

    return london.minuteOfDay >= (slotMinuteOfDay - preWarmMinutes) &&
        london.minuteOfDay < (slotMinuteOfDay + windowMinutes);
}

function timestampToDate(value) {
    if (!value) return null;
    if (value instanceof admin.firestore.Timestamp) return value.toDate();
    if (value instanceof Date) return value;
    if (typeof value === 'string') {
        const parsed = new Date(value);
        if (!Number.isNaN(parsed.getTime())) return parsed;
    }
    return null;
}

function normalizedUserId(raw) {
    return String(raw || '').trim();
}

async function listActivePublishedEventIds(now) {
    const db = admin.firestore();
    const startWindow = new Date(now.getTime() - 2 * 60 * 60 * 1000).toISOString();
    const endWindow = new Date(now.getTime() + 2 * 60 * 60 * 1000).toISOString();

    const snap = await db
        .collection('events')
        .where('startTimeUTC', '>=', startWindow)
        .where('startTimeUTC', '<=', endWindow)
        .get();

    const activeEventMap = new Map();
    const markActive = (docId, data) => {
        if (!docId) return;
        if (!activeEventMap.has(docId)) {
            activeEventMap.set(docId, data || {});
        }
    };

    snap.docs.forEach((doc) => {
        const data = doc.data() || {};
        if (data.isPublished !== true) return;
        if (data.isDraft === true) return;

        if (isActiveBySlotFallback(doc.id, data, now)) {
            markActive(doc.id, data);
            return;
        }

        const window = parseEventWindow(data);
        if (!window) return;
        const startWithPreWarm = new Date(window.start.getTime() - 90 * 1000);
        const inWindow = now >= startWithPreWarm && now <= window.end;
        if (inWindow) markActive(doc.id, data);
    });

    // Fallback: app playback can still use published slots by clock time even
    // when stored startTimeUTC/doc date key is stale. Match by London clock.
    const london = londonNowParts(now);
    const currentClock = formatMinuteOfDay(london.minuteOfDay);
    const nextClock = formatMinuteOfDay(london.minuteOfDay + 1);

    const [currentSnap, nextSnap] = await Promise.all([
        db.collection('events').where('originTime', '==', currentClock).get(),
        db.collection('events').where('originTime', '==', nextClock).get(),
    ]);

    [currentSnap, nextSnap].forEach((timeSnap) => {
        const eligible = timeSnap.docs.filter((doc) => {
            const data = doc.data() || {};
            return data.isPublished === true && data.isDraft !== true;
        });

        const canonical = pickCanonicalEventDoc(eligible, now);
        if (!canonical) return;
        markActive(canonical.id, canonical.data() || {});
    });

    return Array.from(activeEventMap.entries()).map(([id, data]) => ({ id, data }));
}

async function listOpenAppCandidates(cutoffTs, recentUserActiveCutoffTs) {
    const db = admin.firestore();
    const roomSnap = await db
        .collection('room_live_presence')
        .doc('community_room')
        .collection('sessions')
        .where('lastSeenAt', '>=', cutoffTs)
        .get();

    const candidates = new Map();
    roomSnap.docs.forEach((doc) => {
        const data = doc.data() || {};
        const userId = normalizedUserId(data.userId);
        if (!userId) return;
        candidates.set(userId, {
            userId,
            timeZone: String(data.timeZone || '').trim() || null,
            countryCode: String(data.countryCode || '').trim().toUpperCase() || null,
            flagEmoji: String(data.flagEmoji || '').trim() || null,
            reasons: ['open_app'],
        });
    });

    const usersSnap = await db
        .collection('users')
        .where('lastActive', '>=', recentUserActiveCutoffTs)
        .get();

    usersSnap.docs.forEach((doc) => {
        const data = doc.data() || {};
        if (data.autoJoinWorldwide !== true) return;

        const userId = normalizedUserId(doc.id);
        if (!userId) return;

        const countryCode = String(
            data.countryCode || data.country_code || data.country || '',
        )
            .trim()
            .toUpperCase();

        const existing = candidates.get(userId);
        if (!existing) {
            candidates.set(userId, {
                userId,
                timeZone: String(data.timeZone || '').trim() || null,
                countryCode: countryCode || null,
                flagEmoji: String(data.flagEmoji || '').trim() || null,
                reasons: ['open_app_recent_activity'],
            });
            return;
        }

        const mergedReasons = new Set([...(existing.reasons || []), 'open_app_recent_activity']);
        existing.reasons = Array.from(mergedReasons);
        existing.timeZone = existing.timeZone || String(data.timeZone || '').trim() || null;
        existing.countryCode = existing.countryCode || countryCode || null;
        existing.flagEmoji = existing.flagEmoji || String(data.flagEmoji || '').trim() || null;
        candidates.set(userId, existing);
    });

    return candidates;
}

async function listDormantOverrideCandidates(recentUserActiveCutoffDate) {
    const db = admin.firestore();
    const snap = await db
        .collection('users')
        .where('dormantPlaybackEnabled', '==', true)
        .where('autoJoinWorldwide', '==', true)
        .get();

    const candidates = new Map();
    snap.docs.forEach((doc) => {
        const data = doc.data() || {};
        const lastActive = timestampToDate(data.lastActive);
        if (!lastActive) return;
        if (lastActive.getTime() < recentUserActiveCutoffDate.getTime()) return;

        const userId = normalizedUserId(doc.id);
        if (!userId) return;

        const countryCode = String(
            data.countryCode || data.country_code || data.country || '',
        )
            .trim()
            .toUpperCase();

        candidates.set(userId, {
            userId,
            timeZone: String(data.timeZone || '').trim() || null,
            countryCode: countryCode || null,
            flagEmoji: String(data.flagEmoji || '').trim() || null,
            reasons: ['dormant_override'],
        });
    });

    return candidates;
}

exports.guardrailEventLiveCounter = functions.pubsub
    .schedule('every 1 minutes')
    .timeZone('UTC')
    .onRun(async () => runGuardrailEventCounterPass(new Date()));

async function runGuardrailEventCounterPass(now) {
    const db = admin.firestore();
    const bridgeLastSeenAt = admin.firestore.Timestamp.fromDate(
        new Date(now.getTime() + 75 * 1000),
    );
    const cutoffTs = admin.firestore.Timestamp.fromDate(
        new Date(now.getTime() - 70 * 1000),
    );
    const recentUserActiveCutoffDate = new Date(now.getTime() - 15 * 60 * 1000);
    const recentUserActiveCutoffTs = admin.firestore.Timestamp.fromDate(
        recentUserActiveCutoffDate,
    );

        const activeEvents = await listActivePublishedEventIds(now);
        if (activeEvents.length === 0) {
        return null;
    }

    const [openAppCandidates, dormantCandidates] = await Promise.all([
        listOpenAppCandidates(cutoffTs, recentUserActiveCutoffTs),
        listDormantOverrideCandidates(recentUserActiveCutoffDate),
    ]);

        for (const activeEvent of activeEvents) {
            const eventId = activeEvent.id;
            const eventData = activeEvent.data || {};
            const eventType = String(eventData.type || '').trim().toLowerCase();
            const isWorldwide = eventType === 'worldwide' || eventType === 'global';

        const eventRef = db.collection('event_live_viewers').doc(eventId);
        const sessionsRef = eventRef.collection('sessions');

        const [activeSessionsSnap, existingBridgeSnap] = await Promise.all([
            sessionsRef.where('lastSeenAt', '>=', cutoffTs).get(),
            sessionsRef.where('source', '==', 'backend_live_counter_bridge_v3').get(),
        ]);

        const realUserIds = new Set();
            const realZones = new Set();
        activeSessionsSnap.docs.forEach((doc) => {
            const data = doc.data() || {};
            const source = String(data.source || '');
            if (source === 'backend_live_counter_bridge_v3') return;
            const userId = normalizedUserId(data.userId);
            if (userId) realUserIds.add(userId);
                const zone = normalizeZone(data.timeZone);
                if (zone) realZones.add(zone);
        });

            const allowedZones = new Set();
            if (!isWorldwide) {
                if (realZones.size > 0) {
                    realZones.forEach((zone) => allowedZones.add(zone));
                } else {
                    const originZone = normalizeZone(eventData.originTimeZone);
                    if (originZone) {
                        allowedZones.add(originZone);
                    } else {
                        const londonZone = londonShortZone(now);
                        if (londonZone) allowedZones.add(londonZone);
                    }
                }
            }

        const candidateMap = new Map();
        const addCandidate = (candidate) => {
            if (!candidate || !candidate.userId) return;
            if (realUserIds.has(candidate.userId)) return;
                if (!isWorldwide) {
                    const candidateZone = normalizeZone(candidate.timeZone);
                    if (!candidateZone || !allowedZones.has(candidateZone)) {
                        return;
                    }
                }
            const existing = candidateMap.get(candidate.userId);
            if (!existing) {
                candidateMap.set(candidate.userId, candidate);
                return;
            }

            const mergedReasons = new Set([...(existing.reasons || []), ...(candidate.reasons || [])]);
            existing.reasons = Array.from(mergedReasons);
            existing.timeZone = existing.timeZone || candidate.timeZone || null;
            existing.countryCode = existing.countryCode || candidate.countryCode || null;
            existing.flagEmoji = existing.flagEmoji || candidate.flagEmoji || null;
            candidateMap.set(candidate.userId, existing);
        };

        openAppCandidates.forEach((candidate) => addCandidate(candidate));
        dormantCandidates.forEach((candidate) => addCandidate(candidate));

        const batch = db.batch();

        candidateMap.forEach((candidate, userId) => {
            const bridgeDocId = `bridge_v3_${userId}`;
            batch.set(
                sessionsRef.doc(bridgeDocId),
                {
                    sessionId: bridgeDocId,
                    userId,
                    // Keep bridge sessions visible through short (10-40s) events,
                    // despite the app-side 15s active cutoff.
                    lastSeenAt: bridgeLastSeenAt,
                    timeZone: candidate.timeZone || null,
                    countryCode: candidate.countryCode || null,
                    flagEmoji: candidate.flagEmoji || null,
                    source: 'backend_live_counter_bridge_v3',
                    reasons: candidate.reasons || [],
                },
                { merge: true },
            );
        });

        existingBridgeSnap.docs.forEach((doc) => {
            const data = doc.data() || {};
            const userId = normalizedUserId(data.userId);
            if (!userId || !candidateMap.has(userId)) {
                batch.delete(doc.ref);
            }
        });

        batch.set(
            eventRef,
            {
                eventId,
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            { merge: true },
        );

        await batch.commit();
    }

    return null;
}

exports.guardrailEventLiveCounterOnRoomPresence = functions.region('europe-west1').firestore
    .document('room_live_presence/community_room/sessions/{sessionId}')
    .onWrite(async (change) => {
        if (!change.after.exists) return null;
        return runGuardrailEventCounterPass(new Date());
    });

exports.guardrailEventLiveCounterOnUserActivity = functions.region('europe-west1').firestore
    .document('users/{userId}')
    .onWrite(async (change) => {
        if (!change.after.exists) return null;
        const before = change.before.exists ? (change.before.data() || {}) : {};
        const after = change.after.data() || {};

        if (after.autoJoinWorldwide !== true) return null;

        const beforeLast = timestampToDate(before.lastActive);
        const afterLast = timestampToDate(after.lastActive);
        if (!afterLast) return null;
        if (beforeLast && afterLast.getTime() === beforeLast.getTime()) return null;

        return runGuardrailEventCounterPass(new Date());
    });

function currentMonthKeyUtc() {
    const now = new Date();
    const month = String(now.getUTCMonth() + 1).padStart(2, '0');
    return `${now.getUTCFullYear()}-${month}`;
}

function normalizeCurrencyCode(raw) {
    const code = String(raw || '').trim().toUpperCase();
    return code.length === 3 ? code : null;
}

function collectDefaultCurrencies() {
    return ['GBP', 'USD', 'EUR', 'AUD', 'CAD', 'NZD', 'ZAR', 'NGN', 'INR'];
}

async function collectTargetCurrencies() {
    const snap = await admin.firestore().collection('sellers').get();
    const result = new Set(collectDefaultCurrencies());

    snap.docs.forEach((doc) => {
        const data = doc.data() || {};
        const payoutCurrency = normalizeCurrencyCode(data.payoutCurrency);
        if (payoutCurrency) {
            result.add(payoutCurrency);
        }
    });

    result.delete('GBP');
    return Array.from(result).sort();
}

async function fetchLiveGbpRates(targetCurrencies) {
    if (!Array.isArray(targetCurrencies) || targetCurrencies.length === 0) {
        return { rates: { GBP: 1 }, provider: 'frankfurter' };
    }

    const to = targetCurrencies.join(',');
    const url = `https://api.frankfurter.app/latest?from=GBP&to=${encodeURIComponent(to)}`;
    const response = await fetch(url, {
        method: 'GET',
        headers: { 'accept': 'application/json' },
    });

    if (!response.ok) {
        throw new Error(`FX provider error: ${response.status}`);
    }

    const payload = await response.json();
    const apiRates = payload && typeof payload === 'object' ? payload.rates || {} : {};

    const rates = { GBP: 1 };
    targetCurrencies.forEach((code) => {
        const value = apiRates[code];
        if (typeof value === 'number' && Number.isFinite(value) && value > 0) {
            rates[code] = value;
        }
    });

    return {
        rates,
        provider: 'frankfurter',
        providerDate: String(payload.date || ''),
    };
}

async function writeLiveReference({ actor = 'system' } = {}) {
    const targetCurrencies = await collectTargetCurrencies();
    const { rates, provider, providerDate } = await fetchLiveGbpRates(targetCurrencies);

    await admin.firestore().collection('fx_rates').doc('live_reference').set({
        baseCurrency: 'GBP',
        rates,
        provider,
        providerDate,
        targetCurrencies,
        updatedBy: actor,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    return { rates, provider, providerDate, targetCurrencies };
}

async function lockMonthSnapshot(monthKey, actor) {
    const safeMonth = String(monthKey || '').trim() || currentMonthKeyUtc();
    const liveRef = await admin.firestore().collection('fx_rates').doc('live_reference').get();

    if (!liveRef.exists) {
        throw new Error('Live FX reference missing. Refresh live FX first.');
    }

    const data = liveRef.data() || {};
    const rates = data.rates && typeof data.rates === 'object' ? data.rates : null;
    if (!rates || Object.keys(rates).length === 0) {
        throw new Error('Live FX rates are empty.');
    }

    await admin.firestore().collection('fx_rates_monthly').doc(safeMonth).set({
        month: safeMonth,
        baseCurrency: 'GBP',
        rates,
        source: 'fx_rates/live_reference',
        provider: String(data.provider || 'unknown'),
        providerDate: String(data.providerDate || ''),
        lockedBy: actor,
        lockedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    return {
        month: safeMonth,
        rateCount: Object.keys(rates).length,
    };
}

exports.refreshLiveFxRates = functions.https.onCall(async (data, context) => {
    await assertAdminPermission(context, 'seller_management', 'manage seller FX rates');
    const actor = context.auth && context.auth.uid ? context.auth.uid : 'unknown';
    const result = await writeLiveReference({ actor });
    return {
        ok: true,
        provider: result.provider,
        providerDate: result.providerDate,
        rateCount: Object.keys(result.rates).length,
        targetCurrencies: result.targetCurrencies,
    };
});

exports.lockCurrentMonthFxSnapshot = functions.https.onCall(async (data, context) => {
    await assertAdminPermission(context, 'seller_management', 'lock seller FX snapshots');
    const actor = context.auth && context.auth.uid ? context.auth.uid : 'unknown';
    const month = normalizeMonthKey(data && data.month);
    const result = await lockMonthSnapshot(month, actor);
    return {
        ok: true,
        month: result.month,
        rateCount: result.rateCount,
    };
});

function normalizeMonthKey(raw) {
    const value = String(raw || '').trim();
    if (!value) return currentMonthKeyUtc();
    return /^\d{4}-\d{2}$/.test(value) ? value : currentMonthKeyUtc();
}

exports.refreshLiveFxRatesDaily = functions.pubsub
    .schedule('every 24 hours')
    .timeZone('UTC')
    .onRun(async () => {
        await writeLiveReference({ actor: 'scheduler:daily' });
        return null;
    });

exports.lockMonthlyFxSnapshot = functions.pubsub
    .schedule('5 0 1 * *')
    .timeZone('UTC')
    .onRun(async () => {
        await lockMonthSnapshot(currentMonthKeyUtc(), 'scheduler:monthly');
        return null;
    });

exports.cleanupExpiredCommunityFeedImages = functions.pubsub
    .schedule('every 15 minutes')
    .timeZone('UTC')
    .onRun(async () => {
        const db = admin.firestore();
        const nowTs = admin.firestore.Timestamp.now();
        const querySnap = await db
            .collection('community_posts')
            .where('imageExpiresAt', '<=', nowTs)
            .limit(250)
            .get();

        if (querySnap.empty) {
            return null;
        }

        const batch = db.batch();
        let expiredCount = 0;

        querySnap.docs.forEach((doc) => {
            const data = doc.data() || {};
            const hasImage = data.hasImage === true;
            const imageUrl = String(data.imageUrl || '').trim();
            if (!hasImage || !imageUrl) {
                return;
            }

            expiredCount += 1;
            batch.set(doc.ref, {
                hasImage: false,
                imageStatus: 'expired_auto',
                imageExpiredAt: admin.firestore.FieldValue.serverTimestamp(),
                imageUrl: admin.firestore.FieldValue.delete(),
                imageStoragePath: admin.firestore.FieldValue.delete(),
                imageBytes: admin.firestore.FieldValue.delete(),
                imageWidth: admin.firestore.FieldValue.delete(),
                imageHeight: admin.firestore.FieldValue.delete(),
                imageCreatedAt: admin.firestore.FieldValue.delete(),
                imageExpiresAt: admin.firestore.FieldValue.delete(),
                imageSource: admin.firestore.FieldValue.delete(),
            }, { merge: true });
        });

        if (expiredCount === 0) {
            return null;
        }

        await batch.commit();
        console.log('[community_cleanup] expired_images_removed', {
            scanned: querySnap.size,
            expiredCount,
        });

        return null;
    });
