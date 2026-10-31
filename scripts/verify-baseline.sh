#!/usr/bin/env bash
# Verify every immutable upstream pin, then stage source archives under
# distfiles/ for the Docker build. Drift fails the build before compilation.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/baseline.env"

DISTFILES="${DISTFILES:-$ROOT/distfiles}"
mkdir -p "$DISTFILES"

fail() {
  echo "错误: 基线漂移 - $*" >&2
  exit 1
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

check_tag_commit() {
  local repo="$1" tag="$2" want="$3" got
  got="$(git ls-remote "https://github.com/${repo}.git" "refs/tags/${tag}^{}" | awk 'NR==1 {print $1}')"
  if [ -z "$got" ]; then
    got="$(git ls-remote "https://github.com/${repo}.git" "refs/tags/${tag}" | awk 'NR==1 {print $1}')"
  fi
  [ -n "$got" ] || fail "${repo} ${tag} 不存在"
  [ "$got" = "$want" ] || fail "${repo} ${tag} commit: 期望 ${want}，实际 ${got}"
  echo "[baseline] ${repo} ${tag} @ ${want} OK"
}

download_verify() {
  local url="$1" output="$2" want="$3" got
  if [ ! -f "$output" ]; then
    echo "[baseline] 下载 $(basename "$output")"
    curl -fL --retry 3 --retry-delay 2 -o "$output.tmp" "$url"
    mv "$output.tmp" "$output"
  fi
  got="$(sha256_of "$output")"
  [ "$got" = "$want" ] || fail "$(basename "$output") SHA256: 期望 ${want}，实际 ${got}"
  echo "[baseline] $(basename "$output") SHA256 OK"
}

verify_github_archive() {
  local repo="$1" tag="$2" sha="$3" output="$4"
  download_verify "https://github.com/${repo}/archive/refs/tags/${tag}.tar.gz" "$output" "$sha"
}

manifest_digest() {
  local url="$1" auth="${2:-}" tmp
  tmp="$(mktemp)"
  if [ -n "$auth" ]; then
    curl -fsSL -H "Authorization: Bearer ${auth}" \
      -H 'Accept: application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json,application/vnd.oci.image.manifest.v1+json,application/vnd.docker.distribution.manifest.v2+json' \
      -o "$tmp" "$url" || { rm -f "$tmp"; return 1; }
  else
    curl -fsSL \
      -H 'Accept: application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json,application/vnd.oci.image.manifest.v1+json,application/vnd.docker.distribution.manifest.v2+json' \
      -o "$tmp" "$url" || { rm -f "$tmp"; return 1; }
  fi
  printf 'sha256:%s\n' "$(sha256_of "$tmp")"
  rm -f "$tmp"
}

check_quay_index() {
  local repo="$1" tag="$2" want="$3" got
  repo="${repo#quay.io/}"
  got="$(manifest_digest "https://quay.io/v2/${repo}/manifests/${tag}")" \
    || fail "读取 quay.io/${repo}:${tag} 失败"
  [ "$got" = "$want" ] || fail "quay.io/${repo}:${tag} digest: 期望 ${want}，实际 ${got}"
  echo "[baseline] quay.io/${repo}:${tag} @ ${want} OK"
}

check_dockerhub_index() {
  local repo="$1" tag="$2" want="$3" token got
  token="$(curl -fsSL "https://auth.docker.io/token?service=registry.docker.io&scope=repository:${repo}:pull" \
    | sed -E 's/.*"token":"([^"]+)".*/\1/')" || fail "取得 Docker Hub token 失败"
  [ -n "$token" ] || fail "Docker Hub 返回空 token"
  got="$(manifest_digest "https://registry-1.docker.io/v2/${repo}/manifests/${tag}" "$token")" \
    || fail "读取 docker.io/${repo}:${tag} 失败"
  [ "$got" = "$want" ] || fail "docker.io/${repo}:${tag} digest: 期望 ${want}，实际 ${got}"
  echo "[baseline] docker.io/${repo}:${tag} @ ${want} OK"
}

check_tag_commit apache/apisix "$APISIX_TAG" "$APISIX_COMMIT"
check_tag_commit api7/apisix-build-tools "$BUILD_TOOLS_TAG" "$BUILD_TOOLS_COMMIT"
check_tag_commit openresty/openresty "$OPENRESTY_TAG" "$OPENRESTY_COMMIT"
check_tag_commit "$TONGSHUO_REPO" "$TONGSHUO_TAG" "$TONGSHUO_COMMIT"
check_tag_commit PCRE2Project/pcre2 "$PCRE2_TAG" "$PCRE2_COMMIT"

check_tag_commit "$NGX_MULTI_UPSTREAM_MODULE_REPO" "$NGX_MULTI_UPSTREAM_MODULE_TAG" "$NGX_MULTI_UPSTREAM_MODULE_COMMIT"
check_tag_commit "$APISIX_NGINX_MODULE_REPO" "$APISIX_NGINX_MODULE_TAG" "$APISIX_NGINX_MODULE_COMMIT"
check_tag_commit "$WASM_NGINX_MODULE_REPO" "$WASM_NGINX_MODULE_TAG" "$WASM_NGINX_MODULE_COMMIT"
check_tag_commit "$LUA_VAR_NGINX_MODULE_REPO" "$LUA_VAR_NGINX_MODULE_TAG" "$LUA_VAR_NGINX_MODULE_COMMIT"
check_tag_commit "$MOD_DUBBO_REPO" "$MOD_DUBBO_TAG" "$MOD_DUBBO_COMMIT"
check_tag_commit "$LUA_RESTY_EVENTS_REPO" "$LUA_RESTY_EVENTS_TAG" "$LUA_RESTY_EVENTS_COMMIT"
check_tag_commit "$NGX_HTTP_FFI_CLIENT_REPO" "$NGX_HTTP_FFI_CLIENT_TAG" "$NGX_HTTP_FFI_CLIENT_COMMIT"

