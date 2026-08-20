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
            return null;
        }

        const newlyAddedLikerUid = afterLikedBy.find((uid) => !beforeLikedBy.includes(uid));
        if (!newlyAddedLikerUid) {
            return null;
        }

        const ownerUid = String(after.authorUid || after.userId || after.uid || '').trim();
        if (!ownerUid || ownerUid === newlyAddedLikerUid) {
            return null;
        }

        const ownerDoc = await admin.firestore().collection('users').doc(ownerUid).get();
        if (!ownerDoc.exists) {
            return null;
        }

        const ownerData = ownerDoc.data() || {};
        if (ownerData.notifyOnCommentLikes === false) {
            return null;
        }

        const ownerToken = String(ownerData.fcmToken || '').trim();
        if (!ownerToken) {
            return null;
        }

        const likerDoc = await admin.firestore().collection('users').doc(newlyAddedLikerUid).get();
        const likerData = likerDoc.exists ? likerDoc.data() || {} : {};
        const likerName = String(likerData.name || likerData.username || 'Someone').trim() || 'Someone';

        const message = {
            token: ownerToken,
            notification: {
                title: 'Your comment got a like',
                body: `${likerName} liked your comment in Community.`,
            },
            data: {
                type: 'community_comment_like',
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
                },
                payload: {
                    aps: {
                        sound: 'default',
                    },
                },
            },
        };

        try {
            await admin.messaging().send(message);
            return null;
        } catch (error) {
            console.error('Error sending community like notification:', error);
            return null;
        }
    });

exports.notifyOnCommunityReply = functions.firestore
    .document('community_posts/{postId}/replies/{replyId}')
    .onCreate(async (snap, context) => {
        const reply = snap.data() || {};
        const postId = String(context.params.postId || '').trim();
        if (!postId) {
            return null;
        }

        const postDoc = await admin.firestore().collection('community_posts').doc(postId).get();
        if (!postDoc.exists) {
            return null;
        }

        const postData = postDoc.data() || {};
        const ownerUid = String(postData.authorUid || postData.userId || postData.uid || '').trim();
        const replierUid = String(reply.authorUid || reply.userId || reply.uid || '').trim();

        if (!ownerUid || !replierUid || ownerUid === replierUid) {
            return null;
        }

        const ownerDoc = await admin.firestore().collection('users').doc(ownerUid).get();
        if (!ownerDoc.exists) {
            return null;
        }

        const ownerData = ownerDoc.data() || {};
        if (ownerData.notifyOnCommentLikes === false) {
            return null;
        }

        const ownerToken = String(ownerData.fcmToken || '').trim();
        if (!ownerToken) {
            return null;
        }

        const replierDoc = await admin.firestore().collection('users').doc(replierUid).get();
        const replierData = replierDoc.exists ? replierDoc.data() || {} : {};
        const replierName = String(replierData.name || replierData.username || reply.userName || 'Someone').trim() || 'Someone';
        const replyContent = String(reply.content || reply.text || '').trim();
        const preview = replyContent.length > 80 ? `${replyContent.slice(0, 77)}...` : replyContent;

        const message = {
            token: ownerToken,
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
                },
                payload: {
                    aps: {
                        sound: 'default',
                    },
                },
            },
        };

        try {
            await admin.messaging().send(message);
            return null;
        } catch (error) {
            console.error('Error sending community reply notification:', error);
            return null;
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
        const db = admin.firestore();
        const settingsRef = db.collection('system_settings').doc('maintenance_jobs');
        const settingsSnap = await settingsRef.get();
        const settings = settingsSnap.exists ? settingsSnap.data() || {} : {};

        const lastCursor = typeof settings.registeredEventsPruneCursor === 'string'
            ? settings.registeredEventsPruneCursor
            : null;

        const pageSize = 2000;
        const now = new Date();
        let query = db
            .collectionGroup('registered_events')
            .orderBy(admin.firestore.FieldPath.documentId())
            .limit(pageSize);

        if (lastCursor) {
            query = query.startAfter(lastCursor);
        }

        const snap = await query.get();
        if (snap.empty) {
            await settingsRef.set(
                {
                    registeredEventsPruneCursor: null,
                    registeredEventsPruneLastRunAt: admin.firestore.FieldValue.serverTimestamp(),
                    registeredEventsPruneScanned: 0,
                    registeredEventsPruneRemoved: 0,
                },
                { merge: true },
            );
            return null;
        }

        const batch = db.batch();
        let removed = 0;

        snap.docs.forEach((doc) => {
            const data = doc.data() || {};
            const expiry = calculateRegistrationExpiry(data);
            if (!expiry) return;

            if (expiry.getTime() < now.getTime()) {
                batch.delete(doc.ref);
                removed++;
            }
        });

        if (removed > 0) {
            await batch.commit();
        }

        const nextCursor = snap.docs[snap.docs.length - 1].ref.path;
        await settingsRef.set(
            {
                registeredEventsPruneCursor: nextCursor,
                registeredEventsPruneLastRunAt: admin.firestore.FieldValue.serverTimestamp(),
                registeredEventsPruneScanned: snap.docs.length,
                registeredEventsPruneRemoved: removed,
            },
            { merge: true },
        );

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
