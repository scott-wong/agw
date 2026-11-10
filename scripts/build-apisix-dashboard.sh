#!/usr/bin/env bash
# Build the pinned-per-run Admin UI source inside the Node builder stage.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/baseline.env"

DASHBOARD_SHA="${DASHBOARD_SHA:?缺少 DASHBOARD_SHA}"
DASHBOARD_SOURCE_SHA256="${DASHBOARD_SOURCE_SHA256:?缺少 DASHBOARD_SOURCE_SHA256}"
DISTFILES="${DISTFILES:-/opt/agw/distfiles}"
PATCH_DIR="${PATCH_DIR:-/opt/agw/patches/apisix-dashboard}"
BRANDING_DIR="${BRANDING_DIR:-/opt/agw/branding}"
WORK="${WORK:-/tmp/agw-dashboard-build}"
OUTPUT="${OUTPUT:-/opt/agw/ui-dist}"
PROVENANCE_OUTPUT="${PROVENANCE_OUTPUT:-/opt/agw/dashboard-provenance.json}"

if [[ -n "${NPM_REGISTRY:-}" ]]; then
  export COREPACK_NPM_REGISTRY="$NPM_REGISTRY"
  export npm_config_registry="$NPM_REGISTRY"
  export PNPM_CONFIG_REGISTRY="$NPM_REGISTRY"
fi

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

[[ "$DASHBOARD_SHA" =~ ^[0-9a-f]{40}$ ]]
[[ "$DASHBOARD_SOURCE_SHA256" =~ ^[0-9a-f]{64}$ ]]

archive="$DISTFILES/apisix-dashboard-${DASHBOARD_SHA}.tar.gz"
test -f "$archive"
actual_source_sha="$(sha256_of "$archive")"
test "$actual_source_sha" = "$DASHBOARD_SOURCE_SHA256"

rm -rf "$WORK"
mkdir -p "$WORK"
tar -xzf "$archive" --strip-components=1 -C "$WORK"

(
  cd "$WORK"
  for patch_file in "$PATCH_DIR"/*.patch; do
    patch -p1 -E --batch --forward < "$patch_file"
  done

  test -f "$BRANDING_DIR/agw-mark.svg"
  test -f "$BRANDING_DIR/agw-mark-dark.svg"
  test -f "$BRANDING_DIR/agw-favicon.svg"
  test -f "$BRANDING_DIR/favicon.ico"
  install -d src/assets public
  install -m 0644 "$BRANDING_DIR/agw-mark.svg" src/assets/agw-mark.svg
  install -m 0644 "$BRANDING_DIR/agw-mark-dark.svg" src/assets/agw-mark-dark.svg
  install -m 0644 "$BRANDING_DIR/agw-favicon.svg" public/agw-favicon.svg
  install -m 0644 "$BRANDING_DIR/favicon.ico" public/favicon.ico

  rm -f src/assets/apisix-logo.svg
  test ! -e src/assets/apisix-logo.svg
  ! grep -R -q -F 'https://apisix.apache.org/docs/' index.html src
  ! grep -R -q -F 'https://github.com/apache/apisix-dashboard/issues/1407' \
    index.html src
  ! grep -R -q -F 'help-us-translate' src

  export HUSKY=0
  export CI=true
  export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
  test "$(corepack pnpm --version)" = "$DASHBOARD_PNPM_VERSION"
  corepack pnpm install --frozen-lockfile
  corepack pnpm lint
  corepack pnpm test
  corepack pnpm build

  test -f dist/index.html
  grep -Fq '<title>AGW Dashboard</title>' dist/index.html
  grep -Fq 'href="/ui/agw-favicon.svg"' dist/index.html
  test -f dist/agw-favicon.svg
  test -f dist/favicon.ico
  grep -R -I -q -F '16AFC4' dist/assets
  test -z "$(find dist -iname '*apisix*logo*' -print -quit)"
  ! grep -R -q -F 'https://apisix.apache.org/docs/' dist
  ! grep -R -q -F 'https://github.com/apache/apisix-dashboard/issues/1407' dist
  ! grep -R -q -F 'help-us-translate' dist
  ! grep -R -q -F '帮助我们进行翻译' dist
  ! grep -R -q -F 'Apache APISIX Dashboard' dist
  ! grep -R -q -F 'APISIX Dashboard' dist
  ! grep -R -q -F 'Help Us Translate' dist

  rm -rf "$OUTPUT"
  install -d "$OUTPUT"
  cp -a dist/. "$OUTPUT/"
  install -m 0644 LICENSE "$OUTPUT/LICENSE"
  install -m 0644 NOTICE "$OUTPUT/NOTICE"
)

python3 - "$PROVENANCE_OUTPUT" "$DASHBOARD_SHA" \
  "$DASHBOARD_SOURCE_SHA256" <<'PY'
import json
import sys

output, commit, archive_sha = sys.argv[1:]
with open(output, "w", encoding="utf-8") as handle:
    json.dump(
        {
            "repository": "https://github.com/apache/apisix-dashboard",
            "ref": "master",
            "commit": commit,
            "sourceArchiveSha256": archive_sha,
        },
        handle,
        ensure_ascii=False,
        indent=2,
    )
    handle.write("\n")
PY

test -f "$PROVENANCE_OUTPUT"
test -f "$OUTPUT/index.html"
echo "[dashboard] built apache/apisix-dashboard@${DASHBOARD_SHA}"
