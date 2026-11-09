#!/bin/sh
set -eu

s3() {
  aws --endpoint-url http://rustfs:9000 s3api "$@"
}

for bucket in vector-tiles raster-data; do
  if ! s3 head-bucket --bucket "$bucket" >/dev/null 2>&1; then
    s3 create-bucket --bucket "$bucket" >/dev/null
  fi
done
