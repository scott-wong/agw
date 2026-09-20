#!/usr/bin/env bash
# gm-ntls-handshake.sh — Tongsuo 国密真实握手冒烟（SM2 双证书 + NTLSv1.1）。
#
# 自签一棵 SM2 CA，签发 NTLS 认证需要的两张证书（sign 签名证书 / enc 加密证书），
# 再用同一份二进制起 s_server / s_client 做一次完整握手，验证：
#   1. 运行时 TLS 库是 Tongsuo（编译期印记 "Tongsuo: "）
#   2. ECDHE-SM2-SM4-GCM-SM3 套件存在且协议为 NTLSv1.1
#   3. 双证书链可校验、握手成功并返回 HTTP 响应
# 全程离线，不依赖外部证书或网络。
#
# 用法: gm-ntls-handshake.sh [openssl-bin]
set -euo pipefail

OPENSSL="${1:-/usr/local/openresty/tongsuo/bin/openssl}"
PORT="${GM_NTLS_PORT:-18443}"
CIPHER='ECDHE-SM2-WITH-SM4-SM3'
TMPDIR_GM="$(mktemp -d)"
SERVER_PID=""

cleanup() {
  if [ -n "$SERVER_PID" ]; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  rm -rf "$TMPDIR_GM"
}
trap cleanup EXIT

test -x "$OPENSSL" || { echo "ERROR: 找不到可执行的 openssl: $OPENSSL" >&2; exit 1; }
"$OPENSSL" version | grep -q '^Tongsuo: ' || {
  echo "ERROR: $OPENSSL 不是 Tongsuo 构建（缺 'Tongsuo: ' 印记）" >&2
  exit 1
}

cd "$TMPDIR_GM"

# ---- SM2 双证书链 ----
"$OPENSSL" ecparam -genkey -name SM2 -out ca.key
"$OPENSSL" req -x509 -new -sm3 -key ca.key -subj "/CN=AGW GM Test CA" -days 3650 -out ca.crt
for role in sign enc; do
  "$OPENSSL" ecparam -genkey -name SM2 -out "$role.key"
  "$OPENSSL" req -new -sm3 -key "$role.key" -subj "/CN=AGW $role" -out "$role.csr"
  "$OPENSSL" x509 -req -sm3 -in "$role.csr" -CA ca.crt -CAkey ca.key -CAcreateserial \
    -days 3650 -out "$role.crt"
done

# ---- 套件门禁：必须是 NTLSv1.1 的 SM2 套件 ----
"$OPENSSL" ciphers -v 'ECDHE-SM2-SM4-GCM-SM3' | grep -q 'NTLSv1.1' || {
  echo "ERROR: Tongsuo 未提供 NTLSv1.1 的 SM2 套件" >&2
  exit 1
}

# ---- 真握手 ----
"$OPENSSL" s_server -enable_ntls -ntls -accept "$PORT" \
  -sign_cert sign.crt -sign_key sign.key -enc_cert enc.crt -enc_key enc.key \
  -cipher "$CIPHER" -www -quiet > server.log 2>&1 &
SERVER_PID=$!

RESP=""
HANDSHAKE_OK=0
for _ in $(seq 1 30); do
  RESP=$(printf 'GET /\r\n\r\n' | "$OPENSSL" s_client -enable_ntls -ntls \
      -connect "127.0.0.1:$PORT" -CAfile ca.crt \
      -sign_cert sign.crt -sign_key sign.key -enc_cert enc.crt -enc_key enc.key \
      -cipher "$CIPHER" -quiet 2>&1 || true)
  if echo "$RESP" | grep -q 'HTTP/1.0 200 ok'; then
    HANDSHAKE_OK=1
    break
  fi
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    break
  fi
  sleep 1
done

if [ "$HANDSHAKE_OK" -ne 1 ]; then
  echo "ERROR: SM2/NTLS 握手失败" >&2
  echo "--- s_client ---" >&2
  echo "$RESP" | tail -n 30 >&2
  echo "--- s_server ---" >&2
  tail -n 30 server.log >&2 || true
  exit 1
fi

echo "$RESP" | grep -q 'verify return:1' || {
  echo "ERROR: NTLS 双证书链未通过校验" >&2
  echo "$RESP" | tail -n 30 >&2
  exit 1
}

echo "[gm] SM2/NTLS 握手 OK（NTLSv1.1 + ${CIPHER}，sign/enc 双证书链校验通过）"
