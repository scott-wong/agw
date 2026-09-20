#!/usr/bin/env bash
# verify-baseline.sh — 基线漂移校验：7 个模块 tag commit + Tongsuo TLS 基线
# + OpenResty tarball SHA256 + APISIX tag commit。基线事实源：scripts/baseline.env。
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

echo "[baseline] 全部基线校验通过"
