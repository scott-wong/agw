#!/usr/bin/env bash
# Build the AGW OpenResty runtime inside one target distribution. The same
# script runs in both build stages; no compiled tree crosses distro boundaries.
set -euo pipefail
set -x

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/baseline.env"

DISTFILES="${DISTFILES:-/opt/agw/distfiles}"
OR_PREFIX="${OR_PREFIX:-/usr/local/openresty}"
OPENSSL_PREFIX="$OR_PREFIX/tongsuo"
ZLIB_PREFIX="$OR_PREFIX/zlib"
PCRE_PREFIX="$OR_PREFIX/pcre"
OPENSSL_CONF_PATH="${OPENSSL_CONF_PATH:-/opt/agw/packaging/openssl/openssl.cnf}"
APISIX_RUNTIME_VERSION="${APISIX_RUNTIME_VERSION:-1.4.2}"
WORK="${WORK:-/tmp/agw-runtime-build}"

export PATH="$PCRE_PREFIX/bin:$OPENSSL_PREFIX/bin:$OR_PREFIX/bin:$OR_PREFIX/luajit/bin:$PATH"
export PKG_CONFIG_PATH="$PCRE_PREFIX/lib/pkgconfig:$ZLIB_PREFIX/lib/pkgconfig:$OPENSSL_PREFIX/lib/pkgconfig"
export CPPFLAGS="-I$PCRE_PREFIX/include -I$ZLIB_PREFIX/include -I$OPENSSL_PREFIX/include"
export LDFLAGS="-L$PCRE_PREFIX/lib -L$ZLIB_PREFIX/lib -L$OPENSSL_PREFIX/lib -Wl,-rpath,$PCRE_PREFIX/lib:$ZLIB_PREFIX/lib:$OPENSSL_PREFIX/lib"
export LD_LIBRARY_PATH="$PCRE_PREFIX/lib:$ZLIB_PREFIX/lib:$OPENSSL_PREFIX/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

cc_opt="-DNGX_LUA_ABORT_AT_PANIC -I$ZLIB_PREFIX/include -I$PCRE_PREFIX/include -I$OPENSSL_PREFIX/include"
ld_opt="-L$ZLIB_PREFIX/lib -L$PCRE_PREFIX/lib -L$OPENSSL_PREFIX/lib -Wl,-rpath,$ZLIB_PREFIX/lib:$PCRE_PREFIX/lib:$OPENSSL_PREFIX/lib"

extract_archive() {
  local archive="$1" destination="$2"
  local top
  top="$(tar -tzf "$archive" | sed -n '1p' | cut -d/ -f1)"
  [ -n "$top" ] || { echo "错误: 空归档 $archive" >&2; exit 1; }
  rm -rf "$destination"
  mkdir -p "$destination"
  tar -xzf "$archive" --strip-components=1 -C "$destination"
}

install_pcre2() {
  extract_archive "$DISTFILES/pcre2-${PCRE2_VERSION}.tar.gz" "$WORK/pcre2"
  (
    cd "$WORK/pcre2"
    ./configure --prefix="$PCRE_PREFIX" --enable-jit --enable-pcre2grep-jit
    make -j"$(nproc)"
    make install
  )
  test -x "$PCRE_PREFIX/bin/pcre2-config"
  [ "$("$PCRE_PREFIX/bin/pcre2-config" --version)" = "$PCRE2_VERSION" ]
}

install_zlib() {
  extract_archive "$DISTFILES/zlib-${ZLIB_VERSION}.tar.gz" "$WORK/zlib"
  (
    cd "$WORK/zlib"
    CFLAGS="-O3 -fPIC" ./configure --prefix="$ZLIB_PREFIX" --shared
    make -j"$(nproc)"
    make install
  )
  test -f "$ZLIB_PREFIX/include/zlib.h"
}

install_tongsuo() {
  extract_archive "$DISTFILES/tongsuo-${TONGSHUO_VERSION}.tar.gz" "$WORK/tongsuo"
  (
    cd "$WORK/tongsuo"
    ./config shared enable-ntls zlib \
      enable-rfc3779 enable-cms enable-rc5 enable-weak-ssl-ciphers \
      --prefix="$OPENSSL_PREFIX" \
      --libdir=lib \
      --with-zlib-lib="$ZLIB_PREFIX/lib" \
      --with-zlib-include="$ZLIB_PREFIX/include"
    make -j"$(nproc)" LD_LIBRARY_PATH= CC=gcc
    make install_sw install_ssldirs
  )
  if [ -f "$OPENSSL_CONF_PATH" ]; then
    cp "$OPENSSL_CONF_PATH" "$OPENSSL_PREFIX/ssl/openssl.cnf"
  fi
  "$OPENSSL_PREFIX/bin/openssl" version | grep -q "^Tongsuo: Tongsuo ${TONGSHUO_VERSION} "
  "$OPENSSL_PREFIX/bin/openssl" ciphers -v 'ECDHE-SM2-SM4-GCM-SM3' | grep -q 'NTLSv1.1'
}

