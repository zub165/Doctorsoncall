#!/usr/bin/env bash
set -euo pipefail
# Production / TestFlight / Play Store — use this script for API dart-defines.
#
# App URLs (never :3015, :8012, or 127.0.0.1 in release):
#   EMR_API_BASE_URL  → https://api.docsoncalls.com/api/  (override: FLUTTER_EMR_API_BASE_URL)
#   MAPS_API_BASE_URL → same as EMR (hospitals/search/ proxied to MyWaitime :3015 on VPS)
#     Optional override: FLUTTER_MAPS_API_BASE_URL=... on flutter run/build only
#
# VPS: nginx :443 → gunicorn 127.0.0.1:8012; django_emr .env MYWAITIME_UPSTREAM_API_BASE =
#   https://api.mywaitime.com/api/  OR  http://127.0.0.1:3015/api/  (server-side only)
#
# Local sim: ./scripts/flutter_run_ios_simulator_local_api.sh (8012 + 3015)
# RUN_API_SMOKE=1 — quick production login + hospitals check before launch
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EMR_API_BASE_URL="${FLUTTER_EMR_API_BASE_URL:-${FLUTTER_API_BASE_URL:-https://api.docsoncalls.com/api/}}"
# Subscriptions: direct App Store / Google Play (in_app_purchase); Stripe for doctor bills / web checkout
if [[ -f "$ROOT/.env" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ROOT/.env" 2>/dev/null || true
  set +a
fi
MAPS_DEFINES=()
[[ -n "${FLUTTER_MAPS_API_BASE_URL:-}" ]] && MAPS_DEFINES+=(--dart-define=MAPS_API_BASE_URL="${FLUTTER_MAPS_API_BASE_URL}")
cd "$ROOT/flutter_emr"

if [[ "${RUN_API_SMOKE:-0}" == "1" ]]; then
  echo "Running production API smoke (doc_admin test user)…"
  /usr/bin/python3 << 'PY'
import json, urllib.request, sys
API = "https://api.docsoncalls.com/api/"
def post(path, data):
    req = urllib.request.Request(API + path, data=json.dumps(data).encode(),
        headers={"Content-Type": "application/json"}, method="POST")
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read().decode())
def get(path, token):
    req = urllib.request.Request(API + path, headers={"Authorization": f"Token {token}"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read().decode())
ok, body = True, post("auth/login/", {"email": "doc_admin@example.com", "password": "DoctorAdmin2026!",
    "portal": "administrator", "role": "administrator"})
if body.get("status") != "success":
    print("FAIL admin login:", body.get("message")); sys.exit(1)
token = body["data"]["token"]
h = get("hospitals/", token)
n = len((h.get("data") or {}).get("results") or [])
print(f"PASS admin login; hospitals={n}")
if n < 1: sys.exit(1)
PY
fi

# Store release builds (Play AAB + App Store IPA) — same production API:
#   ./scripts/flutter_run_production_api.sh build
if [[ "${1:-}" == "build" ]]; then
  shift
  echo "==> Production store build v$(grep '^version:' pubspec.yaml | awk '{print $2}')"
  echo "    App: Doctor On Call / Doctersoncall ONLY (App Store 6767928390)"
  echo "    NOT DocSchedule (6752506189) — upload only this repo's IPA/AAB"
  echo "    iOS bundle: com.doctoroncall.emr (App Store 6767928390)"
  echo "    Android: com.doctoroncall.emr (Play: Doctoroncall)"
  echo "    EMR:  $EMR_API_BASE_URL"
  if [[ ${#MAPS_DEFINES[@]} -gt 0 ]]; then
    echo "    Maps: ${FLUTTER_MAPS_API_BASE_URL} (override)"
  else
    echo "    Hospitals: via EMR nginx → MyWaitime :3015 (MAPS_API_BASE_URL defaults to EMR)"
  fi
  echo "    Subscriptions: direct App Store / Google Play (in_app_purchase) + Stripe for extra visits"
  flutter pub get
  flutter build appbundle --release \
    --dart-define=EMR_API_BASE_URL="$EMR_API_BASE_URL" \
    --dart-define=API_USER_ME_PATH=user-data/ \
    ${MAPS_DEFINES[@]+"${MAPS_DEFINES[@]}"} \
    "$@"
  flutter build ipa --release \
    --dart-define=EMR_API_BASE_URL="$EMR_API_BASE_URL" \
    --dart-define=API_USER_ME_PATH=user-data/ \
    ${MAPS_DEFINES[@]+"${MAPS_DEFINES[@]}"} \
    "$@"
  echo ""
  echo "AAB: build/app/outputs/bundle/release/app-release.aab"
  IPA_DIR="build/ios/ipa"
  shopt -s nullglob
  ipa_files=("${IPA_DIR}"/*.ipa)
  shopt -u nullglob
  ipa_out=""
  if [[ ${#ipa_files[@]} -gt 0 ]]; then
    ipa_out="${ipa_files[0]}"
    for f in "${ipa_files[@]}"; do
      [[ "$f" -nt "$ipa_out" ]] && ipa_out="$f"
    done
  fi
  echo "IPA: ${ipa_out:-build/ios/ipa/*.ipa} (App Store: Doctersoncall, bundle com.doctoroncall.emr)"
  exit 0
fi

exec flutter run \
  --dart-define=EMR_API_BASE_URL="$EMR_API_BASE_URL" \
  --dart-define=API_USER_ME_PATH=user-data/ \
  ${MAPS_DEFINES[@]+"${MAPS_DEFINES[@]}"} \
  "$@"
