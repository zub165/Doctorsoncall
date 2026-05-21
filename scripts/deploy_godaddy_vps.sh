#!/usr/bin/env bash
# Deploy django_emr to GoDaddy VPS (api.docsoncalls.com -> nginx :443 -> gunicorn :8012)
#
# Usage:
#   ./scripts/deploy_godaddy_vps.sh
#   DEPLOY_SSH=user@host DEPLOY_REMOTE_DIR=/path ./scripts/deploy_godaddy_vps.sh
#
# Notes:
# - Do NOT `source .env` in SSH (a bad line there can break the shell with "time: missing program").
# - Django loads django_emr/.env via emergencytime/settings.py on manage.py / gunicorn start.
# - Email on VPS .env (not rsynced). Recommended:
#     EMAIL_HOST=dedrelay.secureserver.net
#     EMAIL_PORT=25
#     EMAIL_USE_TLS=false
#     DEFAULT_FROM_EMAIL=noreply@docsoncalls.com
#     SUPPORT_EMAIL=info@innovatorsgeneration.com
#   Test: python manage.py send_test_email you@email.com && pm2 restart django-emr-api --update-env
#   Smoke: ./scripts/test_docsoncalls_production.sh
# - Remote SSH uses bash --noprofile --norc (server .bashrc can break non-interactive sessions).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REMOTE="${DEPLOY_SSH:-godaddy-server}"
REMOTE_DIR="${DEPLOY_REMOTE_DIR:-/home/newgen/django_emr}"

echo "==> Rsync django_emr -> ${REMOTE}:${REMOTE_DIR}"
rsync -avz --delete \
  --exclude 'venv/' \
  --exclude '.env' \
  --exclude 'db.sqlite3' \
  --exclude '__pycache__/' \
  --exclude '*.pyc' \
  --exclude 'media/' \
  --exclude 'staticfiles/' \
  --exclude '.git/' \
  "${ROOT}/django_emr/" "${REMOTE}:${REMOTE_DIR}/"

echo "==> Remote: migrate, collectstatic, restart gunicorn :8012"
ssh "${REMOTE}" bash --noprofile --norc -s <<EOF
set -euo pipefail
cd '${REMOTE_DIR}'
source venv/bin/activate
pip install -q -r requirements.txt 2>/dev/null || true
python manage.py check
python manage.py migrate --noinput
python manage.py collectstatic --noinput
pkill -f 'gunicorn.*0.0.0.0:8012' 2>/dev/null || true
/bin/sleep 2
nohup bash --noprofile --norc -c 'cd "${REMOTE_DIR}" && source venv/bin/activate && exec gunicorn --bind 0.0.0.0:8012 --workers 2 --threads 2 --timeout 120 emergencytime.wsgi:application' \
  >> "${REMOTE_DIR}/gunicorn.log" 2>&1 &
/bin/sleep 2
curl -s -o /dev/null -w "local welcome: %{http_code}\n" http://127.0.0.1:8012/api/welcome/
EOF

echo "==> Ensure nginx serves /static/ (reload only if block was missing)"
ssh "${REMOTE}" 'bash --noprofile --norc -s' <<'NGINX_EOF'
  set -euo pipefail
  NGINX_SITE="/etc/nginx/sites-enabled/api.docsoncalls.com"
  if [ ! -f "$NGINX_SITE" ]; then
    echo "nginx site not found: $NGINX_SITE (skip)"
    exit 0
  fi
  if grep -q "location /static/" "$NGINX_SITE"; then
    echo "nginx /static/ already configured"
    exit 0
  fi
  sudo sed -i "/location \\/api\\//i\\
    location /static/ {\\
        alias /home/newgen/django_emr/staticfiles/;\\
        expires 30d;\\
        add_header Cache-Control \"public\";\\
    }\\
" "$NGINX_SITE"
  sudo nginx -t
  sudo systemctl reload nginx
  echo "nginx reloaded"
NGINX_EOF

echo "==> Public checks (via nginx -> gunicorn)"
curl -s -o /dev/null -w "welcome: %{http_code}\n" https://api.docsoncalls.com/api/welcome/
curl -s -o /dev/null -w "billing admin (expect 401): %{http_code}\n" https://api.docsoncalls.com/api/billing/admin/summary/
curl -s -o /dev/null -w "stripe-connect (expect 401): %{http_code}\n" -X POST https://api.docsoncalls.com/api/billing/doctor/stripe-connect/
curl -s -o /dev/null -w "static css: %{http_code}\n" https://api.docsoncalls.com/static/rest_framework/css/bootstrap.min.css
curl -s "https://api.docsoncalls.com/api/tomtom/status/" | python3 -c "import sys,json; d=json.load(sys.stdin); print('tomtom:', d.get('message'), d.get('data'))" 2>/dev/null || echo "tomtom: check manually"

echo "Done. API: https://api.docsoncalls.com/api/welcome/"
