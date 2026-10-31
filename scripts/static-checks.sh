#!/usr/bin/env bash
# Fast checks that do not require Docker.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "[static] shell syntax"
while IFS= read -r script; do
  bash -n "$script"
done < <(find scripts test packaging -type f -name '*.sh' -print | sort)

echo "[static] baseline environment"
bash -c 'source scripts/baseline.env'

echo "[static] generated evidence"
python3 scripts/gen-evidence.py --check

echo "[static] workflow and smoke YAML"
ruby -e 'require "yaml"; ARGV.each { |path| YAML.load_file(path) }' \
  .github/workflows/*.yml test/smoke/*.yaml

echo "[static] APISIX patch applies and Lua files parse"
test -d build/src || {
  echo "错误: build/src 缺失，请先执行 make fetch" >&2
  exit 1
}
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cp -a build/src/. "$TMP/"
(
  cd "$TMP"
  for patch_file in "$ROOT"/patches/apisix/*.patch; do
    patch -p1 --dry-run --batch < "$patch_file"
  done
  for patch_file in "$ROOT"/patches/apisix/*.patch; do
    patch -p1 --batch < "$patch_file" >/dev/null
  done
  if command -v luac >/dev/null 2>&1; then
    luac -p \
      apisix/init.lua \
      apisix/cli/config.lua \
      apisix/cli/schema.lua \
      apisix/plugins/gm.lua
  else
    echo "[static] luac 未安装，跳过 Lua 语法解析"
  fi
)

echo "[static] obsolete delivery paths are absent"
test -z "$(find packaging/rpm packaging/fpm -type f -print 2>/dev/null)"
test ! -e .grype.yaml
test ! -e .trivyignore || ! grep -q '^CVE-' .trivyignore

echo "[static] git whitespace"
git diff --check

echo "[static] OK"
