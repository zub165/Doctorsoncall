#!/usr/bin/env bash
set -euo pipefail
# Override: FLUTTER_API_BASE_URL=https://api.mywaitime.com/api/
# VPS Django example: FLUTTER_API_BASE_URL=http://208.109.215.53:8012/api/
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
API_BASE_URL="${FLUTTER_API_BASE_URL:-https://api.mywaitime.com/api/}"
cd "$ROOT/flutter_emr"
exec flutter run \
  --dart-define=API_BASE_URL="$API_BASE_URL" \
  --dart-define=API_USER_ME_PATH=user-data/ \
  "$@"
