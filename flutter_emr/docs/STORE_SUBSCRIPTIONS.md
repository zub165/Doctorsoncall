# Store subscriptions (3 plans) + Stripe for extra visits

## Payment split

| What | How patients pay |
|------|------------------|
| **Basic / Gold / Premium** (monthly) | **Apple App Store** or **Google Play** — direct `in_app_purchase` (no RevenueCat) |
| **Extra visits** (beyond plan allowance) | **Stripe** — doctor consultation invoices in **Client → Doctor bills & pay** |
| **Web** (optional) | **Stripe Checkout** via `POST /api/billing/checkout/` with `platform=web` |

**Mobile:** after purchase, app calls `POST /api/billing/verify-store/` with receipt data. **No** RevenueCat keys in the app build.

## Django plans (must match stores)

| Plan | Visits/mo | App Store / Play product id | Entitlement field (`revenuecat_entitlement_id`) |
|------|-----------|----------------------------|------------------------------------------------|
| Basic | **1** | `doc_basic_monthly` | `basic` |
| Gold | **3** | `doc_gold_monthly` | `gold` |
| Premium | **5** | `doc_premium_monthly` | `premium` |

DB column names still say `revenuecat_*` for history; they hold **store product id** and **entitlement** only.

Seed: `GET /api/plans/?fixture=1` or Admin → Plans.

## App Store Connect

| Level | Product ID | Reference name (display only) |
|-------|------------|-------------------------------|
| 1 | `doc_basic_monthly` | `doc_basic_monthly` |
| 2 | `doc_gold_monthly` | `doc_gold_monthly` |
| 3 | `doc_premium_monthly` | `doc_enterprise_monthly` is OK |

Complete subscription metadata and pricing in Connect before testing.

## Google Play Console

Create the same three **subscription** product IDs.

## Server (VPS `.env`)

| Variable | Purpose |
|----------|---------|
| `APPLE_SHARED_SECRET` | Verify iOS receipts in `billing/verify-store/` |
| `STORE_VERIFY_STRICT` | `1` = reject unverified receipts in production |
| `STRIPE_*` | Doctor bills, web checkout, Connect |

Legacy `REVENUECAT_WEBHOOK_SECRET` + `POST /api/billing/webhook/` are optional and unused by the mobile app.

## Release build

```bash
./scripts/flutter_run_production_api.sh build
```

Uses `EMR_API_BASE_URL` from `.env` only — no RevenueCat dart-defines.

## Patient app flow

**Client → Plan tab**

- **Subscribe with App Store / Google Play** on each plan
- **Restore purchases** → verify-store for each restored product
- **Extra visits & doctor bills** → Stripe only

Implementation: `lib/services/store_purchase_service.dart`, `_PlanTab` in `client_hub_screen.dart`.
