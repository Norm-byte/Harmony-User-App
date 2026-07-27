# Seller Management Method (Admin) + RevenueCat Notes

## Purpose
This method defines how Harmony tracks seller-attributed subscribers, validates promo/referral codes, and calculates seller residual estimates in-house from Firestore.

## Core Rules
- Promo/referral input is optional for user signup.
- Only recognized, active seller codes are stored.
- Unknown text is ignored and never persisted as seller attribution.
- Seller metrics are visible in the admin Sellers tab.
- Seller payout rates are configurable globally, per country, and per seller.

## Data Model
### sellers collection
Each document stores seller profile and payout defaults.

Suggested fields:
- name
- email
- phone
- country
- isActive
- status
- defaultRate (0.00 to 1.00)
- notes
- createdAt
- updatedAt

### seller_codes collection
Each document stores one code. Sellers can have multiple codes.

Suggested fields:
- sellerId
- code
- normalizedCode
- isActive
- status
- createdAt
- updatedAt

### users collection (attribution fields)
Written only when code is valid and active.

Fields:
- assignedSellerId
- assignedSellerCode
- assignedSellerCodeNormalized
- assignedSellerAt

### Existing subscription fields in users
Used for residual visibility and in-house estimates:
- status
- subscriptionPlan
- willRenew
- renewalDate
- isVip

## Signup Flow
1. User enters Promo/Referral code (optional).
2. App normalizes value (uppercase/trim).
3. App checks seller_codes for matching normalizedCode/code.
4. If valid and active:
   - save seller attribution fields in users doc
   - set RevenueCat subscriber attributes for seller id/code
5. If invalid or inactive:
   - do nothing
   - do not store raw text

## Admin Sellers Tab (Current Scope)
- Create/update seller profile
- Active toggle per seller
- Activate/deactivate all sellers
- Delete seller
- Create/attach seller codes
- Active toggle per code
- Delete code
- Search sellers
- Country dropdown filter
- Date-range picker for residual views
- In-house residual metrics per seller
- Copy report JSON for export/print workflows

## Residual Calculation (In-House)
Current estimate logic:
- Identify users attributed to seller
- Count active subscribers (status == active)
- Count willRenew
- Count paid-monthly style plans
- Estimate gross by plan (Starter/Harmony 100 mapping)
- Apply configured rate to estimate residual

Formula:
- residualEstimate = grossEstimate * appliedRate

## Rate Strategy
- Global default rate in seller_commission_settings/global
- Country-specific override in seller_country_rates/{CC}
- Seller-specific default rate in sellers/{sellerId}.defaultRate

Recommended priority order:
1. Seller-specific country override
2. Seller default rate
3. Global default rate

## RevenueCat Integration Guidance
You can keep operations in-house while still using RevenueCat as the payment truth source.

Recommended:
1. Continue syncing user subscription summary fields (already in app flow).
2. Add RevenueCat webhook ingestion to Cloud Functions for payout-grade audit trails.
3. Write normalized webhook events to Firestore (subscription_events).
4. Keep admin tab reading Firestore only (no manual RevenueCat console work).

Why:
- App-side sync gives quick visibility.
- Webhooks provide authoritative event history (renewal, cancellation, refund).
- Firestore becomes your internal ledger and reporting source.

## Operator Security
- Sellers tab is permission-gated via seller_management permission key.
- Super admins retain full access.
- Non-authorized operators are blocked by LockedTabWrapper.

## Admin Permission Key
- seller_management

## Operational Checklist
Before payout run:
1. Confirm seller active status.
2. Confirm code active status.
3. Confirm date window.
4. Confirm rate policy (global/country/seller).
5. Export and archive report copy.
6. Perform payment off-app.

## Notes
- This method keeps garbage promo input out of Firestore attribution fields.
- This method supports one seller owning multiple codes.
- This method supports future daily rollups if scale requires cheaper aggregation.
