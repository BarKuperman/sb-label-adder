#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
PRIMARY_OVERPASS="https://maps.mail.ru/osm/tools/overpass/api/interpreter"
FALLBACK_OVERPASS="https://overpass-api.de/api/interpreter"

BASE_MAP=""
BBOX=""
OUTPUT=""
WORKDIR=""
PREFER_ENGLISH=0
FORCE_ENGLISH=0
SUBURBS_AS_NEIGHBORHOODS=0

log() {
  printf '[label-adder] %s\n' "$1"
}

die() {
  printf '[label-adder] ERROR: %s\n' "$1" >&2
  exit 1
}

usage() {
  cat <<EOF
Usage:
  $SCRIPT_NAME --base-map <path> [options]

Required:
  --base-map <path>              Path to base .pmtiles file

Optional:
  --bbox "south,west,north,east"  Override bbox (auto-inferred if omitted)
  --output <path>                Output .pmtiles path (default: <workdir>/final_map.pmtiles)
  --workdir <dir>                Working directory (default: base map directory)
  --prefer-english               Prefer name:en for labels when available
  --force-english                Use only name:en labels (drop features without name:en)
  --san                          Combine suburbs into the neighborhoods layer
  -h, --help                     Show this help
EOF
}

require_command() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    die "Missing required command '$cmd'."
  fi
}

abs_path() {
  local p="$1"
  if command -v realpath >/dev/null 2>&1; then
    realpath "$p"
  else
    python3 - "$p" <<'PY'
import os,sys
print(os.path.abspath(sys.argv[1]))
PY
  fi
}

convert_wsl_path() {
  local p="$1"
  if [[ -z "$p" ]]; then
    printf "%s\n" "$p"
    return 0
  fi
  if command -v wslpath >/dev/null 2>&1; then
    if [[ "$p" =~ ^[A-Za-z]:[\\/] ]] || [[ "$p" =~ ^\\\\[a-zA-Z0-9] ]]; then
      wslpath -u "$p"
      return 0
    fi
  fi
  printf "%s\n" "$p"
}

install_tippecanoe() {
  log "Installing tippecanoe in Ubuntu (may ask for sudo password)..."
  sudo apt update
  sudo apt install build-essential libsqlite3-dev zlib1g-dev git -y

  if [[ ! -d "$HOME/tippecanoe" ]]; then
    git clone https://github.com/felt/tippecanoe.git "$HOME/tippecanoe"
  fi

  cd "$HOME/tippecanoe"
  git pull --ff-only || true
  make -j
  sudo make install
}

prompt_install_tippecanoe() {
  while true; do
    printf '[label-adder] tippecanoe/tile-join are not installed. Install now? [y/n]: '
    read -r reply
    case "${reply,,}" in
      y|yes)
        install_tippecanoe
        return 0
        ;;
      n|no)
        die "tippecanoe/tile-join are required to continue."
        ;;
      *)
        log "Please type 'y' or 'n'."
        ;;
    esac
  done
}

validate_bbox() {
  local bb="$1"
  python3 - "$bb" <<'PY'
import sys
s = sys.argv[1]
parts = [p.strip() for p in s.split(',')]
if len(parts) != 4:
    raise SystemExit(1)
try:
    south, west, north, east = map(float, parts)
except Exception:
    raise SystemExit(1)
if not (-90 <= south <= 90 and -90 <= north <= 90 and -180 <= west <= 180 and -180 <= east <= 180):
    raise SystemExit(1)
if not (south < north):
    raise SystemExit(1)
if not (west < east):
    raise SystemExit(1)
print(f"{south},{west},{north},{east}")
PY
}

