#!/bin/sh
set -eu
check_dir=$(mktemp -d)
trap 'rm -rf "$check_dir"' EXIT
curl -fsS http://127.0.0.1:3001/gis_smoke/0/0/0 -o "$check_dir/postgis"
curl -fsS http://127.0.0.1:3001/gis_smoke_archive/0/0/0 -o "$check_dir/pmtiles"
curl -fsSG 'http://127.0.0.1:8001/cog/tiles/WebMercatorQuad/0/0/0.png' --data-urlencode 'url=s3://raster-data/gis_smoke.tif' -o "$check_dir/raster"
test -s "$check_dir/postgis"
test -s "$check_dir/pmtiles"
test "$(od -An -tx1 -N8 "$check_dir/raster" | tr -d ' \n')" = 89504e470d0a1a0a
code=$(curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:9000/raster-data/gis_smoke.tif)
test "$code" = 403