prepare_modules() {
  extract_archive "$DISTFILES/ngx_multi_upstream_module-${NGX_MULTI_UPSTREAM_MODULE_TAG}.tar.gz" "$WORK/ngx_multi_upstream_module"
  extract_archive "$DISTFILES/apisix-nginx-module-${APISIX_NGINX_MODULE_TAG}.tar.gz" "$WORK/apisix-nginx-module"
  extract_archive "$DISTFILES/wasm-nginx-module-${WASM_NGINX_MODULE_TAG}.tar.gz" "$WORK/wasm-nginx-module"
  extract_archive "$DISTFILES/lua-var-nginx-module-${LUA_VAR_NGINX_MODULE_TAG}.tar.gz" "$WORK/lua-var-nginx-module"
  extract_archive "$DISTFILES/mod_dubbo-${MOD_DUBBO_TAG}.tar.gz" "$WORK/mod_dubbo"
  extract_archive "$DISTFILES/lua-resty-events-${LUA_RESTY_EVENTS_TAG}.tar.gz" "$WORK/lua-resty-events"
  extract_archive "$DISTFILES/ngx_http_ffi_client-${NGX_HTTP_FFI_CLIENT_TAG}.tar.gz" "$WORK/ngx_http_ffi_client"
  extract_archive "$DISTFILES/lua-resty-limit-traffic-${LUA_RESTY_LIMIT_TRAFFIC_TAG}.tar.gz" "$WORK/lua-resty-limit-traffic"

  extract_archive "$DISTFILES/openresty-${OPENRESTY_VERSION}.tar.gz" "$WORK/openresty-${OPENRESTY_VERSION}"

  (
    cd "$WORK/ngx_multi_upstream_module"
    ./patch.sh "../openresty-${OPENRESTY_VERSION}"
  )
  (
    cd "$WORK/apisix-nginx-module/patch"
    ./patch.sh "../../openresty-${OPENRESTY_VERSION}"
  )
  (
    cd "$WORK/wasm-nginx-module"
    # wget/curl link the distro's libcrypto; keep the newly built Tongsuo
    # rpath/LD_LIBRARY_PATH out of this bootstrap process.
    env -u LD_LIBRARY_PATH ./install-wasmtime.sh
  )

  local limit_bundle
  limit_bundle="$(find "$WORK/openresty-${OPENRESTY_VERSION}/bundle" -maxdepth 1 -type d -name 'lua-resty-limit-traffic-*' -print -quit)"
  [ -n "$limit_bundle" ] || {
    echo "错误: OpenResty ${OPENRESTY_VERSION} 缺少 lua-resty-limit-traffic bundle" >&2
    exit 1
  }
  rm -rf "$limit_bundle"
  cp -a "$WORK/lua-resty-limit-traffic" "$limit_bundle"
}

