#!/usr/bin/env bash
# runtime-smoke.sh — 交付运行时冒烟（RPM 安装后与交付镜像内通用）。
#
# 断言运行时的四个面：
#   1. OpenResty/Lua 运行时可用（openresty -V、apisix version、限流 lua 可加载）
#   2. TLS 基线是 Tongsuo（不是官方 OpenSSL/OpenResty 自带 openssl）
#   3. APISIX 默认插件表含 gm（国密插件随包可用）
#   4. SM2 双证书 NTLS 真握手（见 gm-ntls-handshake.sh）
#
# 不负责安装 RPM、不负责启动 apisix（分别见 Makefile verify / scripts/smoke-docker.sh）。
set -euo pipefail

SMOKE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENSSL=/usr/local/openresty/tongsuo/bin/openssl
APISIX_DEFAULT_CONF=/usr/local/apisix/apisix/cli/config.lua

echo "[runtime] OpenResty / APISIX CLI"
test -x /usr/local/openresty/bin/openresty
/usr/local/openresty/bin/openresty -V 2>&1 | head -n 3
test -x /usr/bin/apisix
/usr/bin/apisix version

echo "[runtime] 限流 lua 可加载"
test -f /usr/local/openresty/lualib/resty/limit/traffic.lua
/usr/local/openresty/luajit/bin/luajit "$SMOKE_DIR/smoke-limit.lua"

echo "[runtime] TLS 基线 = Tongsuo"
test -x "$OPENSSL"
"$OPENSSL" version | grep -q '^Tongsuo: '

echo "[runtime] APISIX 默认插件表含 gm"
test -f "$APISIX_DEFAULT_CONF"
grep -q '"gm",' "$APISIX_DEFAULT_CONF"

echo "[runtime] SM2 双证书 NTLS 真握手"
bash "$SMOKE_DIR/gm-ntls-handshake.sh" "$OPENSSL"

echo "[runtime] OK"
