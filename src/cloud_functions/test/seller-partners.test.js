'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const h = require('../seller-partner-helpers');

const NOW = 1800000000000;
const raw = overrides => ({
    id: ' event-1 ', type: 'INITIAL_PURCHASE', environment: 'PRODUCTION',
    app_user_id: ' user-1 ', aliases: ['$RCAnonymousID:unknown'],
    product_id: 'starter_monthly', store: 'APP_STORE', transaction_id: 'tx-1',
    original_transaction_id: 'original-1', event_timestamp_ms: NOW,
    purchased_at_ms: NOW - 1000, expiration_at_ms: NOW + 100000,
    period_type: 'NORMAL', ...overrides,
});
const event = overrides => h.parseEvent({ event: raw(overrides) });

test('normalizes code, exact case-sensitive user IDs and anonymous IDs', () => {
    assert.equal(h.normalizeCode(' abC '), 'ABC');
    assert.equal(h.documentId(' UserA '), 'UserA');
    for (const id of ['', 'a/b', '..', '$RCAnonymousID:x', 123]) assert.equal(h.documentId(id), null);
    assert.deepEqual(event({ aliases: ['user-1', ' Other ', '$RCAnonymousID:x'] }).userIds, ['user-1', 'Other']);
});

test('auth fails closed for missing, wrong, short secrets and malformed Bearer headers', () => {
    const secret = 'a'.repeat(64);
    assert.equal(h.authenticated(`Bearer ${secret}`, secret), true);
    for (const header of [undefined, secret, `bearer ${secret}`, `Bearer ${secret} `, 'Bearer b']) {
        assert.equal(h.authenticated(header, secret), false);
    }
    assert.equal(h.authenticated('Bearer abc', 'abc'), false);
    assert.equal(h.authenticated('Bearer undefined', undefined), false);
});

test('rejects malformed event timestamps/environments/aliases and bounds', () => {
    for (const overrides of [
        { event_timestamp_ms: null }, { event_timestamp_ms: '123' },
        { expiration_at_ms: -1 }, { environment: 'unknown' },
        { aliases: 'user' }, { aliases: [42] }, { aliases: Array(101).fill('a') },
        { id: ' ' }, { id: 'x'.repeat(513) },
    ]) assert.throws(() => event(overrides));
});

test('rejects duplicate codes even if only one active, inactive code or seller', () => {
    const code = { sellerId: 'seller-1', isActive: true, status: 'active' };
    assert.equal(h.resolveCode([code], { isActive: true }), 'seller-1');
    assert.equal(h.resolveCode([code, { ...code, isActive: false }], { isActive: true }), null);
    assert.equal(h.resolveCode([{ ...code, status: 'inactive' }], { isActive: true }), null);
    assert.equal(h.resolveCode([code], { isActive: false }), null);
    assert.equal(h.resolveCode([code], { isActive: true, status: 'archived' }), null);
    assert.equal(h.resolveCode([code], { isActive: true, status: 'paused' }), null);
    assert.equal(h.resolveCode([code], null), null);
});

test('aliases resolve only a unique Firebase user; transfer never picks an owner', () => {
    const user = { id: 'one' };
    assert.equal(h.resolveUser([user], 'RENEWAL').user, user);
    assert.equal(h.resolveUser([], 'RENEWAL').resolution, 'unresolved');
    assert.equal(h.resolveUser([user, { id: 'two' }], 'RENEWAL').resolution, 'ambiguous');
    assert.equal(h.resolveUser([user], 'TRANSFER').user, null);
});

