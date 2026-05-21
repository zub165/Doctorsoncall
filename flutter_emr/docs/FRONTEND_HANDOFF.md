# Doctors On Call — Flutter frontend spec

Handoff for the mobile team. Backend: `https://api.docsoncalls.com/api/` (nginx → gunicorn `:8012`).

**One line:** Monthly plans = **App Store / Google Play** (`in_app_purchase`) + `POST /api/billing/verify-store/`. Extra visits & web = **Stripe**. No RevenueCat in the app.

---

## Not in this repo (dashboard / mobile owner)

| Item | Owner |
|------|--------|
| App Store Connect + Play Console — 3 subscription product IDs | Mobile / product |
| `APPLE_SHARED_SECRET` in VPS `.env` | Ops |
| Stripe webhook → `https://api.docsoncalls.com/api/billing/stripe-webhook/` | Stripe Dashboard |

### Sanity check after a real purchase

1. Patient logs in (Token auth).
2. Subscribe on Plan tab → store purchase → app calls `POST /api/billing/verify-store/`.
3. `GET /api/billing/status/` → `active` + `visit_allowance` (1 / 3 / 5 visits).

---

## API bases (compile-time)

| Define | Production | Local simulator |
|--------|------------|-----------------|
| `EMR_API_BASE_URL` | `https://api.docsoncalls.com/api/` | `http://127.0.0.1:8012/api/` |
| `MAPS_API_BASE_URL` | `https://api.mywaitime.com/api/` | `http://127.0.0.1:3015/api/` |
| `API_USER_ME_PATH` | `user-data/` | same |

**Scripts**

- Production / TestFlight: `./scripts/flutter_run_production_api.sh`
- Local sim (EMR 8012 + maps 3015): `./scripts/flutter_run_ios_simulator_local_api.sh`

**Headers:** `Authorization: Token <token>`, `Accept` / `Content-Type: `application/json`

**Envelope:** `{ "status": "success", "data": … }` — use `ApiEnvelope` helpers (repo).

Use `EmergencyApiClient` for EMR; `EmergencyApiClient.maps()` for hospitals only.

---

## 1. Store subscriptions (direct IAP)

**Not Stripe** for monthly plans. Stripe = doctor bills + optional web checkout.

### Plans list (API done; UI must match)

`GET /api/plans/` → **exactly 3 plans** (no `?all=1` on patient app).

Admin only: `GET /api/plans/?all=1` (staff token).

| UI label | Visits/mo | `revenuecat_product_id` | `revenuecat_entitlement_id` |
|----------|-----------|-------------------------|-----------------------------|
| Basic | 1 | `doc_basic_monthly` | `basic` |
| Gold | 3 | `doc_gold_monthly` | `gold` |
| Premium | 5 | `doc_premium_monthly` | `premium` |

Show: `plan_name`, `price`, `duration`, `number_appointments`, product id (debug/support).

Copy: plans include **available doctors**; doctors can **join** / **volunteer online visits** via Provider application.

### Subscribe flow

1. `in_app_purchase` via `lib/services/store_purchase_service.dart`.
2. Plan tab subscribe:
   - Resolve `product_id` from plan row or `POST /api/billing/checkout/` (`platform`: `apple` | `android`).
   - `StorePurchaseService.purchaseProductId(product_id)`.
   - `POST /api/billing/verify-store/` with receipt fields.
3. Refresh `GET /api/billing/status/`.
4. **Restore purchases** → restore in store, verify-store per product, refresh status.

**Do not** use `platform: "web"` on mobile for plans.

**Repo status:** `_PlanTab` in `client_hub_screen.dart` — wired; needs live products in App Store Connect / Play Console and `APPLE_SHARED_SECRET` on VPS for strict iOS verify.

### Billing status

`GET /api/billing/status/` → parse:

- `data.active` — current subscription (if any)
- `data.visit_allowance`:
  - `has_subscription`, `plan_name`
  - `visits_included`, `visits_used_this_month`, `visits_remaining`
  - `covered_visit_available` (bool)

Show on **Client → Plan** and before booking (`VisitAllowanceCard`).

### Build defines

```bash
--dart-define=EMR_API_BASE_URL=https://api.docsoncalls.com/api/
```

No RevenueCat dart-defines. VPS: `APPLE_SHARED_SECRET`, `STRIPE_*`.

---

## 2. Stripe doctor visits (15%) — mostly wired; polish UX

Separate from store plans. Extra/paid visits after plan allowance.

| Role | Screen | API | Status |
|------|--------|-----|--------|
| Patient | Client → Doctor bills & pay / drawer | `GET billing/patient/bills/`, `POST billing/patient/pay-bill/` | Done — open `url` in browser |
| Patient | `patient_billing_screen.dart` | same | Done |
| Doctor | Drawer → Doctor billing & Stripe | `GET billing/doctor/summary/`, `POST billing/doctor/stripe-connect/` | Done — `doctor_billing_screen.dart` |
| Doctor | Patients list → Send invoice | `POST billing/doctor/create-invoice/` | Done |
| Doctor | Complimentary visit | `POST billing/doctor/complimentary-visit/` | Done |

**Frontend should add / improve:**

- Short copy on Plan tab: “Included visits = App Store/Play plan. Extra doctor bills = Stripe.” (**partially done**)
- Doctor summary: show `commission_percent` (15) from summary (**done** in doctor billing screen)
- After invoice: tell patient to open Billing & Invoices
- Handle errors: Connect not onboarded, empty `url`, `501` Stripe not configured
- **Do not** use Stripe Checkout on mobile for monthly plans

**Server:** `PLATFORM_COMMISSION_PERCENT=15` in `django_emr/.env`; split on `POST billing/doctor/create-invoice/`.

---

## 3. Appointments + billing hint (done; keep)

`POST /api/appointments/` response may include `billing_hint`:

- `visit_allowance` — same shape as billing status

Use on book flow (`book_appointment_screen.dart`) — keep in sync with Plan tab.

---

## 4. Hospitals (done; verify behavior)

Load order (with GPS):

1. `GET {EMR}/hospitals/search/?lat=&lon=`
2. `GET {MAPS}/hospitals/search/?lat=&lon=`
3. Fallback `GET {EMR}/hospitals/?lat=&lon=` filtered to ~80 km

Filter pins/list to ~80 km. Catalog fallback banner only if both live searches fail.

Parse distance: `distance_km`, `distance_miles`, `distance_m`.

Local script sets both API URLs. See `docs/HOSPITALS_TAB_FRONTEND.md`.

---

## 5. Discovery / doctors (done; verify)

- `GET /api/countries/`, `/specialities/`, `/providers/`
- Provider rows include `country_id`, `country_name` (after deploy)
- Country → filter doctors UX in `discovery_screen.dart`
- Provider apply: `provider_apply_screen.dart` (Scaffold + volunteer toggle)

---

## 6. Admin (done)

- Plans CRUD: `GET /api/plans/?all=1` in admin hub only
- Other admin lists unchanged

---

## 7. Priority backlog (ordered)

| P | Task | Notes |
|---|------|--------|
| P0 | Sandbox IAP + `verify-store` on VPS | App Store / Play test accounts |
| P0 | Plan tab: 3 plans + visit allowance from `billing/status` | API filters to 3 store plans |
| P0 | `APPLE_SHARED_SECRET` on VPS | iOS receipt verification |
| P1 | Clear UX split: Plan = store, Invoices = Stripe | Copy on Plan tab |
| P1 | Doctor transactions list UI | `GET billing/doctor/transactions/` — API exists |
| P2 | Bundle id `com.doctoroncall.emr` (iOS/Android) | Confirm in Xcode / Gradle |
| P2 | Pull-to-refresh on Plan after purchase | |

---

## 8. Copy-paste API cheat sheet

```http
# Auth
POST auth/login/  → store Token

