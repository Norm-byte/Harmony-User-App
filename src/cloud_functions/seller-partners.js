'use strict';

const helpers = require('./seller-partner-helpers');
const { defineSecret } = require('firebase-functions/params');
const webhookAuth = defineSecret('REVENUECAT_WEBHOOK_AUTH');

// All writes here are Admin SDK only. No financial calculation or legacy billing writes.
module.exports = function sellerPartners(functions, admin) {
    const db = admin.firestore();
    const timestamp = () => admin.firestore.FieldValue.serverTimestamp();
    const ref = (collection, id) => db.collection(collection).doc(id);
    const riskKey = (env, userId) => helpers.key(JSON.stringify([env, userId]));
    const transactionKey = event => helpers.key(JSON.stringify([
        event.environment, event.store, event.original_transaction_id || event.transaction_id,
    ]));

    const resolveSellerAttribution = functions.firestore.document('users/{userId}').onWrite(async change => {
        if (!change.after.exists) return null;
        const after = change.after.data();
        if (after.assignedSellerId || !helpers.normalizeCode(after.assignedSellerCode)) return null;
        const outcome = await db.runTransaction(async tx => {
            const user = await tx.get(change.after.ref);
            if (!user.exists || user.data().assignedSellerId) return 'already_attributed';
            const code = helpers.normalizeCode(user.data().assignedSellerCode);
            if (!code || code.length > 128) return 'invalid_code';
            // Query all statuses: an inactive duplicate must not make a code unambiguous.
            const codes = await tx.get(db.collection('seller_codes').where('normalizedCode', '==', code).limit(2));
            if (codes.size !== 1) return 'missing_or_duplicate_code';
            const sellerId = helpers.documentId(codes.docs[0].data().sellerId);
            if (!sellerId) return 'invalid_seller';
            const seller = await tx.get(ref('sellers', sellerId));
            if (!helpers.resolveCode(codes.docs.map(doc => doc.data()), seller.exists ? seller.data() : null)) {
                return 'inactive_code_or_seller';
            }
            tx.update(user.ref, {
                assignedSellerId: sellerId,
                acceptedSellerCode: code,
                sellerAttributedAt: timestamp(),
            });
            return 'attributed';
        });
        functions.logger.info('seller_attribution', { outcome });
        return null;
    });

    async function ingest(event) {
        // Stable receipt time for every retry within this invocation.
        const receivedAtMs = Date.now();
        const eventRef = ref('subscription_events', helpers.key(event.id));
        return db.runTransaction(async tx => {
            const existing = await tx.get(eventRef);
            if (existing.exists) return 'duplicate';
            const snapshots = await Promise.all(event.userIds.map(id => tx.get(ref('users', id))));
            const users = snapshots.filter(s => s.exists).map(s => ({ id: s.id, data: s.data() }));
            const { user, resolution } = helpers.resolveUser(users, event.type);
            const sellerId = user ? helpers.documentId(user.data.assignedSellerId) : null;
            const userId = user ? user.id : null;
            const statusRef = userId ? ref('partner_subscription_status', riskKey(event.environment, userId)) : null;
            const status = statusRef ? await tx.get(statusRef) : null;
            const reason = helpers.reviewReason(event);
            const ledgerRef = (event.transaction_id || event.original_transaction_id)
                ? ref('seller_subscription_transaction_reviews', transactionKey(event)) : null;
            // Every read precedes every write (including duplicate and reversal checks).
            const ledger = ledgerRef ? await tx.get(ledgerRef) : null;
            // Retain transfer/reversal risk even for Firebase IDs whose profiles do not
            // exist yet. A later signup must not bypass the transfer review marker.
            const riskUsers = reason && (event.type === 'TRANSFER' || !event.original_transaction_id)
                ? event.userIds.map(id => ({ id })) : [];
            const risks = await Promise.all(riskUsers.map(u => tx.get(ref(
                'partner_subscription_risks', riskKey(event.environment, u.id),
            ))));
            const configRef = ref('seller_integration_config', 'revenuecat');
            const config = await tx.get(configRef);
            const record = {
                eventId: event.id, type: event.type, environment: event.environment,
                product: event.product_id, store: event.store, userId, sellerId,
                purchasedAt: event.purchased_at_ms, expiresAt: event.expiration_at_ms,
                receivedAt: timestamp(), receivedAtMs, lastEventAt: event.event_timestamp_ms,
                transactionId: event.transaction_id, originalTransactionId: event.original_transaction_id,
                transactionReviewId: ledgerRef ? ledgerRef.id : null,
                cancelReason: event.cancel_reason,
                periodType: helpers.normalizeId(event.period_type).toUpperCase() || null,
                resolution, reviewReason: reason,
                identityCandidates: event.userIds,
                transferredFrom: event.type === 'TRANSFER'
                    ? [...new Set((event.transferred_from || []).map(helpers.documentId).filter(Boolean))] : [],
                transferredTo: event.type === 'TRANSFER'
                    ? [...new Set((event.transferred_to || []).map(helpers.documentId).filter(Boolean))] : [],
            };
            tx.create(eventRef, record);
            const attributed = event.type === 'TRANSFER'
                ? [...new Set(users.map(u => helpers.documentId(u.data.assignedSellerId)).filter(Boolean))]
                : sellerId ? [sellerId] : [];
            for (const id of attributed) {
                tx.create(ref('seller_subscription_events', helpers.key(JSON.stringify([event.id, id]))), {
                    ...record, sellerId: id,
                    affectedUserIds: event.type === 'TRANSFER'
                        ? users.filter(u => u.data.assignedSellerId === id).map(u => u.id) : [],
                });
            }
            if (reason && ledgerRef) {
                // A later purchase/replay must never clear a prior reversal/review marker.
                tx.set(ledgerRef, {
                    blocked: true, environment: event.environment, reason,
                    firstEventId: ledger.exists ? ledger.data().firstEventId : event.id,
                    lastEventId: event.id, updatedAt: timestamp(),
                }, { merge: true });
            }
            riskUsers.forEach((u, i) => {
                // Unknown transaction lineage: conservatively block settlement for this user.
                // Transfers always require review; refunds with known lineage block that lineage only.
                tx.set(risks[i].ref, {
                    userId: u.id, environment: event.environment, blocked: true, reason,
                    firstEventId: risks[i].exists ? risks[i].data().firstEventId : event.id,
                    lastEventId: event.id, updatedAt: timestamp(),
                }, { merge: true });
            });
            const next = sellerId ? helpers.nextStatus(status && status.exists ? status.data() : null, event, receivedAtMs) : null;
            if (next) tx.set(statusRef, {
                ...next, userId, sellerId, environment: event.environment,
            }, { merge: true });
            // Only authenticated, new events update configuration; replay is a no-op.
            tx.set(configRef, {
                configured: true, updatedAt: timestamp(),
                lastEventAt: Math.max(config.exists ? config.data().lastEventAt || 0 : 0, event.event_timestamp_ms),
            }, { merge: true });
            return resolution;
        });
    }

    const revenueCatSellerWebhook = functions.runWith({ secrets: [webhookAuth] }).https.onRequest(async (req, res) => {
        if (req.method !== 'POST') return res.status(405).send('Method not allowed');
        if (!helpers.authenticated(req.get('authorization'), webhookAuth.value())) {
            return res.status(401).send('Unauthorized');
        }
        let event;
        try {
            event = helpers.parseEvent(req.body);
        } catch (_) {
            return res.status(400).send('Invalid event');
        }
        try {
            const outcome = await ingest(event);
            functions.logger.info('seller_revenuecat_event', { outcome });
            return res.status(200).json({ accepted: true });
        } catch (_) {
            functions.logger.error('seller_revenuecat_event_failed');
            return res.status(500).send('Retry later');
        }
    });

    const recordSellerPartnerSettlement = functions.https.onCall(async (data, context) => {
        if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Authentication required.');
        let input;
        try {
            input = helpers.settlementInput(data);
        } catch (_) {
            throw new functions.https.HttpsError('invalid-argument', 'Provide eventId and accountingReference (1–200 characters).');
        }
        return db.runTransaction(async tx => {
            const adminRecord = await tx.get(ref('admin_users', context.auth.uid));
            if (!adminRecord.exists || adminRecord.data().isActive !== true) {
                throw new functions.https.HttpsError('permission-denied', 'Active admin required.');
            }
            const event = await tx.get(ref('subscription_events', helpers.key(input.eventId)));
            if (!event.exists) throw new functions.https.HttpsError('not-found', 'Event not found.');
            const record = event.data();
            const risk = record.userId ? await tx.get(ref('partner_subscription_risks', riskKey(record.environment, record.userId))) : null;
            const review = record.transactionReviewId ? await tx.get(ref('seller_subscription_transaction_reviews', record.transactionReviewId)) : null;
            if (!helpers.settlementEligible(record, (risk && risk.exists && risk.data().blocked) || (review && review.exists && review.data().blocked))) {
                throw new functions.https.HttpsError('failed-precondition', 'Event is not eligible or requires reversal/transfer review.');
            }
            // Deduplicate both event retries and distinct RevenueCat events for the same purchase.
            const settlementId = helpers.key(JSON.stringify([record.environment, record.store, record.transactionId]));
            const settlementRef = ref('seller_partner_settlements', settlementId);
            const existing = await tx.get(settlementRef);
            if (existing.exists) {
                const previous = existing.data();
                if (previous.accountingReference !== input.accountingReference || previous.sellerId !== record.sellerId || previous.userId !== record.userId) {
                    throw new functions.https.HttpsError('already-exists', 'Transaction already recorded with different accounting details.');
                }
                return { settlementId, recorded: false };
            }
            tx.create(settlementRef, {
                eventId: record.eventId, subscriptionEventId: event.id,
                sellerId: record.sellerId, userId: record.userId,
                type: record.type, environment: record.environment,
                product: record.product, store: record.store, transactionId: record.transactionId,
                accountingReference: input.accountingReference,
                recordedBy: context.auth.uid, recordedAt: timestamp(),
            });
            return { settlementId, recorded: true };
        });
    });

    return { resolveSellerAttribution, revenueCatSellerWebhook, recordSellerPartnerSettlement };
};