test('status preserves ordering, replay and unknown products; cancellation is not expiry', () => {
    const initial = h.nextStatus(null, event(), NOW);
    assert.equal(initial.plan, 'starter');
    assert.equal(initial.active, true);
    assert.equal(initial.willRenew, true);
    assert.equal(h.nextStatus(initial, event(), NOW), null);
    assert.equal(h.nextStatus(initial, event({ event_timestamp_ms: NOW - 1 }), NOW), null);
    const canceled = h.nextStatus(initial, event({ type: 'CANCELLATION', event_timestamp_ms: NOW + 1 }), NOW);
    assert.equal(canceled.active, true);
    assert.equal(canceled.willRenew, false);
    const expired = h.nextStatus(canceled, event({ type: 'EXPIRATION', event_timestamp_ms: NOW + 2 }), NOW);
    assert.equal(expired.active, false);
    assert.equal(h.nextStatus(null, event({ product_id: 'new_tier' }), NOW).plan, 'new_tier');
    assert.equal(h.nextStatus(null, event({ product_id: 'harmony100_monthly' }), NOW).plan, 'harmony100');
    for (const type of ['REFUND', 'REFUND_REVERSED', 'TRANSFER', 'TEST', 'UNKNOWN']) {
        assert.equal(h.nextStatus(initial, event({ type, event_timestamp_ms: NOW + 1 }), NOW), null);
    }
});

test('support cancellation/refunds require review but normal cancellation does not', () => {
    assert.equal(h.reviewReason(event({ type: 'CANCELLATION', cancel_reason: 'UNSUBSCRIBE' })), null);
    assert.ok(h.reviewReason(event({ type: 'CANCELLATION', cancel_reason: 'customer_support' })));
    assert.ok(h.reviewReason(event({ type: 'REFUND' })));
});

test('settlement is production initial/renewal, not trial, refund or risk; bounded input', () => {
    const record = {
        environment: 'PRODUCTION', type: 'INITIAL_PURCHASE', userId: 'u', sellerId: 's',
        transactionId: 't', store: 'APP_STORE', product: 'starter', purchasedAt: NOW,
    };
    assert.equal(h.settlementEligible(record, false), true);
    for (const patch of [
        { environment: 'SANDBOX' }, { type: 'CANCELLATION' }, { type: 'REFUND' },
        { periodType: 'TRIAL' }, { sellerId: null }, { transactionId: null },
    ]) assert.equal(h.settlementEligible({ ...record, ...patch }, false), false);
    assert.equal(h.settlementEligible(record, true), false);
    assert.deepEqual(h.settlementInput({ eventId: ' a ', accountingReference: ' REF ' }), { eventId: 'a', accountingReference: 'REF' });
    for (const data of [null, {}, { eventId: 'a', accountingReference: '' },
        { eventId: 'a', accountingReference: 'a'.repeat(201) },
        { eventId: 'a', accountingReference: 'a\nb' },
        { eventId: 'a', accountingReference: 'ok', amount: 1 }]) assert.throws(() => h.settlementInput(data));
});

