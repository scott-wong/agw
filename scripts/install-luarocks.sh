#!/usr/bin/env bash
# Install the pinned LuaRocks release against OpenResty's LuaJIT.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/baseline.env"

DISTFILES="${DISTFILES:-/opt/agw/distfiles}"
OR_PREFIX="${OR_PREFIX:-/usr/local/openresty}"
WORK="${WORK:-/tmp/agw-luarocks-build}"

rm -rf "$WORK"
mkdir -p "$WORK"
tar -xzf "$DISTFILES/luarocks-${LUAROCKS_VERSION}.tar.gz" --strip-components=1 -C "$WORK"

(
  cd "$WORK"
  ./configure \
    --prefix=/usr/local \
    --sysconfdir=/etc \
    --with-lua="$OR_PREFIX/luajit" \
    --with-lua-include="$OR_PREFIX/luajit/include/luajit-2.1" \
    --lua-version=5.1
  make build
  make install
)

export PATH="/usr/local/bin:$OR_PREFIX/luajit/bin:$OR_PREFIX/bin:$PATH"
mkdir -p /root/.luarocks
luarocks config variables.OPENSSL_DIR "$OR_PREFIX/tongsuo"
luarocks config variables.OPENSSL_LIBDIR "$OR_PREFIX/tongsuo/lib"
luarocks config variables.OPENSSL_INCDIR "$OR_PREFIX/tongsuo/include"
luarocks config variables.YAML_DIR /usr
luarocks config variables.PCRE_DIR "$OR_PREFIX/pcre"

luarocks --version
rm -rf "$WORK"
