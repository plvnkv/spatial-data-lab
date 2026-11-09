#!/bin/sh
set -eu
query() {
  curl -fsSG http://127.0.0.1:9090/api/v1/query --data-urlencode "query=$1"
}
probes=$(query 'probe_success and (time() - timestamp(probe_success) < 35)')
printf '%s\n' "$probes" |
  python3 -c 'import json,sys; rows=json.load(sys.stdin)["data"]["result"]; assert len(rows)==9 and all(row["value"][1]=="1" for row in rows), rows'
targets=$(query 'up and (time() - timestamp(up) < 35)')
printf '%s\n' "$targets" |
  python3 -c 'import json,sys; rows=json.load(sys.stdin)["data"]["result"]; assert len(rows)==15 and all(row["value"][1]=="1" for row in rows), rows'
logs=$(curl -fsSG http://127.0.0.1:3100/loki/api/v1/query_range --data-urlencode 'query={service="geoserver"}')
printf '%s\n' "$logs" |
  python3 -c 'import json,sys; assert json.load(sys.stdin)["data"]["result"], "GeoServer logs are missing"'
curl -fsS http://127.0.0.1:3000/api/health -o /dev/null
curl -fsS http://127.0.0.1:9093/-/ready -o /dev/null