// In-memory Firestore contract fixture: enforces all reads before writes and atomic commit.
// Not an emulator: production Firestore retries/rules need orchestrator smoke testing.
function harness() {
    const docs = new Map();
    const reference = path => ({ path, id: path.split('/').at(-1) });
    const snapshot = r => ({ ref: r, id: r.id, exists: docs.has(r.path), data: () => structuredClone(docs.get(r.path)) });
    const collection = name => ({
        doc: id => reference(`${name}/${id}`),
        where: (field, op, value) => ({
            limit: limit => ({ query: true, name, field, value, limit }),
        }),
    });
    const db = {
        collection,
        runTransaction: async fn => {
            const writes = [];
            const tx = {
                get: async r => {
                    assert.equal(writes.length, 0, 'transaction read after write');
                    if (!r.query) return snapshot(r);
                    const matches = [...docs].filter(([p, d]) => p.startsWith(`${r.name}/`) && d[r.field] === r.value)
                        .slice(0, r.limit).map(([p]) => snapshot(reference(p)));
                    return { size: matches.length, docs: matches };
                },
                create: (r, data) => { assert.equal(docs.has(r.path), false); writes.push([r.path, data, false]); },
                update: (r, data) => writes.push([r.path, data, true]),
                set: (r, data, options) => writes.push([r.path, data, Boolean(options && options.merge)]),
            };
            const result = await fn(tx);
            for (const [p, data, merge] of writes) docs.set(p, { ...(merge ? docs.get(p) : {}), ...data });
            return result;
        },
    };
    const firestore = () => db;
    firestore.FieldValue = { serverTimestamp: () => 'SERVER_TIMESTAMP' };
    class HttpsError extends Error { constructor(code, message) { super(message); this.code = code; } }
    const functions = {
        firestore: { document: () => ({ onWrite: fn => fn }) },
        runWith: () => ({ https: { onRequest: fn => fn } }),
        https: { onCall: fn => fn, HttpsError },
        logger: { info: () => {}, error: () => {} },
    };
    const api = require('../seller-partners')(functions, { firestore });
    const secret = 'fixture-secret-'.repeat(4);
    process.env.REVENUECAT_WEBHOOK_AUTH = secret;
    async function send(overrides, auth = `Bearer ${secret}`) {
        let code = 200;
        const res = { status: n => { code = n; return res; }, send: () => {}, json: () => {} };
        await api.revenueCatSellerWebhook({ method: 'POST', get: () => auth, body: { event: raw(overrides) } }, res);
        return code;
    }
    const put = (p, value) => docs.set(p, value);
    const all = name => [...docs].filter(([p]) => p.startsWith(`${name}/`)).map(([, d]) => d);
    const writeUser = async data => {
        put('users/user-1', data);
        await api.resolveSellerAttribution({ after: snapshot(reference('users/user-1')) });
    };
    return { api, docs, put, all, send, writeUser };
}

test('onWrite resolves code AFTER signup, preserves data and never reassigns/loops', async () => {
    const f = harness();
    f.put('seller_codes/c1', { normalizedCode: 'ABC', sellerId: 'seller-1', isActive: true });
    f.put('sellers/seller-1', { isActive: true });
    await f.writeUser({ name: 'kept', subscriptionPlan: 'legacy' });
    await f.writeUser({ name: 'kept', subscriptionPlan: 'legacy', assignedSellerCode: ' abc ' });
    const accepted = f.docs.get('users/user-1');
    assert.equal(accepted.assignedSellerId, 'seller-1');
    assert.equal(accepted.acceptedSellerCode, 'ABC');
    assert.equal(accepted.assignedSellerCode, ' abc ');
    assert.equal(accepted.subscriptionPlan, 'legacy');
    await f.writeUser({ ...accepted, assignedSellerCode: 'OTHER' });
    assert.equal(f.docs.get('users/user-1').assignedSellerId, 'seller-1');
});

test('onWrite refuses inactive/duplicate code, inactive seller and exact-only code matching', async () => {
    for (const variant of ['duplicate', 'inactive-code', 'inactive-seller', 'not-normalized']) {
        const f = harness();
        f.put('seller_codes/c1', { normalizedCode: variant === 'not-normalized' ? 'abc' : 'ABC', sellerId: 's', isActive: variant !== 'inactive-code' });
        f.put('sellers/s', { isActive: variant !== 'inactive-seller' });
        if (variant === 'duplicate') f.put('seller_codes/c2', { normalizedCode: 'ABC', sellerId: 's', isActive: false });
        await f.writeUser({ assignedSellerCode: 'abc' });
        assert.equal(f.docs.get('users/user-1').assignedSellerId, undefined);
    }
});

test('webhook auth, immutable replay, out-of-order history and sandbox separation', async () => {
    const f = harness();
    const legacy = { assignedSellerId: 'seller-1', subscriptionPlan: 'legacy', status: 'trial', isVip: true };
    f.put('users/user-1', legacy);
    assert.equal(await f.send({}, 'Bearer wrong'), 401);
    assert.equal(f.docs.size, 1);
    assert.equal(await f.send({}), 200);
    const before = structuredClone([...f.docs]);
    assert.equal(await f.send({ product_id: 'changed-replay' }), 200);
    assert.deepEqual([...f.docs], before);
    await f.send({ id: 'late', type: 'EXPIRATION', event_timestamp_ms: NOW - 100 });
    assert.equal(f.all('subscription_events').length, 2);
    assert.equal(f.all('seller_subscription_events').length, 2);
    assert.equal(f.all('partner_subscription_status')[0].lastEventAt, NOW);
    assert.equal(f.docs.get('seller_integration_config/revenuecat').lastEventAt, NOW);
    await f.send({ id: 'sandbox', environment: 'SANDBOX' });
    assert.equal(f.all('partner_subscription_status').length, 2);
    assert.deepEqual(f.docs.get('users/user-1'), legacy);
});

