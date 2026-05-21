# Hospitals tab — frontend API guide (copy/paste)

## Two APIs — don’t mix them up

| App area | Base URL | Auth |
|----------|----------|------|
| Hospitals / ER search / wait times / maps | `https://api.mywaitime.com/api/` | None for read APIs |
| Login, appointments, billing, records, admin | `https://api.docsoncalls.com/api/` | `Authorization: Token <token>` after login |

Always use URLs ending in `/api/` (not host-only, not `:3015`, not `127.0.0.1` in production).

### Production / TestFlight / Play Store

| Dart define | Value |
|-------------|--------|
| `EMR_API_BASE_URL` | `https://api.docsoncalls.com/api/` |
| `MAPS_API_BASE_URL` | `https://api.mywaitime.com/api/` (Flutter default if omitted) |

Build or run against production:

```bash
./scripts/flutter_run_production_api.sh build
```

That script sets **EMR** only; **maps** uses `ApiConfig` default unless you set `FLUTTER_MAPS_API_BASE_URL` for a one-off override.

**VPS (server-side):** nginx `:443` → gunicorn `127.0.0.1:8012`. In `django_emr/.env`, `MYWAITIME_UPSTREAM_API_BASE` is either public MyWaitime or internal `http://127.0.0.1:3015/api/` — never exposed in the mobile app.

**Local simulator:** `./scripts/flutter_run_ios_simulator_local_api.sh` → EMR `8012`, maps `3015`.

---

## Hospitals & wait time (MyWaitime)

- **No API key.** Do not use `MYWAITIME_API_KEY` in the client.

```
GET /api/hospitals/search/?lat={lat}&lon={lon}&radius_m=25000&limit=50
GET /api/hospitals/nearby/?lat={lat}&lon={lon}          # alias of search
GET /api/hospitals/{uuid}/
GET /api/hospitals/{uuid}/smart-wait-time/
GET /api/hospitals/{uuid}/smart-wait-time/?user_lat={lat}&user_lon={lon}
```

**Batch wait times — POST, not GET:**

```
POST /api/hospitals/smart-wait-time/batch/
Content-Type: application/json

{
  "hospital_ids": ["uuid1", "uuid2"],
  "user_lat": 40.73,
  "user_lon": -74.17
}
```

Max **30** UUIDs per batch.

### Rules

- Hospital `id` = **UUID** from search (field is usually `id`)
- Prefer query param **`radius_m`** (meters); `radius` also works
- Response: `{ "status": "success", "data": { ... } }`
- Exception: `/api/health/` returns `"status": "healthy"`
- **Cache** wait times — refresh every few minutes, not on every scroll
- Rate limit ~**1000 req/hour** anonymous

### TomTom (maps)

Call through the API, not TomTom directly:

```
GET /api/tomtom/tiles/{z}/{x}/{y}.png
GET /api/tomtom/geocode/?address=...
GET /api/tomtom/search-hospitals/?lat=&lon=&radius_m=25000&limit=40
GET /api/tomtom/status/
```

Maps on `api.docsoncalls.com` also proxy these if you standardize on one host for the Doctors app.

---

## Doctors On Call app (EMR)

**Base:** `https://api.docsoncalls.com/api/`

**Headers on protected routes:**

```
Content-Type: application/json
Accept: application/json
Authorization: Token <token-from-login>
```

**Login:**

```
POST /api/auth/login/
{ "username": "...", "password": "..." }
```

→ use response token on all EMR calls.

| Feature | Path |
|---------|------|
| Health | `GET health/` |
| User profile | `GET user-data/` |
| Appointments | `GET appointments/mine/`, `POST appointments/` |
| Billing status | `GET billing/status/` |
| Pay invoice | `POST billing/patient/pay-bill/` |
| Plans | `GET plans/` |

### Hospitals in Flutter

1. **Live search:** Hospital Finder only — `GET {MAPS_API_BASE_URL}health/` then `GET {MAPS_API_BASE_URL}hospitals/search/` (nginx → Django **:3015**). No EMR catalog/TomTom on Live tab.
2. **Catalog tab:** EMR `GET /api/hospitals/?lat=&lon=` only.
3. **Detail:** MyWaitime `GET /api/hospitals/{uuid}/` first, EMR fallback.

Implemented in `hospitals_list_screen.dart` + `catalog_api.dart`.

### Local dev

```bash
flutter run --dart-define=EMR_API_BASE_URL=http://127.0.0.1:8012/api/
# Android emulator: http://10.0.2.2:8012/api/
# Maps stays: https://api.mywaitime.com/api/
```

---

## Web (browser) — CORS

- Native app / server: call APIs directly — no CORS issue.
- Browser SPA on a new domain: add origin to CORS or proxy `/api` through nginx.

---

## What frontend should **not** do

- Don’t put Stripe / RevenueCat / TomTom **secrets** in the app.
- Don’t call `127.0.0.1:3015` or `:8012` in **production** builds.
- Don’t use hospital **name** or Google `place_id` as id — use **UUID**.
- Don’t **GET** the batch wait-time URL — it’s **POST** + JSON.

---

## Error handling

| Code | Meaning |
|------|---------|
| 401 | Missing/invalid token (**EMR only**) |
| 404 | Bad hospital UUID |
| 502 | Upstream slow/unavailable — retry once, then cached/empty |
| 429 | Throttled — back off and cache |

If MyWaitime returns empty/502, retry via EMR `GET /api/hospitals/search/?lat=&lon=`.

---

## Slack one-liner

Use `https://api.mywaitime.com/api/` for hospital search and smart wait time (no auth, UUID ids, `radius_m` in meters). Use `https://api.docsoncalls.com/api/` for login, appointments, billing, records — send `Authorization: Token …`. Batch wait times: **POST** `/hospitals/smart-wait-time/batch/` with `{ "hospital_ids": [...] }`. Cache wait times; don’t poll every second. Browser apps need CORS or a backend proxy. No secrets in the client.
