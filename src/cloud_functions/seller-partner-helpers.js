'use strict';

const crypto = require('node:crypto');

const EVENT_TYPES = new Set([
    'INITIAL_PURCHASE', 'RENEWAL', 'CANCELLATION', 'UNCANCELLATION',
    'EXPIRATION', 'BILLING_ISSUE', 'PRODUCT_CHANGE', 'SUBSCRIPTION_PAUSED',
    'SUBSCRIPTION_EXTENDED', 'NON_RENEWING_PURCHASE', 'TRANSFER',
    'TEMPORARY_ENTITLEMENT_GRANT', 'REFUND', 'REFUND_REVERSED', 'TEST',
]);

function normalizeId(value) {
    return typeof value === 'string' ? value.trim() : '';
}

function documentId(value) {
    const id = normalizeId(value);
    return id && id.length <= 128 && !id.includes('/') && id !== '.' && id !== '..'
        && !/^\$RCAnonymousID:/i.test(id) ? id : null;
}

function normalizeCode(value) {
    return normalizeId(value).toUpperCase();
}

function key(value) {
    return crypto.createHash('sha256').update(value).digest('hex');
}

function authenticated(header, secret) {
    if (typeof secret !== 'string' || secret.length < 32 || typeof header !== 'string') return false;
    // Compare fixed-length digests, including for wrong-length credentials.
    const expected = crypto.createHash('sha256').update(`Bearer ${secret}`).digest();
    const actual = crypto.createHash('sha256').update(header).digest();
    return crypto.timingSafeEqual(expected, actual);
}

function milliseconds(value, required = false) {
    if (value == null && !required) return null;
    if (!Number.isSafeInteger(value) || value < 0 || value > 253402300799999) {
        throw new Error('invalid_timestamp');
    }
    return value;
}

function boundedString(value, max, required = false) {
    const result = normalizeId(value);
    if ((required && !result) || result.length > max) throw new Error('invalid_string');
    return result || null;
}

function identities(event) {
    const candidates = event.type === 'TRANSFER'
        ? [...(event.transferred_from || []), ...(event.transferred_to || [])]
        : [event.app_user_id, event.original_app_user_id, ...(event.aliases || [])];
    if (candidates.length > 100) throw new Error('too_many_aliases');
    return [...new Set(candidates.map(documentId).filter(Boolean))];
}

function parseEvent(body) {
    const raw = body && body.event;
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) throw new Error('invalid_event');
    for (const field of ['aliases', 'transferred_from', 'transferred_to']) {
        if (raw[field] != null && (!Array.isArray(raw[field]) || raw[field].some(v => typeof v !== 'string'))) {
            throw new Error('invalid_aliases');
        }
    }
    const event = {
        ...raw,
        id: boundedString(raw.id, 512, true),
        type: boundedString(raw.type, 80, true).toUpperCase(),
        environment: boundedString(raw.environment, 32, true).toUpperCase(),
        product_id: boundedString(raw.product_id, 512),
        store: boundedString(raw.store, 80),
        transaction_id: boundedString(raw.transaction_id, 512),
        original_transaction_id: boundedString(raw.original_transaction_id, 512),
        cancel_reason: boundedString(raw.cancel_reason, 80)?.toUpperCase() || null,
        event_timestamp_ms: milliseconds(raw.event_timestamp_ms, true),
        purchased_at_ms: milliseconds(raw.purchased_at_ms),
        expiration_at_ms: milliseconds(raw.expiration_at_ms),
    };
    if (!['PRODUCTION', 'SANDBOX'].includes(event.environment)) throw new Error('invalid_environment');
    event.userIds = identities(event);
    return event;
}

function activeRecord(data) {
    const status = normalizeId(data && data.status).toLowerCase();
    return Boolean(data && data.isActive === true && (!status || status === 'active'));
}

function resolveCode(codeDocuments, seller) {
    if (codeDocuments.length !== 1 || !activeRecord(codeDocuments[0])) return null;
    const sellerId = documentId(codeDocuments[0].sellerId);
    return sellerId && activeRecord(seller) ? sellerId : null;
}

function resolveUser(users, type) {
    if (type === 'TRANSFER') return { user: null, resolution: 'transfer_requires_review' };
    if (users.length !== 1) return { user: null, resolution: users.length ? 'ambiguous' : 'unresolved' };
    return { user: users[0], resolution: 'resolved' };
}

function reviewReason(event) {
    if (['REFUND', 'REFUND_REVERSED'].includes(event.type)) return 'refund_requires_review';
    if (event.type === 'CANCELLATION' && event.cancel_reason === 'CUSTOMER_SUPPORT') {
        return 'customer_support_cancellation_requires_review';
    }
    if (event.type === 'TRANSFER') return 'transfer_requires_review';
    return null;
}

function plan(product) {
    const lower = (product || '').toLowerCase();
    if (lower.includes('starter')) return 'starter';
    if (lower.includes('harmony100')) return 'harmony100';
    return product;
}

function nextStatus(previous, event, receivedAtMs) {
    if (previous && event.event_timestamp_ms <= previous.lastEventAt) return null;
    if (!EVENT_TYPES.has(event.type) || ['TRANSFER', 'TEST', 'REFUND', 'REFUND_REVERSED',
        'NON_RENEWING_PURCHASE', 'PRODUCT_CHANGE', 'TEMPORARY_ENTITLEMENT_GRANT'].includes(event.type)) return null;
    const expiresAt = event.expiration_at_ms ?? (previous ? previous.expiresAt : null);
    let active = previous ? previous.active : false;
    let willRenew = previous ? previous.willRenew : false;
    if (['INITIAL_PURCHASE', 'RENEWAL', 'UNCANCELLATION', 'SUBSCRIPTION_EXTENDED'].includes(event.type)) {
        active = expiresAt != null && expiresAt > receivedAtMs;
        willRenew = event.type === 'SUBSCRIPTION_EXTENDED' ? willRenew : true;
    } else if (event.type === 'EXPIRATION') {
        active = false;
        willRenew = false;
    } else if (['CANCELLATION', 'SUBSCRIPTION_PAUSED'].includes(event.type)) {
        // Cancellation/pausing is not proof of refund or immediate entitlement loss.
        active = expiresAt != null ? expiresAt > receivedAtMs : active;
        willRenew = false;
    }
    return {
        plan: plan(event.product_id) ?? (previous ? previous.plan : null),
        active, willRenew, expiresAt,
        lastEventAt: event.event_timestamp_ms,
        lastReceivedAt: receivedAtMs,
    };
}

function settlementEligible(event, risk) {
    return !risk && event.environment === 'PRODUCTION'
        && ['INITIAL_PURCHASE', 'RENEWAL'].includes(event.type)
        && Boolean(event.userId && event.sellerId && event.transactionId && event.store && event.product)
        && event.purchasedAt != null && event.periodType !== 'TRIAL';
}

function settlementInput(data) {
    if (!data || typeof data !== 'object' || Array.isArray(data)
        || Object.keys(data).some(k => !['eventId', 'accountingReference'].includes(k))) throw new Error('invalid_input');
    const eventId = boundedString(data.eventId, 512, true);
    const accountingReference = boundedString(data.accountingReference, 200, true);
    if (/[\x00-\x1f\x7f]/.test(accountingReference)) throw new Error('invalid_reference');
    return { eventId, accountingReference };
}

module.exports = {
    EVENT_TYPES, normalizeId, documentId, normalizeCode, key, authenticated,
    parseEvent, activeRecord, resolveCode, resolveUser, reviewReason,
    nextStatus, settlementEligible, settlementInput,
};