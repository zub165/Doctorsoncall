# Frontend API Documentation
## Hospital Finder Django Backend - Complete API Reference

---

## 📋 **Table of Contents**

1. [Base Configuration](#base-configuration) — includes [§2.1 Production / nginx](#production-base-url-nginx--pre-flight-checks-21)
2. [Authentication](#authentication)
3. [Hospital Endpoints](#hospital-endpoints)
4. [Search & Discovery](#search--discovery)
5. [Feedback & Reviews](#feedback--reviews)
6. [User Analytics](#user-analytics)
7. [Maps & Location](#maps--location)
8. [AI Features](#ai-features)
9. [User Management](#user-management)
10. [Email Services](#email-services)
11. [Error Handling](#error-handling)
12. [Frontend Integration Examples](#frontend-integration-examples)
13. [Complete Endpoint Index (Flutter / EMR)](#complete-endpoint-index-flutter--emr)
14. [API & Flutter (production contract)](#api--flutter-production-contract)

---

## API & Flutter (production contract)

### Base URL & `user-data`

- **Base URL (production default):** `https://api.mywaitime.com/api/` — set **`API_BASE_URL`** to that (or your real host). Nginx on **443** usually means **no `:3015`** in the URL.
- **User / “me”:** `GET /api/user-data/` with `Authorization: Token <token>`. Set **`API_USER_ME_PATH=user-data/`** if the client uses a relative path (default in this project).
- **Guest vs logged-in:** `GET /api/user-data/` can return **200** with `is_authenticated: false` — treat as **guest**, not a hard error.

### Login & register

- **Login:** `POST /api/auth/login/` — body may use **`email` + `password`** or **`username` + `password`**. Read **`status: "success"`** and **`data.token`**.
- **Register:** `POST /api/auth/register/` with JSON **`username`** (optional if you send **`email` + `password`**), **`email`**, **`password`** — not `password1`/`password2` unless you change the backend. Prefer **no spaces** in optional username, or leave blank so the server derives from email.
- **Auth header** for protected routes: **`Authorization: Token <token>`** (not `Bearer` for this DRF token flow).

### Before you trust the app in production

1. `curl -sS GET https://api.mywaitime.com/api/health/` (or your host).
2. `curl …/api/schema/` or open **`…/api/docs/`** / **`…/api/redoc/`** — deployed OpenAPI is the **source of truth** for every route.
3. Login once and confirm **`data.token`**, then **`GET …/api/user-data/`** with the token.

### Nginx

- Proxy **`location /api/`** to `http://127.0.0.1:3015` (or your upstream) with **`Host`**, **`X-Forwarded-For`**, **`X-Forwarded-Proto`**.
- **Do not duplicate CORS** in both nginx and Django — pick **one** (duplicate headers break **Flutter web**).

### When `curl` works but the app fails

- **Flutter web:** check CORS (origins, preflight).
- **Android / iOS:** check HTTPS, hostname, certificate trust — **not** CORS.

### Project / repo hygiene

- **Full route map:** this file (including **§13** index: ER analytics, nutrition v1, vitals, doctors, wallet, lab, etc.).
- **Team `flutter run` (production):** `scripts/flutter_run_production_api.sh` (same **`API_BASE_URL`** + **`API_USER_ME_PATH`** as §2.1).
- **iOS Simulator + local Django:** `scripts/flutter_run_ios_simulator_local_api.sh` — uses **`http://127.0.0.1:${LOCAL_API_PORT:-3016}/api/`**. Start the server first: `cd django_emr && python manage.py runserver 127.0.0.1:3016`.
- **Android emulator + local Django:** use **`http://10.0.2.2:PORT/api/`** in `--dart-define` (same port as `runserver`).
- **Lab app:** use a **second base URL** **`/lab/`** if you integrate lab management (different prefix than `/api/`).
- **Duplicate routes:** core `/api/auth/login`, register, medical-records are resolved by **`api.urls`** first — don’t assume a small scaffold overrides them until you check **live OpenAPI**.

### Optional niceties

- **Rate limits / errors:** handle **`status: "error"`** and throttling (**429**) in the client.
- **Nutrition:** prefer **`/api/nutrition/v1/…`** for a stable contract vs legacy `/api/analyze/` Diet101 paths.

---

## 🔧 **Base Configuration**

### **Production base URL, nginx & pre-flight checks (§2.1)**

**Canonical production base (verbatim):** `https://api.mywaitime.com/api/`  
Use this everywhere **`API_BASE_URL`** must match production (trailing slash on `api/` matches Flutter `--dart-define` style).

| Pattern | Example `API_BASE_URL` | Typical setup |
|--------|------------------------|---------------|
| **B — HTTPS on 443 only** | `https://api.mywaitime.com/api/` | Nginx listens on **443** and **reverse-proxies** to **`127.0.0.1:3015`** (clients never see `:3015`) |
| **A — HTTPS with explicit port** | `https://api.mywaitime.com:3015/api/` | Only if **clients actually connect** to port **3015** on the public host |

**Pre-flight checks** (no placeholders):

```bash
curl -sS "https://api.mywaitime.com/api/health/" | head
curl -sS "https://api.mywaitime.com/api/schema/" | head -c 200
```

**Swagger / Redoc** (interactive route list for the running server):

- `https://api.mywaitime.com/api/docs/`
- `https://api.mywaitime.com/api/redoc/`

**Team run script** (from repo root, executable): `scripts/flutter_run_production_api.sh` — passes  
`--dart-define=API_BASE_URL=https://api.mywaitime.com/api/` (and `API_USER_ME_PATH`).  
From **`flutter_emr/`**: `../scripts/flutter_run_production_api.sh`.  
If production hostname ever changes, update **one place** in that script and the canonical string in **§2.1** above (or consolidate to a single env file later).

That **OpenAPI schema** (`/api/schema/`) is the **source of truth** for deployed routes (ER analytics, nutrition v1, vitals, doctors, wallet, lab prefixes, etc.) if they differ from any scaffold repo.

**Auth:** `POST …/api/auth/login/` with your JSON shape; Flutter commonly expects `status: "success"` and **`data.token`**. Adjust parsing only if your deployed responses differ.

**Protected calls:** `Authorization: Token <token>` on `GET …/api/user-data/` and any other authenticated routes.

**CORS:** applies to **Flutter web** only. **Android/iOS** need a valid HTTPS endpoint and trusted certs; they do **not** use browser CORS.

---

### **Base URLs**

```javascript
// Production (canonical — Pattern B, same string as API_BASE_URL / §2.1)
const API_BASE_URL = 'https://api.mywaitime.com/api/';

// Production Pattern A — only if clients hit :3015 directly
// const API_BASE_URL = 'https://api.mywaitime.com:3015/api/';

// Development (local Django)
// const API_BASE_URL = 'http://localhost:3015/api/';

// Production (HTTP, VPS IP — dev / emergency only; iOS may require ATS exceptions)
// const API_BASE_URL = 'http://208.109.215.53:3015/api/';
```

### **CORS Configuration**

✅ **CORS is enabled** for the following origins:
- `http://localhost:3015`
- `http://localhost:3016`
- `https://localhost:3016`
- `http://208.109.215.53:3015`
- `http://208.109.215.53:3016`
- `https://208.109.215.53:3016`
- `https://mywaitime.com`
- `https://www.mywaitime.com`
- `https://api.mywaitime.com`
- `https://zub165.github.io` (GitHub Pages)

### **Request Headers**

```javascript
const defaultHeaders = {
  'Content-Type': 'application/json',
  'Accept': 'application/json',
  // For authenticated requests (Hospital Finder /api/): prefer DRF token
  'Authorization': 'Token <DRF_TOKEN>',
  // JWT also accepted where SimpleJWT is wired (e.g. some lab routes); use only if that flow issued the token
  // 'Authorization': 'Bearer <JWT>',
  // For CSRF protection (if using session auth):
  'X-CSRFToken': '<CSRF_TOKEN>',
};
```

### **Response Headers**

The backend includes these custom headers:
- `X-Response-Time`: Response time in seconds (e.g., "0.123s")
- `X-Request-ID`: Unique request identifier for debugging
- `X-DB-Query-Count`: Number of database queries (debug mode)

### **Response Format**

All API responses follow this structure:

```javascript
// Success Response
{
  "status": "success",
  "data": { /* response data */ },
  "message": "Optional success message",
  "source": "local_database" | "api_discovery",
  "total_found": 10,
  "timestamp": "2025-12-24T12:00:00Z"
}

// Error Response
{
  "status": "error",
  "message": "Error description",
  "error_code": "ERROR_CODE",
  "details": { /* optional error details */ }
}
```

---

## 🔐 **Authentication**

### **1. Register User**

```http
POST /api/auth/register/
```

**Request Body:**
```json
{
  "username": "john_doe",
  "email": "john@example.com",
  "password": "secure_password123",
  "first_name": "John",
  "last_name": "Doe"
}
```

**Response:**
```json
{
  "status": "success",
  "message": "User registered successfully",
  "user": {
    "id": "uuid",
    "username": "john_doe",
    "email": "john@example.com"
  },
  "token": "jwt_access_token",
  "refresh_token": "jwt_refresh_token"
}
```

### **2. Login User**

```http
POST /api/auth/login/
```

**Request Body:**
```json
{
  "username": "john_doe",  // OR email
  "password": "secure_password123"
}
```

**Response:**
```json
{
  "status": "success",
  "message": "Login successful",
  "user": { /* user object */ },
  "token": "jwt_access_token",
  "refresh_token": "jwt_refresh_token"
}
```

### **3. JWT Token Authentication (Mobile Apps)**

```http
POST /api/auth/token/
```

**Request Body:**
```json
{
  "username": "john_doe",
  "password": "secure_password123"
}
```

**Response:**
```json
{
  "access": "jwt_access_token",
  "refresh": "jwt_refresh_token"
}
```

**Refresh Token:**
```http
POST /api/auth/token/refresh/
```

**Request Body:**
```json
{
  "refresh": "jwt_refresh_token"
}
```

### **4. Get User Profile**

```http
GET /api/auth/profile/
Authorization: Bearer <JWT_TOKEN>
```

### **5. Update User Profile**

```http
PUT /api/auth/profile/
Authorization: Bearer <JWT_TOKEN>
```

**Request Body:**
```json
{
  "first_name": "John",
  "last_name": "Doe",
  "email": "newemail@example.com"
}
```

### **6. Change Password**

```http
POST /api/auth/change-password/
Authorization: Bearer <JWT_TOKEN>
```

**Request Body:**
```json
{
  "old_password": "old_password",
  "new_password": "new_password"
}
```

### **7. Logout**

```http
POST /api/auth/logout/
Authorization: Bearer <JWT_TOKEN>
```

### **8. Get CSRF Token**

```http
GET /api/auth/csrf-token/
```

**Response:**
```json
{
  "csrf_token": "csrf_token_string"
}
```

---

## 🏥 **Hospital Endpoints**

### **1. Search Hospitals (Primary Endpoint)**

```http
GET /api/hospitals/search/
```

**Query Parameters:**
- `lat` (required): Latitude (decimal, -90 to 90)
- `lon` (required): Longitude (decimal, -180 to 180)
- `radius_m` (optional): Search radius in meters (default: 10000 = 10km)
- `limit` (optional): Maximum results (default: 20, max: 100)
- `type` (optional): Filter by type (`all`, `emergency`, `urgent_care`, `clinic`, `general`)
- `q` (optional): Search query (will attempt geocoding if no lat/lon)

**Example:**
```javascript
GET /api/hospitals/search/?lat=28.6753&lon=-81.5115&radius_m=15000&limit=20
```

**Response:**
```json
{
  "status": "success",
  "source": "api_discovery" | "local_database",
  "total_found": 19,
  "data": [
    {
      "id": "uuid",
      "name": "AdventHealth Apopka",
      "address": "201 North Park Avenue",
      "city": "Apopka",
      "state": "FL",
      "country": "USA",
      "phone": "+1-407-889-2000",
      "email": null,
      "website": "https://www.adventhealth.com",
      "latitude": 28.6753,
      "longitude": -81.5115,
      "hospital_type": "emergency" | "urgent_care" | "clinic" | "general",
      "specialties": ["Emergency Medicine", "Cardiology"],
      "ai_rating": 8.5,
      "wait_time_prediction": 20,
      "capacity_status": "medium",
      "distance": 2.5,
      "overall_performance_score": 8.2,
      "category_scores": {
        "wait_time": 7.5,
        "quality": 8.5,
        "accessibility": 8.0
      },
      "total_feedback_count": 45,
      "performance_grade": "A",
      "created_at": "2025-01-01T00:00:00Z",
      "updated_at": "2025-12-24T12:00:00Z"
    }
  ],
  "database_stats": {
    "saved_to_db": 5,
    "already_existed": 14
  }
}
```

**Priority Sorting:**
Hospitals are automatically sorted by priority:
1. **Emergency** (Priority 1)
2. **Urgent Care** (Priority 2)
3. **Walk-in Clinics** (Priority 3)
4. **Clinics** (Priority 4)
5. **Medical Centers** (Priority 5)
6. **General Hospitals** (Priority 6)

### **2. Get Hospital List**

```http
GET /api/hospitals/
```

**Query Parameters:**
- `limit` (optional): Maximum results (default: 20)
- `offset` (optional): Pagination offset
- `city` (optional): Filter by city
- `state` (optional): Filter by state
- `type` (optional): Filter by hospital type
- `sort` (optional): Sort by (`distance`, `rating`, `name`)

**Response:** Same format as search endpoint

### **3. Get Enhanced Hospital List**

```http
GET /api/hospitals-enhanced/
```

Same as above but with additional AI insights and performance metrics.

### **4. Get Hospital Details**

```http
GET /api/hospitals/{hospital_id}/
```

**Response:**
```json
{
  "status": "success",
  "data": {
    "id": "uuid",
    "name": "Hospital Name",
    // ... all hospital fields ...
    "reviews": [
      {
        "id": "uuid",
        "rating": 5,
        "comment": "Great service!",
        "user": "username",
        "created_at": "2025-12-24T12:00:00Z"
      }
    ],
    "performance": {
      "overall_score": 8.5,
      "wait_time_score": 7.5,
      "quality_score": 8.5
    }
  }
}
```

### **5. Get Hospital Details by Query**

```http
GET /api/hospitals/details/?name=Hospital Name&city=Apopka
```

### **6. Get Hospital Wait Times**

```http
GET /api/hospitals/wait-times/?hospital_id={uuid}
```

**Response:**
```json
{
  "status": "success",
  "data": {
    "hospital_id": "uuid",
    "wait_time_prediction": 20,
    "capacity_status": "medium",
    "last_updated": "2025-12-24T12:00:00Z",
    "historical_data": [
      {
        "timestamp": "2025-12-24T10:00:00Z",
        "wait_time": 15,
        "capacity": "low"
      }
    ]
  }
}
```

### **7. Update Hospital Wait Time**

```http
PUT /api/hospitals/{hospital_id}/update-wait-time/
Authorization: Bearer <JWT_TOKEN>
```

**Request Body:**
```json
{
  "wait_time": 25,
  "capacity_status": "high",
  "source": "user_report" | "system_calculated"
}
```

### **8. Get AI Wait Time Prediction**

```http
GET /api/hospitals/{hospital_id}/ai-wait-time/
```

**Response:**
```json
{
  "status": "success",
  "data": {
    "predicted_wait_time": 20,
    "confidence": 0.85,
    "factors": {
      "time_of_day": "peak",
      "day_of_week": "weekend",
      "historical_average": 18,
      "current_capacity": "medium"
    }
  }
}
```

### **9. Get Hospital Statistics**

```http
GET /api/hospitals/stats/
```

**Response:**
```json
{
  "status": "success",
  "data": {
    "total_hospitals": 1500,
    "by_type": {
      "emergency": 250,
      "urgent_care": 400,
      "clinic": 600,
      "general": 250
    },
    "by_state": {
      "FL": 800,
      "CA": 500,
      "TX": 200
    }
  }
}
```

### **10. Add Hospital (Admin)**

```http
POST /api/hospitals/add/
Authorization: Bearer <JWT_TOKEN>
```

**Request Body:**
```json
{
  "name": "New Hospital",
  "address": "123 Main St",
  "city": "Orlando",
  "state": "FL",
  "country": "USA",
  "latitude": 28.5383,
  "longitude": -81.3792,
  "phone": "+1-407-555-1234",
  "hospital_type": "emergency",
  "specialties": ["Emergency Medicine"]
}
```

---

## 🔍 **Search & Discovery**

### **1. Resolve Hospital**

```http
POST /api/hospitals/resolve/
```

**Request Body:**
```json
{
  "name": "Hospital Name",
  "address": "123 Main St, City, State",
  "latitude": 28.5383,
  "longitude": -81.3792
}
```

**Response:**
```json
{
  "status": "success",
  "data": {
    "hospital": { /* hospital object */ },
    "match_confidence": 0.95,
    "matched_fields": ["name", "address"]
  }
}
```

### **2. AI Discover Facilities**

```http
POST /api/refinement/discover/
Authorization: Bearer <JWT_TOKEN>
```

**Request Body:**
```json
{
  "city": "Orlando",
  "state": "FL",
  "radius_km": 50
}
```

### **3. AI Refine Facilities**

```http
POST /api/refinement/refine/
Authorization: Bearer <JWT_TOKEN>
```

**Request Body:**
```json
{
  "hospital_ids": ["uuid1", "uuid2"],
  "refinement_type": "categorization" | "specialties" | "all"
}
```

### **4. Get Refinement Status**

```http
GET /api/refinement/status/
```

---

## 💬 **Feedback & Reviews**

### **1. Submit Feedback**

```http
POST /api/feedback/submit/
```

**Request Body:**
```json
{
  "hospital_id": "uuid",
  "rating": 5,
  "comment": "Great service!",
  "categories": {
    "wait_time": 4,
    "quality": 5,
    "staff": 5,
    "facility": 4
  },
  "anonymous": false
}
```

**Response:**
```json
{
  "status": "success",
  "message": "Feedback submitted successfully",
  "data": {
    "id": "uuid",
    "hospital_id": "uuid",
    "rating": 5,
    "created_at": "2025-12-24T12:00:00Z"
  }
}
```

### **2. Get Hospital Feedback**

```http
GET /api/hospitals/{hospital_id}/feedback/
```

**Query Parameters:**
- `limit` (optional): Maximum results
- `offset` (optional): Pagination offset
- `min_rating` (optional): Minimum rating filter

**Response:**
```json
{
  "status": "success",
  "data": {
    "hospital_id": "uuid",
    "total_feedback": 45,
    "average_rating": 4.5,
    "feedback": [
      {
        "id": "uuid",
        "rating": 5,
        "comment": "Great service!",
        "user": "username",
        "categories": {
          "wait_time": 4,
          "quality": 5
        },
        "created_at": "2025-12-24T12:00:00Z"
      }
    ]
  }
}
```

### **3. Get Hospital Reviews**

```http
GET /api/hospitals/{hospital_id}/reviews/
```

Same format as feedback endpoint.

### **4. Get Hospital Performance**

```http
GET /api/hospitals/{hospital_id}/performance/
```

**Response:**
```json
{
  "status": "success",
  "data": {
    "hospital_id": "uuid",
    "overall_performance_score": 8.5,
    "category_scores": {
      "wait_time": 7.5,
      "quality": 8.5,
      "staff": 8.0,
      "facility": 8.5,
      "accessibility": 8.0
    },
    "total_feedback_count": 45,
    "performance_grade": "A",
    "trend": "improving",
    "last_updated": "2025-12-24T12:00:00Z"
  }
}
```

### **5. Get Top Performing Hospitals**

```http
GET /api/hospitals/top-performing/
```

**Query Parameters:**
- `limit` (optional): Maximum results (default: 10)
- `min_rating` (optional): Minimum rating
- `city` (optional): Filter by city
- `state` (optional): Filter by state

**Response:**
```json
{
  "status": "success",
  "data": [
    {
      "hospital": { /* hospital object */ },
      "performance_score": 9.2,
      "grade": "A+",
      "total_feedback": 120
    }
  ]
}
```

### **6. Get All Feedback**

```http
GET /api/feedback/
```

**Query Parameters:**
- `hospital_id` (optional): Filter by hospital
- `user_id` (optional): Filter by user
- `min_rating` (optional): Minimum rating
- `limit` (optional): Maximum results

---

## 📊 **User Analytics**

### **1. Track User Session**

```http
POST /api/analytics/session/track/
```

**Request Body:**
```json
{
  "session_id": "session_uuid",
  "device_type": "mobile" | "desktop" | "tablet",
  "platform": "ios" | "android" | "web",
  "app_version": "1.0.0",
  "location": {
    "latitude": 28.6753,
    "longitude": -81.5115,
    "city": "Apopka",
    "state": "FL"
  }
}
```

### **2. Track Hospital View**

```http
POST /api/analytics/hospital/view/
```

**Request Body:**
```json
{
  "hospital_id": "uuid",
  "view_duration": 30,
  "action": "viewed" | "clicked" | "directions_requested"
}
```

### **3. Track User Search**

```http
POST /api/analytics/search/track/
```

**Request Body:**
```json
{
  "search_query": "emergency room",
  "search_type": "location" | "name" | "specialty",
  "results_count": 15,
  "filters": {
    "type": "emergency",
    "radius": 10000
  }
}
```

### **4. Track ER Time Interaction**

```http
POST /api/analytics/er-time/interaction/
```

**Request Body:**
```json
{
  "hospital_id": "uuid",
  "interaction_type": "viewed_wait_time" | "updated_wait_time" | "shared",
  "wait_time_value": 20
}
```

### **5. Track Review Interaction**

```http
POST /api/analytics/review/interaction/
```

**Request Body:**
```json
{
  "hospital_id": "uuid",
  "action": "viewed_reviews" | "submitted_review" | "helpful_clicked"
}
```

### **6. Get User Analytics Dashboard**

```http
GET /api/analytics/dashboard/
Authorization: Bearer <JWT_TOKEN>
```

**Response:**
```json
{
  "status": "success",
  "data": {
    "total_searches": 45,
    "hospitals_viewed": 12,
    "reviews_submitted": 3,
    "favorite_hospitals": ["uuid1", "uuid2"],
    "recent_activity": [ /* activity items */ ]
  }
}
```

### **7. Get Hospital Analytics**

```http
GET /api/analytics/hospital/{hospital_id}/
```

**Response:**
```json
{
  "status": "success",
  "data": {
    "hospital_id": "uuid",
    "total_views": 150,
    "total_searches": 45,
    "average_view_duration": 25,
    "popular_times": {
      "hourly": [ /* hourly distribution */ ],
      "daily": [ /* daily distribution */ ]
    }
  }
}
```

---

## 🗺️ **Maps & Location**

### **1. Get User Location**

```http
GET /api/user-location/
```

**Query Parameters:**
- `lat` (required): Latitude
- `lon` (required): Longitude

**Response:**
```json
{
  "status": "success",
  "data": {
    "latitude": 28.6753,
    "longitude": -81.5115,
    "address": "Apopka, FL, USA",
    "city": "Apopka",
    "state": "FL",
    "country": "USA"
  }
}
```

### **2. Get Directions**

```http
POST /api/directions/
```

**Request Body:**
```json
{
  "origin": {
    "latitude": 28.6753,
    "longitude": -81.5115
  },
  "destination": {
    "latitude": 28.5383,
    "longitude": -81.3792
  },
  "travel_mode": "driving" | "walking" | "transit"
}
```

**Response:**
```json
{
  "status": "success",
  "data": {
    "distance": "15.2 miles",
    "duration": "25 minutes",
    "route": {
      "polyline": "encoded_polyline_string",
      "steps": [ /* route steps */ ]
    }
  }
}
```

### **3. Google Geocode**

```http
GET /api/google/geocode/?address=123 Main St, Orlando, FL
```

**Response:**
```json
{
  "status": "success",
  "data": {
    "latitude": 28.5383,
    "longitude": -81.3792,
    "formatted_address": "123 Main St, Orlando, FL 32801, USA"
  }
}
```

### **4. Google Reverse Geocode**

```http
GET /api/google/reverse-geocode/?lat=28.5383&lon=-81.3792
```

### **5. Google Directions**

```http
POST /api/google/directions/
```

**Request Body:**
```json
{
  "origin": "123 Main St, Orlando, FL",
  "destination": "456 Park Ave, Apopka, FL",
  "travel_mode": "driving"
}
```

### **6. Google Place Details**

```http
GET /api/google/place-details/?place_id=ChIJ...
```

### **7. TomTom Geocode**

```http
GET /api/tomtom/geocode/?address=123 Main St, Orlando, FL
```

### **8. TomTom Reverse Geocode**

```http
GET /api/tomtom/reverse-geocode/?lat=28.5383&lon=-81.3792
```

### **9. TomTom Route**

```http
POST /api/tomtom/route/
```

**Request Body:**
```json
{
  "origin": { "lat": 28.6753, "lon": -81.5115 },
  "destination": { "lat": 28.5383, "lon": -81.3792 },
  "route_type": "fastest" | "shortest" | "eco"
}
```

### **10. Get Map Configuration**

```http
GET /api/map-config/
```

**Response:**
```json
{
  "status": "success",
  "data": {
    "google_maps_api_key": "AIza...",
    "tomtom_api_key": "xxx...",
    "default_zoom": 12,
    "default_center": {
      "lat": 28.5383,
      "lon": -81.3792
    }
  }
}
```

---

## 🤖 **AI Features**

### **1. Track User Behavior**

```http
POST /api/ai/track-behavior/
```

**Request Body:**
```json
{
  "action": "search" | "view" | "click" | "share",
  "hospital_id": "uuid",
  "metadata": { /* additional data */ }
}
```

### **2. Get User Analytics**

```http
GET /api/ai/user-analytics/
Authorization: Bearer <JWT_TOKEN>
```

### **3. Generate Recommendations**

```http
GET /api/ai/recommendations/
Authorization: Bearer <JWT_TOKEN>
```

**Query Parameters:**
- `lat` (optional): User latitude
- `lon` (optional): User longitude
- `limit` (optional): Maximum recommendations

**Response:**
```json
{
  "status": "success",
  "data": {
    "recommendations": [
      {
        "hospital": { /* hospital object */ },
        "reason": "Based on your search history",
        "confidence": 0.85
      }
    ]
  }
}
```

### **4. Save User Preferences**

```http
POST /api/ai/preferences/
Authorization: Bearer <JWT_TOKEN>
```

**Request Body:**
```json
{
  "preferred_hospital_types": ["emergency", "urgent_care"],
  "preferred_specialties": ["Emergency Medicine"],
  "max_wait_time": 30,
  "notification_preferences": {
    "wait_time_updates": true,
    "new_hospitals": false
  }
}
```

### **5. Get User Preferences**

```http
GET /api/ai/preferences/get/
Authorization: Bearer <JWT_TOKEN>
```

### **6. Predict Wait Time (ML)**

```http
POST /api/ai/ml/predict-wait-time/
```

**Request Body:**
```json
{
  "hospital_id": "uuid",
  "time_of_day": "14:30",
  "day_of_week": "monday",
  "historical_data": true
}
```

### **7. Get Healthcare Insights**

```http
GET /api/ai/healthcare/insights/
Authorization: Bearer <JWT_TOKEN>
```

---

## 👤 **User Management**

### **1. Delete Account**

```http
DELETE /api/users/me/
Authorization: Bearer <JWT_TOKEN>
```

### **2. Request Account Deletion**

```http
POST /api/privacy/request-account-deletion/
Authorization: Bearer <JWT_TOKEN>
```

### **3. Request Data Export**

```http
POST /api/privacy/request-data-export/
Authorization: Bearer <JWT_TOKEN>
```

### **4. Forgot Password**

```http
POST /api/auth/forgot-password/
```

**Request Body:**
```json
{
  "email": "user@example.com"
}
```

### **5. Reset Password**

```http
POST /api/auth/reset-password/
```

**Request Body:**
```json
{
  "token": "reset_token",
  "new_password": "new_secure_password"
}
```

---

## 📧 **Email Services**

### **1. Send Email**

```http
POST /api/email/send/
```

**Request Body:**
```json
{
  "to": "recipient@example.com",
  "subject": "Email Subject",
  "message": "Email body",
  "html": "<html>...</html>"
}
```

### **2. Send Template Email**

```http
POST /api/email/send-template/
```

**Request Body:**
```json
{
  "to": "recipient@example.com",
  "template": "welcome" | "password_reset" | "appointment_confirmation",
  "variables": {
    "name": "John Doe",
    "link": "https://..."
  }
}
```

### **3. Send Welcome Email**

```http
POST /api/email/welcome/
```

**Request Body:**
```json
{
  "to": "user@example.com",
  "username": "john_doe"
}
```

### **4. Test Email Connection**

```http
GET /api/email/test-connection/
```

---

## ⚠️ **Error Handling**

### **Common Error Codes**

| Error Code | Description | HTTP Status |
|------------|-------------|-------------|
| `MISSING_COORDINATES` | lat/lon parameters missing | 400 |
| `INVALID_COORDINATES` | Invalid coordinate format | 400 |
| `COORDINATES_OUT_OF_RANGE` | Coordinates outside valid range | 400 |
| `HOSPITAL_NOT_FOUND` | Hospital ID not found | 404 |
| `UNAUTHORIZED` | Authentication required | 401 |
| `FORBIDDEN` | Insufficient permissions | 403 |
| `VALIDATION_ERROR` | Request validation failed | 400 |
| `SERVER_ERROR` | Internal server error | 500 |

### **Error Response Format**

```json
{
  "status": "error",
  "message": "Human-readable error message",
  "error_code": "ERROR_CODE",
  "details": {
    "field": "error detail for specific field"
  },
  "timestamp": "2025-12-24T12:00:00Z"
}
```

---

## 💻 **Frontend Integration Examples**

### **JavaScript/TypeScript Example**

```typescript
// api.ts
const API_BASE_URL = 'https://api.mywaitime.com/api';

class HospitalAPI {
  private baseURL: string;
  private token: string | null = null;

  constructor(baseURL: string) {
    this.baseURL = baseURL;
  }

  setToken(token: string) {
    this.token = token;
  }

  private async request<T>(
    endpoint: string,
    options: RequestInit = {}
  ): Promise<T> {
    const url = `${this.baseURL}${endpoint}`;
    const headers: HeadersInit = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      ...options.headers,
    };

    if (this.token) {
      headers['Authorization'] = `Bearer ${this.token}`;
    }

    const response = await fetch(url, {
      ...options,
      headers,
    });

    const data = await response.json();

    if (!response.ok || data.status === 'error') {
      throw new Error(data.message || 'API request failed');
    }

    return data;
  }

  // Search hospitals
  async searchHospitals(params: {
    lat: number;
    lon: number;
    radius_m?: number;
    limit?: number;
    type?: string;
  }) {
    const queryParams = new URLSearchParams({
      lat: params.lat.toString(),
      lon: params.lon.toString(),
      ...(params.radius_m && { radius_m: params.radius_m.toString() }),
      ...(params.limit && { limit: params.limit.toString() }),
      ...(params.type && { type: params.type }),
    });

    return this.request<{
      status: string;
      data: Hospital[];
      total_found: number;
    }>(`/hospitals/search/?${queryParams}`);
  }

  // Get hospital details
  async getHospitalDetails(hospitalId: string) {
    return this.request<{
      status: string;
      data: Hospital;
    }>(`/hospitals/${hospitalId}/`);
  }

  // Submit feedback
  async submitFeedback(feedback: {
    hospital_id: string;
    rating: number;
    comment: string;
    categories?: Record<string, number>;
  }) {
    return this.request<{
      status: string;
      message: string;
      data: Feedback;
    }>('/feedback/submit/', {
      method: 'POST',
      body: JSON.stringify(feedback),
    });
  }

  // Track hospital view
  async trackHospitalView(hospitalId: string, action: string) {
    return this.request('/analytics/hospital/view/', {
      method: 'POST',
      body: JSON.stringify({
        hospital_id: hospitalId,
        action,
      }),
    });
  }
}

// Usage
const api = new HospitalAPI(API_BASE_URL);

// Search hospitals
const results = await api.searchHospitals({
  lat: 28.6753,
  lon: -81.5115,
  radius_m: 15000,
  limit: 20,
});

console.log(`Found ${results.total_found} hospitals`);
console.log(results.data);
```

### **React Hook Example**

```typescript
// useHospitalSearch.ts
import { useState, useEffect } from 'react';
import { HospitalAPI } from './api';

const api = new HospitalAPI(API_BASE_URL);

export function useHospitalSearch(lat: number, lon: number, radius: number = 10000) {
  const [hospitals, setHospitals] = useState<Hospital[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const searchHospitals = async () => {
      setLoading(true);
      setError(null);
      try {
        const results = await api.searchHospitals({
          lat,
          lon,
          radius_m: radius,
          limit: 20,
        });
        setHospitals(results.data);
      } catch (err) {
        setError(err instanceof Error ? err.message : 'Search failed');
      } finally {
        setLoading(false);
      }
    };

    if (lat && lon) {
      searchHospitals();
    }
  }, [lat, lon, radius]);

  return { hospitals, loading, error };
}
```

### **Flutter/Dart Example**

```dart
// hospital_api.dart
import 'package:http/http.dart' as http;
import 'dart:convert';

class HospitalAPI {
  final String baseURL;
  String? token;

  HospitalAPI({this.baseURL = 'https://api.mywaitime.com/api'});

  void setToken(String token) {
    this.token = token;
  }

  Future<Map<String, dynamic>> request(
    String endpoint, {
    String method = 'GET',
    Map<String, dynamic>? body,
  }) async {
    final url = Uri.parse('$baseURL$endpoint');
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }

    http.Response response;
    if (method == 'GET') {
      response = await http.get(url, headers: headers);
    } else if (method == 'POST') {
      response = await http.post(
        url,
        headers: headers,
        body: body != null ? jsonEncode(body) : null,
      );
    } else {
      throw Exception('Unsupported HTTP method');
    }

    final data = jsonDecode(response.body);
    if (response.statusCode != 200 || data['status'] == 'error') {
      throw Exception(data['message'] ?? 'API request failed');
    }

    return data;
  }

  Future<List<Map<String, dynamic>>> searchHospitals({
    required double lat,
    required double lon,
    int radiusM = 10000,
    int limit = 20,
  }) async {
    final queryParams = Uri(queryParameters: {
      'lat': lat.toString(),
      'lon': lon.toString(),
      'radius_m': radiusM.toString(),
      'limit': limit.toString(),
    });

    final response = await request('/hospitals/search/?${queryParams.query}');
    return List<Map<String, dynamic>>.from(response['data']);
  }
}
```

---

## 🗺️ **Complete Endpoint Index (Flutter / EMR)**

All paths below assume the main app mounts them as in `hospital_finder_django/urls.py`: core hospital APIs under **`/api/`**, nutrition under **`/api/nutrition/`**, optional AI clinical helpers under **`/api/ai/`** (from `ai_services`), lab under **`/lab/`** (separate prefix). **Trailing slashes** match Django defaults; some routes register both with/without slash for mobile clients.

**Auth (typical for Flutter against this backend):** `Authorization: Token <token>` after `POST /api/auth/login/`. Unwrap responses with `status` / `data` where applicable.

**OpenAPI / discovery:** `GET /api/schema/`, UI: `/api/docs/`, `/api/redoc/` (drf-spectacular).

**Router caveat:** `api/urls.py` registers `auth/login/`, `auth/register/`, and `medical-records/` **before** `include(simple_auth_urls)` and `include(doctor_urls)`. The **first** matching route wins—use the explicit `/api/auth/*` and `/api/medical-records/*` handlers from `api.views` unless you intentionally call another module’s URL.

### Core: health, user, auth

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/health/` | API health |
| GET | `/api/v1/courses/` | Placeholder courses list |
| GET, POST | `/api/user-data/` | Current user / update profile fields |
| GET | `/api/auth/csrf-token/` | CSRF token |
| POST | `/api/auth/login/` | Login (email or username + password) |
| POST | `/api/auth/register/` | Register (JSON: username, email, password; username optional if email-only) |
| GET | `/api/auth/password-policy/` | Password rules text |
| POST | `/api/auth/logout/` | Logout |
| GET, PUT/PATCH | `/api/auth/profile/` | Profile |
| POST | `/api/auth/change-password/` | Change password |
| POST | `/api/auth/forgot-password/` | Forgot password |
| POST | `/api/auth/password-reset/` | Reset request |
| POST | `/api/auth/reset-password/` | Confirm reset |
| DELETE | `/api/users/me/` | Delete account |

### Hospitals, ER wait time, capacity, refinement

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/hospitals/` | List |
| GET | `/api/hospitals-enhanced/` | Enhanced list |
| GET | `/api/hospitals/<uuid>/` | Detail |
| GET | `/api/hospitals/details/` | Detail by query params |
| GET | `/api/hospitals/search/`, `/api/hospitals/nearby/` | Search / nearby |
| GET | `/api/hospitals/wait-times/` | Wait-time query |
| POST | `/api/hospitals/wait-times/update/` | Report/update wait |
| GET, PATCH | `/api/hospitals/<uuid>/smart-wait-time/` | Smart wait estimate |
| POST | `/api/hospitals/<uuid>/update-wait-time/` | Update wait |
| PATCH | `/api/hospitals/<uuid>/wait-time/` | Patch wait fields |
| GET | `/api/hospitals/<uuid>/ai-wait-time/` | AI wait prediction |
| GET | `/api/hospitals/<uuid>/traffic/` | Traffic context |
| GET | `/api/hospitals/<uuid>/weather/` | Weather context |
| POST | `/api/hospitals/<uuid>/er-capacity/` | ER capacity |
| POST | `/api/refinement/discover/`, `/api/refinement/refine/` | AI discovery / refinement jobs |
| GET | `/api/refinement/status/` | Refinement status |
| GET | `/api/hospitals/dedup/preview/` | Dedup preview |
| POST | `/api/duplicates/find/`, `/duplicates/remove/` | Duplicate tooling |

### Feedback, reviews, performance

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/feedback/` | List feedback |
| POST | `/api/feedback/submit/` | Submit |
| GET | `/api/hospitals/<uuid>/feedback/` | Per hospital |
| POST | `/api/hospitals/<uuid>/update-rating/` | Rating update |
| GET | `/api/hospitals/<uuid>/reviews/` | Reviews |
| GET | `/api/hospitals/<uuid>/performance/` | Performance metrics |
| GET | `/api/hospitals/top-performing/` | Leaderboard |

### Patients, medical records (EMR-lite in `api.views`)

| Method | Path | Purpose |
|--------|------|---------|
| GET, POST | `/api/patients/` | List / create |
| GET | `/api/patients/search/` | Search |
| GET | `/api/patients/<uuid>/` | Detail |
| GET | `/api/patients/<uuid>/records/` | Patient records |
| GET, POST | `/api/medical-records/` | Records list/create |
| GET, PATCH, DELETE | `/api/medical-records/<uuid>/` | Record detail |

### Family / bookings / expenses (local-first helpers)

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/api/chains/` | Create booking chain |
| GET | `/api/chains/me/` | My chain |
| GET | `/api/expense-categories/` | Categories |
| GET, POST | `/api/expenses/` | Expenses |
| GET, PATCH, DELETE | `/api/expenses/<id>/` | Expense detail |
| GET, POST | `/api/family-members/` | Family members |
| GET, PATCH, DELETE | `/api/family-members/<id>/` | Member detail |

### Maps / geodata (TomTom, Google, OSM, Healthsites)

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/osm/search-hospitals/`, `/api/osm/system-status/` | OpenStreetMap |
| GET | `/api/healthsites/search-hospitals/`, `/api/healthsites/system-status/` | Healthsites.io |
| GET | `/api/tomtom/*` | Status, search, geocode, reverse, route, api-key, tiles |
| GET, POST | `/api/google/*` | Status, search, geocode, reverse, directions, place-details |
| POST | `/api/directions/` | Generic directions |

### Diet101 / camera (legacy under `/api/` — distinct from Nutrition Track service)

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/api/analyze/` | Analyze image |
| POST | `/api/barcode/analyze/` | Barcode |
| GET | `/api/model/info/` | Model metadata |

### Admin / enhanced auth (privileged)

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/api/auth/register/role/` | Role register |
| POST | `/api/auth/enhanced-register/` | Enhanced register |
| GET | `/api/admin/users/`, `/api/admin/export/`, `/api/admin/create-admin/` | Admin |

### Visualization & analytics dashboards

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/dashboard/` | Dashboard |
| GET | `/api/analytics/` | Analytics API |
| GET | `/api/analytics/map-data/` | Map data |
| GET, POST | `/api/analytics/search/`, `/api/analytics/activity/` | Lightweight analytics |
| GET | `/api/feedback-analytics/`, `/api/real-time-metrics/` | Feedback / metrics |
| GET | `/api/export/` | Export hospital data |
| GET | `/api/analytics/enhanced/`, `/api/analytics/enhanced/api/` | Enhanced dashboard |

### ER time & behaviour tracking (recommended for robust ER UX)

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/api/analytics/er-time/interaction/` | ER time UI interactions |
| GET, POST | `/api/analytics/session/track/` | Sessions |
| GET, POST | `/api/analytics/hospital/view/` | Hospital views |
| GET, POST | `/api/analytics/search/track/` | Search tracking |
| GET, POST | `/api/analytics/review/interaction/` | Reviews |
| GET, POST | `/api/analytics/activity/real-time/` | Real-time activity |
| GET | `/api/analytics/dashboard/` | User analytics dashboard |
| GET | `/api/analytics/hospital/<uuid>/` | Per-hospital analytics |
| GET | `/api/analytics/real-time/` | Aggregated real-time |

### AI (core app — wait ML, realtime, prefs)

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/api/ai/track-behavior/` | Behaviour |
| GET | `/api/ai/user-analytics/` | User analytics |
| POST | `/api/ai/recommendations/` | Recommendations |
| GET | `/api/ai/analytics-dashboard/` | Dashboard |
| POST | `/api/ai/preferences/` | Save prefs |
| GET | `/api/ai/preferences/get/` | Get prefs |
| POST | `/api/ai/learn/trigger/` | Trigger learning |
| GET | `/api/ai/learn/status/` | Learning status |
| POST | `/api/ai/ml/predict-wait-time/` | ML wait prediction |
| POST | `/api/ai/ml/train-model/` | Train |
| GET | `/api/ai/ml/model-status/` | Model status |
| POST | `/api/ai/emergency/optimize-response/` | Emergency optimizer |
| GET | `/api/ai/healthcare/insights/` | Insights |
| POST | `/api/ai/predict/behavior/` | Behaviour prediction |
| POST | `/api/ai/realtime/send-update/` | Realtime push |
| GET | `/api/ai/realtime/analytics/` | Realtime analytics |

### Translation / language

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/translations/` | Bundles |
| POST | `/api/user/language/` | Set language |
| GET | `/api/languages/` | Supported |
| GET | `/api/user/language/get/` | Current language |

### Privacy

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/api/privacy/request-account-deletion/` | Deletion request |
| POST | `/api/privacy/request-data-export/` | Data export request |

### Email / EmailJS

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/api/email/send/`, `/api/email/send-template/`, `/api/email/test-connection/` | Email |
| GET | `/api/email/templates/` | Templates |
| POST | `/api/email/welcome/`, `/api/email/appointment-confirmation/` | Templated flows |
| POST, GET | `/api/emailjs/*` | EmailJS wrappers |

### Chat

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/api/chat/` | Chat |
| GET | `/api/chat/history/` | History |

### Map config

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/map-config/` | Map configuration |
| GET | `/api/config/api-keys/` | Client-visible keys |

### Legacy

| GET | `/api/hospital-finder/` | Legacy hospital finder |

---

### 🔐 Simple unified auth (duplicate paths — usually shadowed)

Included at the end of `api/urls.py`. **`/api/auth/login/`** and **`/api/auth/register/`** are normally handled by **`api.views`** earlier. Prefer these **additional** URLs from the simple module:

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/auth/user-info/` | User info |
| GET | `/api/auth/demo-accounts/` | Demo accounts |
| POST | `/api/auth/test-demo-login/` | Demo login |

---

### 🏥 Clinical / Doctor APIs (`include('api.doctor_urls')`)

Mounted under **`/api/`** after core patterns; **`/api/medical-records/`** is already bound to **`api.views`** first—doctor module record list applies only if you add non-conflicting paths.

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/doctors/` | Doctor list |
| GET | `/api/doctors/<uuid>/` | Doctor detail |
| GET | `/api/doctors/specialization/<str>/` | By specialization |
| GET | `/api/assessments/` | Health assessments |
| GET | `/api/assessments/high-risk/` | High risk |
| GET | `/api/appointments/` | Appointments |
| GET | `/api/medications/` | Medications |
| GET | `/api/medications/active/` | Active meds |
| GET | `/api/lab-results/` | Lab results |
| GET | `/api/lab-results/abnormal/` | Abnormal labs |
| GET | `/api/dashboard/stats/` | Dashboard stats |

---

### 🩺 Vitals (`api.vitals_urls` under `/api/`)

| Method | Path | Purpose |
|--------|------|---------|
| GET, POST | `/api/vitals/` | List/create |
| GET, PATCH, DELETE | `/api/vitals/<uuid>/` | Detail |
| GET | `/api/vitals/patient/<uuid>/` | Patient vitals |
| GET | `/api/vitals/summary/` | Summary |
| GET | `/api/vitals/high-risk/` | High risk |
| GET | `/api/vitals/phq9-screening/` | PHQ-9 screening |
| GET | `/api/vitals/health/` | Vitals service health |

---

### 🥗 Nutrition Track (`/api/nutrition/`)

Stable **v1** paths are preferable for Flutter contracts.

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/nutrition/health/`, `/api/nutrition/readyz/` | Liveness / readiness |
| POST | `/api/nutrition/analyze/` | Food analyze |
| POST | `/api/nutrition/ocr/` | OCR |
| POST | `/api/nutrition/barcode/analyze/` | Barcode |
| GET | `/api/nutrition/model/info/` | Model info |
| GET | `/api/nutrition/lookup/` | Nutrition lookup |
| POST | `/api/nutrition/halal-check/` | Halal check |
| POST | `/api/nutrition/ai/train/`, `/api/nutrition/ai/insights/`, `/api/nutrition/ai/batch-analyze/` | AI / batch (placeholders where noted in code) |
| GET | `/api/nutrition/v1/health/`, `/v1/readyz/` | Versioned probes |
| POST | `/api/nutrition/v1/analyze/`, `/v1/ocr/`, `/v1/barcode/analyze/` | Versioned analyze |
| GET | `/api/nutrition/v1/model/info/` | Versioned model |
| GET | `/api/nutrition/v1/lookup/` | Versioned lookup |
| POST | `/api/nutrition/v1/halal/check/` | Versioned halal |
| GET | `/api/nutrition/v1/restaurants/`, `/v1/recipes/` | Restaurants / recipes |
| GET | `/api/nutrition/v1/restaurants/favorites/` | Favorites |
| GET | `/api/nutrition/v1/restaurants/reviews/` | Reviews |

---

### 🧠 AI Services (`include('ai_services.urls')` at `/api/ai/` — ICD, meds, symptoms)

These coexist with `/api/ai/ml/…` routes from **`api.urls`** because Django resolves the **more specific** entries in **`api.urls`** first; ICD/medication routes use **different suffixes**.

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/api/ai/icd10/validate/` | ICD-10 validation |
| GET | `/api/ai/icd10/search/` | ICD search |
| GET | `/api/ai/medication/search/` | Medication search |
| POST | `/api/ai/symptoms/analyze/` | Symptom analysis |
| GET | `/api/ai/health/` | Service health (**ai_services**) |

---

### 🧪 Lab management (`/lab/` — separate base path)

JWT at `/lab/auth/token/`, `/lab/auth/token/refresh/`; legacy session auth under `/lab/auth/login/` etc.; router resources: **`/lab/users/`**, **`/lab/patients/`**, **`/lab/tests/`**, **`/lab/test-orders/`**, **`/lab/test-results/`**, **`/lab/appointments/`**, **`/lab/payments/`**, **`/lab/reports/`**, **`/lab/settings/`**, **`/lab/audit-logs/`**, … See `lab_management/urls.py`. Flutter EMR integrations that need lab orders should configure a **second Dio base URL** (`/lab/`) or path prefix.

---

### 💳 SadaqaWorks / Wallet (`include('sadaqaworks.urls')` under `/api/`)

Wallet and charity site APIs live under **`/api/wallet/*`** and **`/api/sadaqaworks/*`** (includes separate auth endpoints). Token rules may follow wallet view mixins—see `sadaqaworks/views.py`.

---

## 📝 **Notes**

1. **Rate Limiting**: 
   - Anonymous: 100 requests/hour
   - Authenticated: 1000 requests/hour

2. **Caching**: 
   - Hospital search results are cached for 5 minutes
   - Hospital list is cached for 15 minutes

3. **Pagination**: 
   - Default page size: 20 items
   - Use `limit` and `offset` for pagination

4. **Hospital Types**:
   - `emergency`: Emergency Rooms
   - `urgent_care`: Urgent Care Centers
   - `clinic`: Medical Clinics
   - `general`: General Hospitals
   - `trauma`: Trauma Centers
   - `pediatric`: Pediatric Hospitals

5. **Priority Sorting**: Hospitals are automatically sorted by type priority (Emergency first, then Urgent Care, etc.)

6. **Distance Calculation**: All distances are in **miles** (not kilometers)

7. **Coordinates**: 
   - Latitude: -90 to 90
   - Longitude: -180 to 180

---

## ✅ **Quick Start Checklist**

- [ ] Set API base URL (development or production)
- [ ] Configure CORS if needed (usually handled by backend)
- [ ] Implement authentication (prefer **DRF Token** for `/api/`; JWT only where that flow applies, e.g. `/lab/` token endpoints)
- [ ] Add error handling
- [ ] Implement hospital search with GPS coordinates
- [ ] Add hospital detail view
- [ ] Implement feedback submission
- [ ] Add user analytics tracking
- [ ] Wire ER-time analytics (`/api/analytics/er-time/interaction/` and related) for robust wait-time UX
- [ ] Point nutrition flows to **`/api/nutrition/v1/`** for stable contracts; use `/api/analyze/` only for legacy Diet101 if needed
- [ ] Add Vitals + clinical (`/api/vitals/`, `/api/doctors/`, …) for EMR features; use **`/lab/`** base URL for lab orders/results
- [ ] Test all endpoints
- [ ] Handle loading and error states

---

**Last Updated**: May 6, 2026
**Backend Version**: 1.0.0
**API Version**: v1