# Plans (patient)
GET  plans/
GET  billing/status/
POST billing/checkout/  { plan_id, platform: "apple"|"android" }

# Stripe visits
GET  billing/patient/bills/
POST billing/patient/pay-bill/  { transaction_id }
GET  billing/doctor/summary/
POST billing/doctor/stripe-connect/
POST billing/doctor/create-invoice/  { patient_id, amount, notes?, appointment_id? }

# Hospitals
GET  hospitals/search/?lat=&lon=   (EMR then Maps clients)
GET  hospitals/?lat=&lon=  (+ client-side ~80 km filter)

# Appointments
POST appointments/  → read billing_hint

# Provider
POST providers/apply/  { ..., volunteer_online_visits: true|false }
```

---

## 9. What backend owns (already on VPS — frontend does not build)

- `POST /api/billing/verify-store/` → activates `PatientSubscription` after App Store / Play purchase
- Stripe webhook → marks `ProviderTransaction` paid
- 15% split on invoice create (`PLATFORM_COMMISSION_PERCENT=15`)
- `GET /api/plans/` → 3 store product IDs for patients

---

## 10. Reference in repo

| Area | Path |
|------|------|
| API paths | `lib/config/api_paths.dart` |
| API config | `lib/config/api_config.dart` |
| EMR API | `lib/services/emr_features_api.dart` |
| Store IAP | `lib/services/store_purchase_service.dart` |
| Plan UI | `lib/screens/client_hub_screen.dart` (`_PlanTab`) |
| Patient Stripe pay | `lib/screens/patient_billing_screen.dart`, `_InvoicesScreen` in `client_hub_screen.dart` |
| Doctor Stripe | `lib/screens/doctor_billing_screen.dart`, `patients_providers_screen.dart` |
| Hospitals | `lib/screens/hospitals_list_screen.dart`, `lib/services/catalog_api.dart` |
| Store / billing docs | `docs/STORE_SUBSCRIPTIONS.md`, `docs/BILLING_FLOW.md` |
| OpenAPI | `GET https://api.docsoncalls.com/api/schema/` |

---

## One-line summary

Plan tab: **direct App Store / Play** + `verify-store`; **Stripe** for doctor bills & web checkout; verify **hospitals** and **3-plan list** after deploy + rebuild.