download_verify "$APISIX_SOURCE_URL" "$DISTFILES/apisix-${APISIX_TAG}.tar.gz" "$APISIX_SHA256"
download_verify "$APISIX_UI_DEB_URL" "$DISTFILES/$APISIX_UI_DEB_NAME" "$APISIX_UI_DEB_SHA256"
download_verify "$OPENRESTY_SOURCE_URL" "$DISTFILES/openresty-${OPENRESTY_VERSION}.tar.gz" "$OPENRESTY_SHA256"
download_verify "$TONGSHUO_SOURCE_URL" "$DISTFILES/tongsuo-${TONGSHUO_VERSION}.tar.gz" "$TONGSHUO_SHA256"
download_verify "$PCRE2_SOURCE_URL" "$DISTFILES/pcre2-${PCRE2_VERSION}.tar.gz" "$PCRE2_SHA256"
download_verify "$ZLIB_SOURCE_URL" "$DISTFILES/zlib-${ZLIB_VERSION}.tar.gz" "$ZLIB_SHA256"
download_verify "$LUAROCKS_SOURCE_URL" "$DISTFILES/luarocks-${LUAROCKS_VERSION}.tar.gz" "$LUAROCKS_SHA256"
download_verify "$WASMTIME_C_API_URL" "$DISTFILES/$WASMTIME_C_API_ASSET" "$WASMTIME_C_API_SHA256"

verify_github_archive "$NGX_MULTI_UPSTREAM_MODULE_REPO" "$NGX_MULTI_UPSTREAM_MODULE_TAG" \
  "$NGX_MULTI_UPSTREAM_MODULE_SHA256" "$DISTFILES/ngx_multi_upstream_module-${NGX_MULTI_UPSTREAM_MODULE_TAG}.tar.gz"
verify_github_archive "$APISIX_NGINX_MODULE_REPO" "$APISIX_NGINX_MODULE_TAG" \
  "$APISIX_NGINX_MODULE_SHA256" "$DISTFILES/apisix-nginx-module-${APISIX_NGINX_MODULE_TAG}.tar.gz"
verify_github_archive "$WASM_NGINX_MODULE_REPO" "$WASM_NGINX_MODULE_TAG" \
  "$WASM_NGINX_MODULE_SHA256" "$DISTFILES/wasm-nginx-module-${WASM_NGINX_MODULE_TAG}.tar.gz"
verify_github_archive "$LUA_VAR_NGINX_MODULE_REPO" "$LUA_VAR_NGINX_MODULE_TAG" \
  "$LUA_VAR_NGINX_MODULE_SHA256" "$DISTFILES/lua-var-nginx-module-${LUA_VAR_NGINX_MODULE_TAG}.tar.gz"
verify_github_archive "$MOD_DUBBO_REPO" "$MOD_DUBBO_TAG" \
  "$MOD_DUBBO_SHA256" "$DISTFILES/mod_dubbo-${MOD_DUBBO_TAG}.tar.gz"
verify_github_archive "$LUA_RESTY_EVENTS_REPO" "$LUA_RESTY_EVENTS_TAG" \
  "$LUA_RESTY_EVENTS_SHA256" "$DISTFILES/lua-resty-events-${LUA_RESTY_EVENTS_TAG}.tar.gz"
verify_github_archive "$NGX_HTTP_FFI_CLIENT_REPO" "$NGX_HTTP_FFI_CLIENT_TAG" \
  "$NGX_HTTP_FFI_CLIENT_SHA256" "$DISTFILES/ngx_http_ffi_client-${NGX_HTTP_FFI_CLIENT_TAG}.tar.gz"
verify_github_archive "$LUA_RESTY_LIMIT_TRAFFIC_REPO" "$LUA_RESTY_LIMIT_TRAFFIC_TAG" \
  "$LUA_RESTY_LIMIT_TRAFFIC_SHA256" "$DISTFILES/lua-resty-limit-traffic-${LUA_RESTY_LIMIT_TRAFFIC_TAG}.tar.gz"

check_quay_index "$OPENEULER_BASE_IMAGE" "$OPENEULER_BASE_TAG" "$OPENEULER_BASE_INDEX_DIGEST"
check_dockerhub_index library/ubuntu "$UBUNTU_BASE_TAG" "$UBUNTU_BASE_INDEX_DIGEST"
check_quay_index coreos/etcd v3.5.21 "$ETCD_TEST_IMAGE_DIGEST"

rm -rf "$ROOT/build/apisix-${APISIX_TAG}" "$ROOT/build/src"
mkdir -p "$ROOT/build"
tar -xzf "$DISTFILES/apisix-${APISIX_TAG}.tar.gz" -C "$ROOT/build"
mv "$ROOT/build/apisix-${APISIX_TAG}" "$ROOT/build/src"

echo "[baseline] all pins verified; APISIX snapshot: build/src"
