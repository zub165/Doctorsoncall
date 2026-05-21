# How billing works in the app

**EMR API:** `https://api.docsoncalls.com/api/` · **Auth:** `Authorization: Token <token>`

## 1. Load plans

`GET /api/plans/`

Each plan includes `id`, `plan_name`, `price`, `number_appointments`, `revenuecat_product_id`, `revenuecat_entitlement_id`.

**VPS (once):** `python manage.py sync_store_plans`

| Plan | Visits/month | Product ID |
|------|--------------|------------|
| Basic | 1 | `doc_basic_monthly` |
| Gold | 3 | `doc_gold_monthly` |
| Premium | **5** (not unlimited) | `doc_premium_monthly` |

(App Store reference name `doc_enterprise_monthly` is display-only; product id stays `doc_premium_monthly`.)

Plans include booking **available doctors** on the platform (Discovery / Book appointment). Licensed clinicians can **join** via Provider application; optional **volunteer online visits** on apply.

## 2. Current subscription + visit allowance

`GET /api/billing/status/`

Response:

- `active` — current subscription or `null`
- `visit_allowance` — `visits_remaining`, `covered_visit_available`, `plan_name`, etc.

**Flutter:** Plan tab shows **VisitAllowanceCard** and current plan (not only `active`).

## 3. Subscribe

`POST /api/billing/checkout/`  
`{ "plan_id": 4, "platform": "apple" | "android" | "web" }`

| Platform | Backend returns | Frontend |
|----------|-----------------|----------|
| `apple` / `android` | `{ product_id, entitlement_id, plan_id, ... }` | `in_app_purchase` with `product_id`, then `POST /billing/verify-store/` |
| `web` | `{ url }` | Open Stripe Checkout (`launchUrl`) |

**Mobile:** App Store / Google Play only (no RevenueCat). After purchase, send receipt to `POST /api/billing/verify-store/`.

**Secrets:** Never put Stripe secret, Apple shared secret, or MyWaitime keys in the app.

## 4. After booking

`POST /api/appointments/` → `billing_hint`

Show `extra_visit_note`, `visit_allowance`, and link to **My bills** when not covered.

## 5. Pay doctor invoice (extra visit)

| Method | Path |
|--------|------|
| List | `GET /api/billing/patient/bills/` |
| Pay | `POST /api/billing/patient/pay-bill/` `{ "transaction_id": 123 }` → `{ "url" }` → Stripe |

## 6. Verify store purchase (server)

`POST /api/billing/verify-store/` — body: `plan_id`, `platform`, `product_id`, `purchase_id`, `verification_data`, …

VPS: set `APPLE_SHARED_SECRET` for real iOS receipt checks. Optional legacy webhook: `POST /api/billing/webhook/` (RevenueCat; not used by app).

## 7. Discovery (providers by country)

| Endpoint | Notes |
|----------|--------|
| `GET /api/countries/` | |
| `GET /api/specialities/` | |
| `GET /api/providers/` | Includes `country_id`, `country_name` when API deployed |

## Ops checklist

| Item | Status |
|------|--------|
| App Store products (`doc_basic_monthly`, `doc_gold_monthly`, `doc_premium_monthly`) | You — fix Missing Metadata |
| Django plans + product IDs | `migrate` + `sync_store_plans` on VPS |
| `APPLE_SHARED_SECRET` on VPS | iOS receipt verification |
| App built with production API | `./scripts/flutter_run_production_api.sh build` |
| `country_id` on providers | Deploy latest Django |

## One-liner (Slack)

EMR: `api.docsoncalls.com/api/` + Token. Plans: `GET /plans/`, mobile: App Store/Play + `verify-store`, web: Stripe checkout. Extra visits: Stripe doctor bills. Hospitals: `api.mywaitime.com/api/`.

## Local dev

```bash
flutter run --dart-define=EMR_API_BASE_URL=http://127.0.0.1:8012/api/
# Android emulator: http://10.0.2.2:8012/api/
# Maps: https://api.mywaitime.com/api/
```
