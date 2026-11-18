#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "$0")/.."
unset SD_LAB_HOST SD_LAB_ORIGIN SD_LAB_POSTGIS_PLATFORM
exec docker compose --env-file .env --env-file /etc/sd-lab/lan.env \
    -f compose.yaml -f bootstrap/compose.https.yaml "$@"
