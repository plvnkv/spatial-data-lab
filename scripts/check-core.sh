#!/bin/sh
set -eu
docker compose config -q
curl -fsS http://127.0.0.1:8088/ -o /dev/null
curl -fsS 'http://127.0.0.1:8088/geoserver/ows?service=WMS&request=GetCapabilities' | grep -q WMS_Capabilities
