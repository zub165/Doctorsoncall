#!/usr/bin/env bash
set -euo pipefail
# Canonical production API — change here (and FRONTEND_API_DOCUMENTATION.md §2.1) if hostname moves.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT/flutter_emr"
exec flutter run \
  --dart-define=API_BASE_URL=https://api.mywaitime.com/api/ \
  --dart-define=API_USER_ME_PATH=user-data/ \
  "$@"