infer_bbox_from_pmtiles() {
  local pmtiles_path="$1"
  python3 - "$pmtiles_path" <<'PY'
import gzip
import json
import struct
import sys

path = sys.argv[1]

def fail(msg):
    print(msg, file=sys.stderr)
    raise SystemExit(1)

def valid_bbox(south, west, north, east):
    if not (-90 <= south <= 90 and -90 <= north <= 90):
        return False
    if not (-180 <= west <= 180 and -180 <= east <= 180):
        return False
    if not (south < north):
        return False
    if not (west < east):
        return False
    return True

with open(path, 'rb') as f:
    header = f.read(127)

if len(header) != 127:
    fail("PMTiles header too short")

if header[:7] != b'PMTiles':
    fail("Not a PMTiles file (missing magic bytes)")

version = header[7]
if version != 3:
    fail(f"Unsupported PMTiles version: {version}")

# PMTiles v3 header layout per spec:
# min_position starts at byte 102 and is encoded as lon(int32 LE), lat(int32 LE).
# max_position starts at byte 110 and is encoded as lon(int32 LE), lat(int32 LE).
min_lon_e7 = struct.unpack_from('<i', header, 102)[0]
min_lat_e7 = struct.unpack_from('<i', header, 106)[0]
max_lon_e7 = struct.unpack_from('<i', header, 110)[0]
max_lat_e7 = struct.unpack_from('<i', header, 114)[0]

south = min_lat_e7 / 1e7
west = min_lon_e7 / 1e7
north = max_lat_e7 / 1e7
east = max_lon_e7 / 1e7

if valid_bbox(south, west, north, east):
    print(f"{south},{west},{north},{east}")
    raise SystemExit(0)

# Fallback to metadata.bounds (TileJSON order: west,south,east,north)
metadata_offset = struct.unpack_from('<Q', header, 24)[0]
metadata_length = struct.unpack_from('<Q', header, 32)[0]
internal_compression = header[97]

if metadata_length == 0:
    fail("Header bbox invalid and metadata block is empty")

with open(path, 'rb') as f:
    f.seek(metadata_offset)
    raw_metadata = f.read(metadata_length)

if len(raw_metadata) != metadata_length:
    fail("Could not read full metadata block")

if internal_compression == 2:
    try:
        raw_metadata = gzip.decompress(raw_metadata)
    except Exception as ex:
        fail(f"Failed to decompress metadata: {ex}")
elif internal_compression not in (1,):
    fail(f"Unsupported internal compression code: {internal_compression}")

try:
    metadata = json.loads(raw_metadata.decode('utf-8'))
except Exception as ex:
    fail(f"Failed to parse metadata JSON: {ex}")

bounds = metadata.get('bounds')
if bounds is None:
    fail("Header bbox invalid and metadata.bounds is missing")

try:
    if isinstance(bounds, str):
        west, south, east, north = [float(x.strip()) for x in bounds.split(',')]
    elif isinstance(bounds, (list, tuple)) and len(bounds) == 4:
        west, south, east, north = [float(x) for x in bounds]
    else:
        fail("metadata.bounds has unsupported format")
except Exception:
    fail("metadata.bounds could not be parsed into 4 numbers")

if not valid_bbox(south, west, north, east):
    fail("Both header bbox and metadata.bounds are invalid")

print(f"{south},{west},{north},{east}")
PY
}

query_overpass_json() {
  local query="$1"
  local out_json="$2"
  local endpoints=("$PRIMARY_OVERPASS" "$FALLBACK_OVERPASS")
  local attempts=2

  for endpoint in "${endpoints[@]}"; do
    for ((i=1; i<=attempts; i++)); do
      log "Overpass request attempt $i/$attempts via $endpoint"
      if curl --silent --show-error --fail --max-time 120 \
        -H 'Content-Type: text/plain; charset=utf-8' \
        --data "$query" \
        "$endpoint" > "$out_json"; then
        return 0
      fi
      log "Overpass attempt failed at $endpoint"
    done
  done

  die "All Overpass endpoints failed. Tried: $PRIMARY_OVERPASS then $FALLBACK_OVERPASS"
}

build_query() {
  local places_csv="$1"
  python3 - "$BBOX" "$places_csv" <<'PY'
import sys
bbox = sys.argv[1]
places = [p.strip() for p in sys.argv[2].split(',') if p.strip()]
body = "\n".join([f'  node["place"="{p}"];' for p in places])
print(f"[out:json][timeout:60][bbox:{bbox}];\n(\n{body}\n);\nout body;")
PY
}

