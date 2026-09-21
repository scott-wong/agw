#!/usr/bin/env bash
# verify-baseline.sh — 基线漂移校验：7 个模块 tag commit + Tongsuo TLS 基线
# + OpenResty tarball SHA256 + APISIX tag commit + 交付镜像基础层 digest。
# 基线事实源：scripts/baseline.env。
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/baseline.env"

fail() { echo "错误: 基线漂移 — $*" >&2; exit 1; }

check_ref() {
  local repo="$1" ref="$2" want="$3" got
  got=$(git ls-remote "https://github.com/$repo.git" "$ref" | awk '{print $1}')
  if [ -z "$got" ]; then
    fail "$repo $ref 不存在（上游删除/改名）"
  fi
  if [ "$got" != "$want" ]; then
    fail "$repo $ref commit 漂移：登记 $want，远端 $got"
  fi
  echo "[baseline] $repo $ref @ $want OK"
}

check_tag() {
  local repo="$1" tag="$2" want="$3"
  check_ref "$repo" "refs/tags/$tag" "$want"
}

# APISIX 网关基线
check_tag apache/apisix "$APISIX_TAG" "$APISIX_COMMIT"

# 运行时模块基线（7 个模块；其中 apisix-nginx-module 含 stream/meta 两个子编译单元）
check_tag api7/ngx_multi_upstream_module "$NGX_MULTI_UPSTREAM_MODULE_VERSION" "$NGX_MULTI_UPSTREAM_MODULE_COMMIT"
check_tag api7/apisix-nginx-module "$APISIX_NGINX_MODULE_VERSION" "$APISIX_NGINX_MODULE_COMMIT"
check_tag api7/wasm-nginx-module "$WASM_NGINX_MODULE_VERSION" "$WASM_NGINX_MODULE_COMMIT"
check_tag api7/lua-var-nginx-module "$LUA_VAR_NGINX_MODULE_VERSION" "$LUA_VAR_NGINX_MODULE_COMMIT"
check_tag api7/mod_dubbo "$MOD_DUBBO_VERSION" "$MOD_DUBBO_COMMIT"
check_tag Kong/lua-resty-events "$LUA_RESTY_EVENTS_VERSION" "$LUA_RESTY_EVENTS_COMMIT"
check_tag api7/ngx_http_ffi_client "$NGX_HTTP_FFI_CLIENT_VERSION" "$NGX_HTTP_FFI_CLIENT_COMMIT"

# TLS 基线：Tongsuo（铜锁）。上游是滚动 master 分支，因此以 commit 固定，
# 并要求 master HEAD 与登记 commit 严格一致——master 前进即红，必须先复核
# （跑 scripts/build-apisix-runtime.sh 的国密握手门禁 + 更新 README 基线表）
# 再 bump baseline.env 的 TONGSHUO_COMMIT / TONGSHUO_TAG。
# `api7/tongsuo` 已不可用，基线改用官方 Tongsuo-Project/Tongsuo。
check_ref Tongsuo-Project/Tongsuo refs/heads/master "$TONGSHUO_COMMIT"
# 同一 commit 同时是上游 tag：用于人工追溯"当时 master 对应哪个发布点"。
check_tag Tongsuo-Project/Tongsuo "$TONGSHUO_TAG" "$TONGSHUO_COMMIT"

# OpenResty release tarball（distfiles 缓存优先）
mkdir -p distfiles
TARBALL="distfiles/openresty-${OPENRESTY_VERSION}.tar.gz"
if [ ! -f "$TARBALL" ]; then
  echo "[baseline] 下载 openresty-${OPENRESTY_VERSION}.tar.gz"
  curl -fL --retry 3 -o "$TARBALL" "https://openresty.org/download/openresty-${OPENRESTY_VERSION}.tar.gz"
fi
echo "${OPENRESTY_SHA256}  $TARBALL" | sha256sum -c - || fail "OpenResty tarball SHA256 mismatch"

# 交付镜像基础层：ghcr.io/scott-wong/anolis-secure:<tag>。
# 该镜像由本账号自建、每周一重建，`latest` 会前进；因此登记 tag 当前指向的 manifest
# index digest 并在此强校验——漂移即红，必须先重扫供应链门禁（Grype/Trivy + .grype.yaml
# 例外复核），再更新 baseline.env 的 BASE_IMAGE_DIGEST 并重新走一遍 build.yml。
check_base_image() {
  local repo="${BASE_IMAGE#ghcr.io/}" ref="$BASE_IMAGE_TAG" want="$BASE_IMAGE_DIGEST"
  local token body got
  token=$(curl -sSf "https://ghcr.io/token?scope=repository:${repo}:pull&service=ghcr.io" \
          | sed -E 's/.*"token":"([^"]+)".*/\1/') \
    || fail "取得 GHCR 匿名 token 失败（${BASE_IMAGE}）"
  [ -n "$token" ] || fail "GHCR 返回空 token（${BASE_IMAGE}）"
  body=$(mktemp)
  curl -sSf -o "$body" \
    -H "Authorization: Bearer $token" \
    -H 'Accept: application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json,application/vnd.oci.image.manifest.v1+json' \
    "https://ghcr.io/v2/${repo}/manifests/${ref}" \
    || { rm -f "$body"; fail "拉取 ${BASE_IMAGE}:${ref} manifest 失败"; }
  got="sha256:$(sha256sum "$body" | awk '{print $1}')"
  rm -f "$body"
  if [ "$got" != "$want" ]; then
    fail "${BASE_IMAGE}:${ref} digest 漂移：登记 $want，当前 $got（上游每周重建；需重扫供应链门禁后更新 baseline.env）"
  fi
  echo "[baseline] ${BASE_IMAGE}:${ref} @ $want OK（运行用户 ${BASE_IMAGE_USER}）"
}

check_base_image

echo "[baseline] 全部基线校验通过"