test('unknown aliases fail closed; ambiguous identities get history but no seller/status', async () => {
    const f = harness();
    await f.send({ app_user_id: 'unknown', aliases: ['missing'] });
    assert.equal(f.all('subscription_events')[0].resolution, 'unresolved');
    f.put('users/user-1', { assignedSellerId: 's' });
    f.put('users/user-2', { assignedSellerId: 's' });
    await f.send({ id: 'ambiguous', aliases: ['user-2'] });
    assert.equal(f.all('subscription_events')[1].resolution, 'ambiguous');
    assert.equal(f.all('seller_subscription_events').length, 0);
    assert.equal(f.all('partner_subscription_status').length, 0);
    await f.send({ id: 'unique', app_user_id: '$RCAnonymousID:old', aliases: ['missing', 'user-1'] });
    assert.equal(f.all('subscription_events')[2].userId, 'user-1');
});

test('settlement requires active admin, dedups purchase, audits and blocks refunds even out-of-order', async () => {
    const f = harness();
    f.put('users/user-1', { assignedSellerId: 's' });
    await f.send({});
    const input = { eventId: 'event-1', accountingReference: 'BANK-REF' };
    const context = { auth: { uid: 'admin' } };
    await assert.rejects(f.api.recordSellerPartnerSettlement(input, {}), { code: 'unauthenticated' });
    await assert.rejects(f.api.recordSellerPartnerSettlement(input, context), { code: 'permission-denied' });
    f.put('admin_users/admin', { isActive: true });
    assert.equal((await f.api.recordSellerPartnerSettlement(input, context)).recorded, true);
    assert.equal((await f.api.recordSellerPartnerSettlement(input, context)).recorded, false);
    assert.equal(f.all('seller_partner_settlements')[0].recordedBy, 'admin');
    await assert.rejects(f.api.recordSellerPartnerSettlement({ ...input, accountingReference: 'other' }, context), { code: 'already-exists' });
    await f.send({ id: 'same-tx', type: 'RENEWAL' });
    assert.equal((await f.api.recordSellerPartnerSettlement({ ...input, eventId: 'same-tx' }, context)).recorded, false);
    await f.send({ id: 'refund', type: 'CANCELLATION', cancel_reason: 'CUSTOMER_SUPPORT', event_timestamp_ms: NOW - 1000 });
    await assert.rejects(f.api.recordSellerPartnerSettlement(input, context), { code: 'failed-precondition' });
    assert.equal(f.all('seller_partner_settlements').length, 1, 'audit history retained after reversal');
    const g = harness();
    g.put('users/user-1', { assignedSellerId: 's' });
    g.put('admin_users/admin', { isActive: true });
    await g.send({ id: 'refund-first', type: 'REFUND' });
    await g.send({});
    await assert.rejects(g.api.recordSellerPartnerSettlement(input, context), { code: 'failed-precondition' });
});

test('transfer stores each attributed seller audit without selecting a user; blocks settlement', async () => {
    const f = harness();
    f.put('users/user-1', { assignedSellerId: 's1' });
    f.put('users/user-2', { assignedSellerId: 's2' });
    f.put('admin_users/admin', { isActive: true });
    await f.send({ id: 'transfer', type: 'TRANSFER', transferred_from: ['user-1'], transferred_to: ['user-2'] });
    assert.equal(f.all('subscription_events')[0].userId, null);
    assert.equal(f.all('seller_subscription_events').length, 2);
    assert.equal(f.all('partner_subscription_status').length, 0);
    await f.send({});
    await assert.rejects(f.api.recordSellerPartnerSettlement({ eventId: 'event-1', accountingReference: 'REF' }, { auth: { uid: 'admin' } }), { code: 'failed-precondition' });
});

