#!/usr/bin/env bash
set -euo pipefail
# iOS Simulator reaches Django on the Mac via 127.0.0.1 (not 10.0.2.2).
# Start Django first, e.g.: cd django_emr && python manage.py runserver 127.0.0.1:${LOCAL_API_PORT:-8012}
export LANG="${LANG:-en_US.UTF-8}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${LOCAL_API_PORT:-8012}"
MAPS_PORT="${LOCAL_MAPS_PORT:-3015}"
cd "$ROOT/flutter_emr"
exec flutter run \
  --dart-define=EMR_API_BASE_URL="http://127.0.0.1:${PORT}/api/" \
  --dart-define=MAPS_API_BASE_URL="http://127.0.0.1:${MAPS_PORT}/api/" \
  --dart-define=API_USER_ME_PATH=user-data/ \
  ${RC_DEFINES[@]+"${RC_DEFINES[@]}"} \
  "$@"