build_openresty() {
  local ngx_lua_bundle_dir
  ngx_lua_bundle_dir="$(find "$WORK/openresty-${OPENRESTY_VERSION}/bundle" -maxdepth 1 -type d -name 'ngx_lua-*' -print -quit)"
  [ -n "$ngx_lua_bundle_dir" ] || { echo "错误: OpenResty 缺少 ngx_lua bundle" >&2; exit 1; }
  export NGX_HTTP_LUA_MODULE_DIR="$ngx_lua_bundle_dir"

  (
    cd "$WORK/openresty-${OPENRESTY_VERSION}"
    ./configure --prefix="$OR_PREFIX" \
      --with-cc-opt="-DAPISIX_RUNTIME_VER=$APISIX_RUNTIME_VERSION $cc_opt" \
      --with-ld-opt="-Wl,-rpath,$OR_PREFIX/wasmtime-c-api/lib $ld_opt" \
      --add-module="$WORK/mod_dubbo" \
      --add-module="$WORK/ngx_multi_upstream_module" \
      --add-module="$WORK/apisix-nginx-module" \
      --add-module="$WORK/apisix-nginx-module/src/stream" \
      --add-module="$WORK/apisix-nginx-module/src/meta" \
      --add-module="$WORK/wasm-nginx-module" \
      --add-module="$WORK/lua-var-nginx-module" \
      --add-module="$WORK/lua-resty-events" \
      --add-module="$WORK/ngx_http_ffi_client" \
      --with-poll_module \
      --with-pcre-jit \
      --without-http_rds_json_module \
      --without-http_rds_csv_module \
      --without-lua_rds_parser \
      --with-stream \
      --with-stream_ssl_module \
      --with-stream_ssl_preread_module \
      --with-stream_realip_module \
      --with-http_v2_module \
      --with-http_v3_module \
      --without-mail_pop3_module \
      --without-mail_imap_module \
      --without-mail_smtp_module \
      --with-http_stub_status_module \
      --with-http_realip_module \
      --with-http_addition_module \
      --with-http_auth_request_module \
      --with-http_secure_link_module \
      --with-http_random_index_module \
      --with-http_gzip_static_module \
      --with-http_sub_module \
      --with-http_dav_module \
      --with-http_flv_module \
      --with-http_mp4_module \
      --with-http_gunzip_module \
      --with-threads \
      --with-compat \
      --with-luajit-xcflags="-DLUAJIT_NUMMODE=2 -DLUAJIT_ENABLE_LUA52COMPAT" \
      -j"$(nproc)"
    make -j"$(nproc)"
    make install
  )

  install -d "$OR_PREFIX/lualib/resty/events"
  install -m 0644 "$WORK"/lua-resty-events/lib/resty/events/*.lua "$OR_PREFIX/lualib/resty/events/"
  install -d "$OR_PREFIX/lualib/resty/events/compat"
  install -m 0644 "$WORK"/lua-resty-events/lib/resty/events/compat/*.lua "$OR_PREFIX/lualib/resty/events/compat/"
  install -d "$OR_PREFIX/lualib/resty"
  install -m 0644 "$WORK/ngx_http_ffi_client/lib/resty/ngx_http_ffi_client.lua" \
    "$OR_PREFIX/lualib/resty/ngx_http_ffi_client.lua"

  (
    cd "$WORK/apisix-nginx-module"
    OPENRESTY_PREFIX="$OR_PREFIX" make install
  )
  (
    cd "$WORK/wasm-nginx-module"
    OPENRESTY_PREFIX="$OR_PREFIX" make install
  )
}

assert_tongsuo_linkage() {
  local nginx_bin="$OR_PREFIX/nginx/sbin/nginx" libs
  libs="$(ldd "$nginx_bin")" || { echo "错误: ldd $nginx_bin 失败" >&2; exit 1; }
  echo "$libs" | grep -E 'libssl\.so' | grep -q "$OPENSSL_PREFIX/lib/" || {
    echo "错误: nginx 未动态链接 $OPENSSL_PREFIX/lib/libssl" >&2
    echo "$libs" >&2
    exit 1
  }
  echo "$libs" | grep -E 'libcrypto\.so' | grep -q "$OPENSSL_PREFIX/lib/" || {
    echo "错误: nginx 未动态链接 $OPENSSL_PREFIX/lib/libcrypto" >&2
    echo "$libs" >&2
    exit 1
  }
  echo "$libs" | grep -E 'libpcre2-8\.so' | grep -q "$PCRE_PREFIX/lib/" || {
    echo "错误: nginx 未动态链接 $PCRE_PREFIX/lib/libpcre2-8" >&2
    echo "$libs" >&2
    exit 1
  }
  echo "$libs" | grep -E 'libz\.so' | grep -q "$ZLIB_PREFIX/lib/" || {
    echo "错误: nginx 未动态链接 $ZLIB_PREFIX/lib/libz" >&2
    echo "$libs" >&2
    exit 1
  }
}

rm -rf "$WORK"
mkdir -p "$WORK"
install_pcre2
install_zlib
install_tongsuo
prepare_modules
build_openresty
assert_tongsuo_linkage

mkdir -p /usr/local/share/agw
cp "$SCRIPT_DIR/baseline.env" /usr/local/share/agw/baseline.env
{
  echo "apisix=${APISIX_TAG}"
  echo "openresty=${OPENRESTY_VERSION}"
  echo "tongsuo=${TONGSHUO_VERSION}"
  echo "pcre2=${PCRE2_VERSION}"
  echo "zlib=${ZLIB_VERSION}"
  echo "runtime_reference=${BUILD_TOOLS_TAG}"
} > /usr/local/share/agw/runtime-provenance.txt

/usr/local/openresty/bin/openresty -V 2>&1 | sed -n '1,6p'
"$OPENSSL_PREFIX/bin/openssl" version