test('transfer to a not-yet-created Firebase profile still blocks later settlement', async () => {
    const f = harness();
    f.put('users/user-1', { assignedSellerId: 's' });
    f.put('admin_users/admin', { isActive: true });
    await f.send({ id: 'transfer', type: 'TRANSFER', transferred_from: ['user-1'], transferred_to: ['future-user'] });
    f.put('users/future-user', { assignedSellerId: 's' });
    await f.send({ id: 'future-purchase', app_user_id: 'future-user' });
    await assert.rejects(f.api.recordSellerPartnerSettlement({ eventId: 'future-purchase', accountingReference: 'REF' }, { auth: { uid: 'admin' } }), { code: 'failed-precondition' });
});

test('refund without original lineage blocks user, unknown types audited, invalid body leaves config untouched', async () => {
    const f = harness();
    f.put('users/user-1', { assignedSellerId: 's' });
    f.put('admin_users/admin', { isActive: true });
    assert.equal(await f.send({ event_timestamp_ms: 'invalid' }), 400);
    assert.equal(f.docs.has('seller_integration_config/revenuecat'), false);
    await f.send({ id: 'future-event', type: 'FUTURE_RC_EVENT' });
    assert.equal(f.all('seller_subscription_events')[0].type, 'FUTURE_RC_EVENT');
    assert.equal(f.all('partner_subscription_status').length, 0);
    await f.send({ id: 'refund', type: 'REFUND', original_transaction_id: null, transaction_id: 'different-tx' });
    await f.send({});
    await assert.rejects(f.api.recordSellerPartnerSettlement({ eventId: 'event-1', accountingReference: 'REF' }, { auth: { uid: 'admin' } }), { code: 'failed-precondition' });
});

test('rules source safeguards attribution and all backend collections without recursive write override', () => {
    const fs = require('node:fs');
    const path = require('node:path');
    const rules = fs.readFileSync(path.join(__dirname, '../../admin/firestore.rules'), 'utf8');
    const users = rules.slice(rules.indexOf('match /users/{userId}'), rules.indexOf('// My Harmony Vault'));
    assert.match(users, /allow create: if !request\.resource\.data\.keys\(\)\.hasAny/);
    assert.match(users, /allow update: if !request\.resource\.data\.diff\(resource\.data\)\.affectedKeys\(\)\.hasAny/);
    assert.match(users, /allow delete: if !resource\.data\.keys\(\)\.hasAny/);
    assert.doesNotMatch(users, /allow.*write: if true/);
    for (const field of ['assignedSellerId', 'acceptedSellerCode', 'sellerAttributedAt']) {
        assert.equal(users.split(`'${field}'`).length - 1, 3);
    }
    for (const collection of ['subscription_events', 'seller_subscription_events', 'seller_partner_settlements',
        'seller_integration_config', 'partner_subscription_status', 'partner_subscription_risks',
        'seller_subscription_transaction_reviews']) {
        const section = rules.slice(rules.indexOf(`match /${collection}/`));
        assert.match(section.split('}')[1], /allow read: if isActiveAdmin\(\);\s+allow write: if false;/);
    }
    for (const collection of ['sellers', 'seller_codes']) {
        const section = rules.slice(rules.indexOf(`match /${collection}/`));
        assert.match(section.split('}')[1], /allow read, write: if isActiveAdmin\(\);/);
    }
    // Audit every recursive match, not just the final fallback (allow rules OR together).
    const recursive = rules.match(/match[^\n]*\*\*[^\n]*\{[\s\S]*?\n    \}/g);
    assert.equal(recursive.length, 3);
    assert.ok(recursive.some(section => section.includes('support_inbox')));
    assert.ok(recursive.some(section => section.includes('/messages/')));
    assert.ok(recursive.some(section => /allow read, write: if false;/.test(section)));
});