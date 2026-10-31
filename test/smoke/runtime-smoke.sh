#!/usr/bin/env bash
# In-image runtime smoke test shared by the openEuler and Ubuntu variants.
set -euo pipefail

SMOKE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENSSL=/usr/local/openresty/tongsuo/bin/openssl
APISIX_CLI_CONFIG=/usr/local/apisix/apisix/cli/config.lua
APISIX_CLI_INIT=/usr/local/apisix/apisix/init.lua

echo "[runtime] base OS"
cat /etc/os-release

echo "[runtime] no build toolchain in final image"
if command -v gcc >/dev/null 2>&1 || command -v g++ >/dev/null 2>&1 || command -v make >/dev/null 2>&1; then
  echo "ERROR: final image contains a compiler or make" >&2
  exit 1
fi
test -z "${LD_LIBRARY_PATH:-}" || {
  echo "ERROR: final image sets a global LD_LIBRARY_PATH" >&2
  exit 1
}

echo "[runtime] OpenResty / APISIX CLI"
test -x /usr/local/openresty/bin/openresty
openresty_version="$(/usr/local/openresty/bin/openresty -V 2>&1)"
printf '%s\n' "$openresty_version" | awk 'NR <= 5'
case "$openresty_version" in
  *openresty/1.31.8.1*) ;;
  *)
    echo "ERROR: unexpected OpenResty version" >&2
    exit 1
    ;;
esac
test -x /usr/local/bin/apisix
/usr/local/bin/apisix version

echo "[runtime] bundled PCRE2/zlib"
test -f /usr/local/openresty/pcre/lib/libpcre2-8.so.0
test -f /usr/local/openresty/zlib/lib/libz.so.1
/usr/local/openresty/pcre/bin/pcre2-config --version | grep -qx '10.49'

echo "[runtime] limit-traffic lua"
test -f /usr/local/openresty/lualib/resty/limit/traffic.lua
/usr/local/openresty/luajit/bin/luajit "$SMOKE_DIR/smoke-limit.lua"

echo "[runtime] Tongsuo TLS baseline"
test -x "$OPENSSL"
"$OPENSSL" version
"$OPENSSL" version | grep -q '^Tongsuo: Tongsuo 8.5.0 '
"$OPENSSL" ciphers -v 'ECDHE-SM2-SM4-GCM-SM3' | grep -q 'NTLSv1.1'

echo "[runtime] APISIX default config"
test -f "$APISIX_CLI_CONFIG"
test -f "$APISIX_CLI_INIT"
grep -q '^    "gm",$' "$APISIX_CLI_CONFIG"
grep -q 'local ver_header = "agw"' "$APISIX_CLI_INIT"
grep -q 'set_standard_pem_ssl_key' /usr/local/apisix/apisix/plugins/gm.lua
grep -q 'for i = 2, #value.certs do' /usr/local/apisix/apisix/plugins/gm.lua

echo "[runtime] bundled APISIX Admin UI"
test -f /usr/local/apisix/ui/index.html
grep -q '<title>Apache APISIX' /usr/local/apisix/ui/index.html
test -n "$(find /usr/local/apisix/ui/assets -type f -name '*.js' -print -quit)"
test -n "$(find /usr/local/apisix/ui/assets -type f -name '*.css' -print -quit)"
test -n "$(find /usr/local/apisix/ui/assets -type f -name '*.svg' -print -quit)"
grep -q 't.keys=Array.isArray(t.keys)' \
  /usr/local/apisix/ui/assets/schema-Cj04qC-8.js
grep -Fq 'o.fields[r]?.id??`key-${d.id}`' \
  /usr/local/apisix/ui/assets/schema-Cj04qC-8.js

echo "[runtime] SM2 dual-certificate NTLS handshake"
bash "$SMOKE_DIR/gm-ntls-handshake.sh" "$OPENSSL"

echo "[runtime] OK"
