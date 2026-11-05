#!/usr/bin/env bash
# Resolve and stage the moving apache/apisix-dashboard master revision.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/baseline.env"

DISTFILES="${DISTFILES:-$ROOT/distfiles}"
COMMAND="${1:-resolve}"

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

validate_sha() {
  local sha="$1"
  [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || {
    echo "错误: 非法 Dashboard commit SHA: $sha" >&2
    exit 1
  }
}

resolve_master() {
  local sha
  sha="$(git ls-remote "https://github.com/${APISIX_DASHBOARD_REPO}.git" \
    "refs/heads/${APISIX_DASHBOARD_REF}" | awk 'NR == 1 {print $1}')"
  validate_sha "$sha"
  printf '%s\n' "$sha"
}

archive_path() {
  local sha="$1"
  printf '%s/apisix-dashboard-%s.tar.gz\n' "$DISTFILES" "$sha"
}

metadata_path() {
  local sha="$1"
  printf '%s/apisix-dashboard-%s.json\n' "$DISTFILES" "$sha"
}

fetch_source() {
  local sha="$1" archive metadata url
  validate_sha "$sha"
  mkdir -p "$DISTFILES"
  archive="$(archive_path "$sha")"
  metadata="$(metadata_path "$sha")"
  url="https://github.com/${APISIX_DASHBOARD_REPO}/archive/${sha}.tar.gz"

  if [ ! -f "$archive" ]; then
    echo "[dashboard] 下载 apache/apisix-dashboard@${sha}" >&2
    curl -fL --retry 3 --retry-delay 2 -o "$archive.tmp" "$url"
    mv "$archive.tmp" "$archive"
  fi

  local archive_sha
  archive_sha="$(sha256_of "$archive")"
  if [ -f "$metadata" ]; then
    local recorded
    recorded="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["sha256"])' "$metadata")"
    if [ "$recorded" != "$archive_sha" ]; then
      echo "错误: Dashboard 源码归档 SHA256 与元数据不一致" >&2
      echo "  元数据: $recorded" >&2
      echo "  实际:   $archive_sha" >&2
      exit 1
    fi
  else
    python3 - "$metadata" "$APISIX_DASHBOARD_REPO" "$APISIX_DASHBOARD_REF" \
      "$sha" "$url" "$(basename "$archive")" "$archive_sha" <<'PY'
import json
import sys

output, repository, ref, commit, url, archive, archive_sha = sys.argv[1:]
with open(output, "w", encoding="utf-8") as handle:
    json.dump(
        {
            "repository": f"https://github.com/{repository}",
            "ref": ref,
            "commit": commit,
            "sourceUrl": url,
            "archive": archive,
            "sha256": archive_sha,
        },
        handle,
        ensure_ascii=False,
        indent=2,
    )
    handle.write("\n")
PY
  fi

  printf '%s\n' "$archive_sha"
}

case "$COMMAND" in
  resolve)
    resolve_master
    ;;
  fetch)
    SHA="${2:-$(resolve_master)}"
    fetch_source "$SHA"
    ;;
  sha256)
    SHA="${2:?缺少 Dashboard SHA}"
    validate_sha "$SHA"
    archive="$(archive_path "$SHA")"
    test -f "$archive"
    sha256_of "$archive"
    ;;
  metadata)
    SHA="${2:?缺少 Dashboard SHA}"
    validate_sha "$SHA"
    test -f "$(metadata_path "$SHA")"
    metadata_path "$SHA"
    ;;
  *)
    echo "用法: dashboard-source.sh {resolve|fetch [sha]|sha256 <sha>|metadata <sha>}" >&2
    exit 1
    ;;
esac
