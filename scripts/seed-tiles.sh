#!/bin/sh
set -eu
fixture_dir=$(mktemp -d)
trap 'rm -rf "$fixture_dir"' EXIT

docker compose exec -T db sh -ec 'export PGPASSWORD="$POSTGRES_PASS"; exec psql -h 127.0.0.1 -U postgres -d geonode_data -v ON_ERROR_STOP=1' <<'SQL'
SET ROLE geonode_data;
CREATE TABLE IF NOT EXISTS public.gis_smoke (
  id integer PRIMARY KEY,
  name text NOT NULL,
  geom geometry(Point, 4326) NOT NULL
);
INSERT INTO public.gis_smoke VALUES (1, 'Kyiv', ST_SetSRID(ST_MakePoint(30.52, 50.45), 4326))
ON CONFLICT (id) DO NOTHING;
SQL
docker compose restart martin
curl --retry 12 --retry-all-errors --retry-delay 2 -fsS http://127.0.0.1:3001/gis_smoke/0/0/0 -o "$fixture_dir/tile.mvt"
test -s "$fixture_dir/tile.mvt"

python3 - "$fixture_dir" <<'PY'
import gzip
import struct
import sys
from pathlib import Path

fixtures = Path(sys.argv[1])
tile = (fixtures / "tile.mvt").read_bytes()
# One directory entry: tile ID 0, run length 1, variable-length tile size, offset 0 encoded as 1.
size = len(tile)
varint = bytearray()
while size > 127:
    varint.append((size & 127) | 128)
    size >>= 7
varint.append(size)
directory = gzip.compress(bytes([1, 0, 1]) + varint + bytes([1]))
metadata = gzip.compress(b'{"name":"GIS smoke test","vector_layers":[{"id":"gis_smoke","fields":{"name":"String"}}]}')
metadata_start = 127 + len(directory)
tile_start = metadata_start + len(metadata)
header = b"PMTiles\x03" + struct.pack(
    "<11Q6B4iB2i",
    127, len(directory), metadata_start, len(metadata), tile_start, 0,
    tile_start, len(tile), 1, 1, 1,
    1, 2, 1, 1, 0, 0,
    -1800000000, -850000000, 1800000000, 850000000, 0, 305200000, 504500000,
)
(fixtures / "gis_smoke_archive.pmtiles").write_bytes(header + directory + metadata + tile)
PY

docker compose exec -T titiler python - > "$fixture_dir/gis_smoke.tif" <<'PY'
import sys
import numpy as np
from rasterio.io import MemoryFile
from rasterio.transform import from_bounds

with MemoryFile() as memory:
    with memory.open(driver="COG", width=256, height=256, count=1, dtype="uint8",
                     crs="EPSG:3857", transform=from_bounds(-20037508, -20037508, 20037508, 20037508, 256, 256)) as dataset:
        dataset.write(np.full((1, 256, 256), 90, dtype="uint8"))
    sys.stdout.buffer.write(memory.read())
PY

upload() {
  docker compose run --rm --no-deps -T --entrypoint aws init-buckets \
    --endpoint-url http://rustfs:9000 s3 cp - "s3://$1/$2" < "$fixture_dir/$2"
}
upload vector-tiles gis_smoke_archive.pmtiles
upload raster-data gis_smoke.tif
docker compose restart martin
