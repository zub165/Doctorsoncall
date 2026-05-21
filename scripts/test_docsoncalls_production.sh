#!/usr/bin/env bash
# Quick production checks: API health (email config), login, password-reset, Finder hospitals.
set -euo pipefail
API="${EMR_API_BASE_URL:-https://api.docsoncalls.com/api/}"
echo "==> EMR API: $API"

echo "==> Health + email config"
curl -s "${API}health/" | python3 -c "
import json,sys
d=json.load(sys.stdin)
e=(d.get('data') or {}).get('email') or {}
print('  smtp_configured:', e.get('smtp_configured'))
print('  host:', e.get('host'))
print('  from:', e.get('from_email'))
print('  support:', e.get('support_email'))
print('  reset_base:', e.get('reset_link_base'))
"

echo "==> Admin login"
TOKEN=$(curl -s -X POST "${API}auth/login/" \
  -H "Content-Type: application/json" \
  -d '{"email":"doc_admin@example.com","password":"DoctorAdmin2026!","portal":"administrator","role":"administrator"}' \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['data']['token'])")
echo "  token: ${TOKEN:0:12}..."

echo "==> Password reset request (doc_admin@example.com)"
curl -s -X POST "${API}auth/password-reset/request/" \
  -H "Content-Type: application/json" \
  -d '{"email":"doc_admin@example.com"}' | python3 -m json.tool

echo "==> Finder hospitals (Clearwater FL)"
curl -s "https://api.mywaitime.com/api/hospitals/search/?lat=27.9659&lon=-82.8001" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print('  count:', len(d.get('results') or []), 'source:', d.get('source'))"

echo "Done. Check inbox/spam for reset mail from noreply@docsoncalls.com (if SMTP on VPS)."
