#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/baseline.env"

DISTFILES="${DISTFILES:-/opt/agw/distfiles}"
WORK="${WORK:-/tmp/agw-docs-build}"
OUTPUT="${OUTPUT:-/opt/agw/docs-dist}"
VIEWER="${VIEWER:-/opt/agw/docs-viewer}"
BRANDING="${BRANDING:-$ROOT/branding}"
ARCHIVE="$DISTFILES/apisix-${APISIX_TAG}.tar.gz"

test -f "$ARCHIVE"
test -f "$VIEWER/package.json"
test -f "$VIEWER/package-lock.json"
test -d "$VIEWER/node_modules/docsify"

rm -rf "$WORK" "$OUTPUT"
mkdir -p "$WORK"
tar -xzf "$ARCHIVE" -C "$WORK"

python3 "$SCRIPT_DIR/build-apisix-docs.py" \
  --source "$WORK/apisix-${APISIX_TAG}" \
  --output "$OUTPUT" \
  --viewer "$VIEWER" \
  --branding "$BRANDING" \
  --version "$APISIX_TAG" \
  --source-url "$APISIX_SOURCE_URL"
