#!/usr/bin/env bash
# Build Apache APISIX from the verified source archive and assemble the runtime
# layout under /usr/local/apisix. This runs after build-apisix-runtime.sh.
set -euo pipefail
set -x

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/baseline.env"

DISTFILES="${DISTFILES:-/opt/agw/distfiles}"
OR_PREFIX="${OR_PREFIX:-/usr/local/openresty}"
APISIX_PREFIX="${APISIX_PREFIX:-/usr/local/apisix}"
WORK="${WORK:-/tmp/agw-apisix-build}"
PATCH_DIR="$SCRIPT_DIR/../patches/apisix"

export PATH="/usr/local/bin:$OR_PREFIX/tongsuo/bin:$OR_PREFIX/pcre/bin:$OR_PREFIX/bin:$OR_PREFIX/luajit/bin:$PATH"
export LUA_PATH="$APISIX_PREFIX/?.lua;$APISIX_PREFIX/?/init.lua;$APISIX_PREFIX/deps/share/lua/5.1/?.lua;$APISIX_PREFIX/deps/share/lua/5.1/?/init.lua;;"
export LUA_CPATH="$APISIX_PREFIX/deps/lib/lua/5.1/?.so;$APISIX_PREFIX/deps/lib64/lua/5.1/?.so;;"
export OPENSSL_DIR="$OR_PREFIX/tongsuo"
export OPENSSL_LIBDIR="$OR_PREFIX/tongsuo/lib"
export OPENSSL_INCDIR="$OR_PREFIX/tongsuo/include"
export YAML_DIR=/usr
export CPPFLAGS="-DXMLSEC_NO_RIPEMD160=1 -I$OR_PREFIX/tongsuo/include"
export LDFLAGS="-L$OR_PREFIX/tongsuo/lib -Wl,-rpath,$OR_PREFIX/tongsuo/lib:$OR_PREFIX/pcre/lib:$OR_PREFIX/zlib/lib"

rm -rf "$WORK"
mkdir -p "$WORK"
tar -xzf "$DISTFILES/apisix-${APISIX_TAG}.tar.gz" --strip-components=1 -C "$WORK"

(
  cd "$WORK"
  for patch_file in "$PATCH_DIR"/*.patch; do
    patch -p1 --batch --forward < "$patch_file"
  done
  grep -q 'local ver_header = "agw"' apisix/init.lua
  grep -q '^    "gm",$' apisix/cli/config.lua
  grep -q 'set_standard_pem_ssl_key' apisix/plugins/gm.lua

  # luarocks make does not need to fetch the source again; point the source
  # stanza at the local checkout as upstream's packaging does.
  sed -re '/^\s*source\s*=\s*\{$/{:src;n;s/^(\s*url\s*=).*$/\1".\/apisix",/;/\}/!bsrc}' \
    -e '/^\s*source\s*=\s*\{$/{:src;n;/^(\s*branch\s*=).*$/d;/\}/!bsrc}' \
    -i apisix-master-0.rockspec

  luarocks config variables.OPENSSL_DIR "$OPENSSL_DIR"
  luarocks config variables.OPENSSL_LIBDIR "$OPENSSL_LIBDIR"
  luarocks config variables.OPENSSL_INCDIR "$OPENSSL_INCDIR"
  luarocks config variables.YAML_DIR "$YAML_DIR"

  luarocks make ./apisix-master-0.rockspec --tree="$WORK/deps"
)

rm -rf "$APISIX_PREFIX"
mkdir -p "$APISIX_PREFIX/conf" "$APISIX_PREFIX/logs"
cp -a "$WORK/deps" "$APISIX_PREFIX/deps"

target_lua="$APISIX_PREFIX/deps/share/lua/5.1/apisix"
test -d "$target_lua"
mv "$target_lua" "$APISIX_PREFIX/apisix"

cp -a "$WORK/conf/." "$APISIX_PREFIX/conf/"
install -d "$APISIX_PREFIX/bin"
install -m 0755 "$WORK/bin/apisix" "$APISIX_PREFIX/bin/apisix"
install -m 0755 "$WORK/bin/apisix" /usr/local/bin/apisix
install -m 0644 "$WORK/LICENSE" "$APISIX_PREFIX/LICENSE"
if [ -f "$WORK/NOTICE" ]; then
  install -m 0644 "$WORK/NOTICE" "$APISIX_PREFIX/NOTICE"
fi

# The source wrapper picks /usr/local/apisix/apisix/cli/apisix.lua. Make the
# CLI and the Nginx Lua VM see both the product tree and LuaRocks dependency
# tree explicitly instead of relying on the build directory or HOME.
sed -i \
  '1i package.path = "/usr/local/apisix/?.lua;/usr/local/apisix/?/init.lua;/usr/local/apisix/deps/share/lua/5.1/?.lua;/usr/local/apisix/deps/share/lua/5.1/?/init.lua;" .. package.path' \
  "$APISIX_PREFIX/apisix/cli/apisix.lua"
sed -i \
  '1i package.cpath = "/usr/local/apisix/deps/lib/lua/5.1/?.so;/usr/local/apisix/deps/lib64/lua/5.1/?.so;" .. package.cpath' \
  "$APISIX_PREFIX/apisix/cli/apisix.lua"

# Remove only package-manager metadata and build docs. Compiled native modules
# remain under deps/lib*/lua/5.1.
rm -rf "$APISIX_PREFIX/deps/lib/luarocks" "$APISIX_PREFIX/deps/lib64/luarocks"
find "$APISIX_PREFIX/deps" -type d -name doc -prune -exec rm -rf {} +

# Prune OpenResty build-only files before the final image COPY. Removing them
# in the final stage would leave the deleted bytes in the lower image layer.
rm -rf \
  "$OR_PREFIX/include" \
  "$OR_PREFIX/luajit/include" \
  "$OR_PREFIX/pcre/include" \
  "$OR_PREFIX/zlib/include" \
  "$OR_PREFIX/tongsuo/include" \
  "$OR_PREFIX/pod"
find "$OR_PREFIX" -type f -name '*.a' -delete
find "$OR_PREFIX" -type d -name pkgconfig -prune -exec rm -rf {} +

ln -sfn "$OR_PREFIX/bin/openresty" /usr/local/bin/openresty
ln -sfn "$OR_PREFIX/bin/resty" /usr/local/bin/resty

test -x /usr/local/bin/apisix
test -f "$APISIX_PREFIX/apisix/cli/apisix.lua"
test -f "$APISIX_PREFIX/conf/config.yaml"
grep -q '"gm",' "$APISIX_PREFIX/apisix/cli/config.lua"
grep -q 'local ver_header = "agw"' "$APISIX_PREFIX/apisix/init.lua"
grep -q 'set_standard_pem_ssl_key' "$APISIX_PREFIX/apisix/plugins/gm.lua"

# Native rocks carry an RPATH to Tongsuo. Keep Tongsuo out of the global
# loader path so LuaRocks can invoke the distro's git/curl without ABI clashes.
env -u LD_LIBRARY_PATH /usr/local/bin/apisix version
rm -rf "$WORK"