overpass_to_geojson() {
  local in_json="$1"
  local out_geojson="$2"
  local prefer_english="$3"
  local force_english="$4"

  python3 - "$in_json" "$out_geojson" "$prefer_english" "$force_english" <<'PY'
import json
import sys

input_path = sys.argv[1]
output_path = sys.argv[2]
prefer_english = sys.argv[3] == '1'
force_english = sys.argv[4] == '1'

with open(input_path, 'r', encoding='utf-8') as f:
    data = json.load(f)

features = []
for el in data.get('elements', []):
    if el.get('type') != 'node':
        continue
    tags = el.get('tags') or {}

    name = None
    if force_english:
        name = tags.get('name:en')
    elif prefer_english:
        name = tags.get('name:en') or tags.get('name')
    else:
        name = tags.get('name') or tags.get('name:en')

    if not name:
        continue

    lat = el.get('lat')
    lon = el.get('lon')
    if lat is None or lon is None:
        continue

    features.append({
        'type': 'Feature',
        'properties': {'name': str(name)},
        'geometry': {'type': 'Point', 'coordinates': [float(lon), float(lat)]}
    })

collection = {'type': 'FeatureCollection', 'features': features}
with open(output_path, 'w', encoding='utf-8') as f:
    json.dump(collection, f, ensure_ascii=False)

print(len(features))
PY
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-map)
      [[ $# -lt 2 ]] && die "--base-map requires a value"
      BASE_MAP="$2"
      shift 2
      ;;
    --bbox)
      [[ $# -lt 2 ]] && die "--bbox requires a value"
      BBOX="$2"
      shift 2
      ;;
    --output)
      [[ $# -lt 2 ]] && die "--output requires a value"
      OUTPUT="$2"
      shift 2
      ;;
    --workdir)
      [[ $# -lt 2 ]] && die "--workdir requires a value"
      WORKDIR="$2"
      shift 2
      ;;
    --prefer-english)
      PREFER_ENGLISH=1
      shift
      ;;
    --force-english)
      FORCE_ENGLISH=1
      shift
      ;;
    --san)
      SUBURBS_AS_NEIGHBORHOODS=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

[[ -z "$BASE_MAP" ]] && { usage; die "--base-map is required"; }

require_command python3
require_command curl

BASE_MAP="$(convert_wsl_path "$BASE_MAP")"
WORKDIR="$(convert_wsl_path "$WORKDIR")"
OUTPUT="$(convert_wsl_path "$OUTPUT")"

BASE_MAP="$(abs_path "$BASE_MAP")"
[[ -f "$BASE_MAP" ]] || die "Base map file not found: $BASE_MAP"
[[ "$BASE_MAP" == *.pmtiles ]] || die "Base map must end with .pmtiles"

if [[ -z "$WORKDIR" ]]; then
  WORKDIR="$(dirname "$BASE_MAP")"
fi
WORKDIR="$(abs_path "$WORKDIR")"
mkdir -p "$WORKDIR"

if [[ -z "$OUTPUT" ]]; then
  OUTPUT="$WORKDIR/final_map.pmtiles"
fi
OUTPUT="$(abs_path "$OUTPUT")"

if [[ -z "$BBOX" ]]; then
  log "Inferring bbox from PMTiles header..."
  if ! BBOX="$(infer_bbox_from_pmtiles "$BASE_MAP")"; then
    die "Failed to infer bbox from '$BASE_MAP'. Pass --bbox \"south,west,north,east\" manually."
  fi
fi

if ! BBOX="$(validate_bbox "$BBOX")"; then
  die "Invalid bbox '$BBOX'. Expected south,west,north,east with valid ranges and west<east."
fi

log "Using bbox: $BBOX"

if ! command -v tippecanoe >/dev/null 2>&1 || ! command -v tile-join >/dev/null 2>&1; then
  prompt_install_tippecanoe
fi

TEMPDIR="$WORKDIR/working_files"
mkdir -p "$TEMPDIR"

cities_geojson="$TEMPDIR/cities.geojson"
suburbs_geojson="$TEMPDIR/suburbs.geojson"
neighborhoods_geojson="$TEMPDIR/neighborhoods.geojson"
labels_only="$TEMPDIR/labels_only.pmtiles"

tmp_cities="$TEMPDIR/.cities_overpass.json"
tmp_suburbs="$TEMPDIR/.suburbs_overpass.json"
tmp_neighborhoods="$TEMPDIR/.neighborhoods_overpass.json"

cleanup() {
  rm -f "$tmp_cities" "$tmp_suburbs" "$tmp_neighborhoods"
}
trap cleanup EXIT

cities_query="$(build_query 'city,town')"
suburbs_query="$(build_query 'suburb,village')"
neighborhoods_query="$(build_query 'neighbourhood,hamlet')"

query_overpass_json "$cities_query" "$tmp_cities"
count="$(overpass_to_geojson "$tmp_cities" "$cities_geojson" "$PREFER_ENGLISH" "$FORCE_ENGLISH")"
log "Wrote $count features to $(basename "$cities_geojson")"

query_overpass_json "$suburbs_query" "$tmp_suburbs"
count="$(overpass_to_geojson "$tmp_suburbs" "$suburbs_geojson" "$PREFER_ENGLISH" "$FORCE_ENGLISH")"
log "Wrote $count features to $(basename "$suburbs_geojson")"

query_overpass_json "$neighborhoods_query" "$tmp_neighborhoods"
count="$(overpass_to_geojson "$tmp_neighborhoods" "$neighborhoods_geojson" "$PREFER_ENGLISH" "$FORCE_ENGLISH")"
log "Wrote $count features to $(basename "$neighborhoods_geojson")"

log "Building labels_only.pmtiles with tippecanoe..."
if [[ "$SUBURBS_AS_NEIGHBORHOODS" -eq 1 ]]; then
  tippecanoe -Z 6 -z 15 -r 1 -y name -o "$labels_only" \
    -L city_labels:"$cities_geojson" \
    -L neighborhood_labels:"$suburbs_geojson" \
    -L neighborhood_labels:"$neighborhoods_geojson" \
    --force
else
  tippecanoe -Z 6 -z 15 -r 1 -y name -o "$labels_only" \
    -L city_labels:"$cities_geojson" \
    -L suburb_labels:"$suburbs_geojson" \
    -L neighborhood_labels:"$neighborhoods_geojson" \
    --force
fi

log "Merging base map and labels..."
tile-join -o "$OUTPUT" "$BASE_MAP" "$labels_only"

log "Done. Final map created at: $OUTPUT"
