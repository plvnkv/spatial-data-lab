#!/bin/sh
set -eu

alert_state() {
  alerts=$(curl -fsS http://127.0.0.1:9093/api/v2/alerts) || return 1
  printf '%s\n' "$alerts" |
    python3 -c 'import json,sys; print("active" if any(row["labels"].get("alertname") == "GISServiceUnavailable" and "titiler:8000/" in row["labels"].get("instance","") for row in json.load(sys.stdin)) else "clear")'
}

wait_for_alert_state() {
  attempt=0
  while [ "$attempt" -lt 30 ]; do
    state=$(alert_state) || return 1
    if [ "$state" = "$1" ]; then
      printf 'TiTiler alert: %s\n' "$state"
      return 0
    fi
    attempt=$((attempt + 1))
    sleep 5
  done
  return 1
}

wait_for_alert_state clear
trap 'docker compose start titiler >/dev/null' EXIT
docker compose stop titiler
wait_for_alert_state active
docker compose start titiler
wait_for_alert_state clear
trap - EXIT
