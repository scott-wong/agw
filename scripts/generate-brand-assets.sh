#!/usr/bin/env bash
# Regenerate raster brand assets from the canonical SVG files.
# macOS provides the required SVG renderer via sips.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BRANDING="$ROOT/branding"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

render_native() {
  local source="$1"
  local output="$2"

  sips -s format png "$source" --out "$output" >/dev/null
}

render_square() {
  local source="$1"
  local size="$2"
  local output="$3"
  local rendered="$TMP/$(basename "$output").png"

  qlmanage -t -s "$size" -o "$TMP" "$source" >/dev/null 2>&1
  mv "$TMP/$(basename "$source").png" "$rendered"
  cp "$rendered" "$output"
}

for size in 16 32 128 512; do
  render_square \
    "$BRANDING/agw-mark.svg" \
    "$size" \
    "$BRANDING/agw-mark-${size}.png"
done

render_native "$BRANDING/agw-logo.svg" "$BRANDING/agw-logo.png"
render_native "$BRANDING/agw-logo-dark.svg" "$BRANDING/agw-logo-dark.png"
render_native "$BRANDING/agw-github-social.svg" \
  "$BRANDING/agw-social-preview.png"

for size in 16 32 48 64 128 256; do
  render_square \
    "$BRANDING/agw-favicon.svg" \
    "$size" \
    "$TMP/favicon-${size}.png"
done

python3 - "$BRANDING/favicon.ico" "$TMP" <<'PY'
import struct
import sys
from pathlib import Path

output = Path(sys.argv[1])
source = Path(sys.argv[2])
sizes = (16, 32, 48, 64, 128, 256)
images = [(size, (source / f"favicon-{size}.png").read_bytes()) for size in sizes]

header = struct.pack("<HHH", 0, 1, len(images))
offset = len(header) + 16 * len(images)
directory = bytearray()
payload = bytearray()

for size, data in images:
    encoded_size = 0 if size == 256 else size
    directory.extend(
        struct.pack(
            "<BBBBHHII",
            encoded_size,
            encoded_size,
            0,
            0,
            1,
            32,
            len(data),
            offset,
        )
    )
    payload.extend(data)
    offset += len(data)

output.write_bytes(header + directory + payload)
print(f"[branding] wrote {output} ({', '.join(map(str, sizes))} px)")
PY

echo "[branding] raster assets regenerated"
