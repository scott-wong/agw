#!/usr/bin/env bash
# Real SM2/NTLS handshake using Tongsuo 8.5's dual-certificate requirements.
set -euo pipefail

OPENSSL="${1:-/usr/local/openresty/tongsuo/bin/openssl}"
PORT="${GM_NTLS_PORT:-18443}"
CIPHER='ECDHE-SM2-SM4-GCM-SM3'
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

test -x "$OPENSSL" || { echo "ERROR: 找不到 openssl: $OPENSSL" >&2; exit 1; }
"$OPENSSL" version | grep -q '^Tongsuo: Tongsuo 8.5.0 ' || {
  echo "ERROR: $OPENSSL 不是 Tongsuo 8.5.0 构建" >&2
  exit 1
}
"$OPENSSL" ciphers -v "$CIPHER" | grep -q 'NTLSv1.1' || {
  echo "ERROR: Tongsuo 未提供 NTLSv1.1 SM2 套件" >&2
  exit 1
}

cd "$TMPDIR_GM"

cat > sign-ext.cnf <<'EOF'
[default]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature,nonRepudiation
extendedKeyUsage = serverAuth,clientAuth
subjectAltName = DNS:localhost,IP:127.0.0.1
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
EOF

cat > enc-ext.cnf <<'EOF'
[default]
basicConstraints = critical,CA:FALSE
keyUsage = critical,keyEncipherment,dataEncipherment
extendedKeyUsage = serverAuth,clientAuth
subjectAltName = DNS:localhost,IP:127.0.0.1
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
EOF

"$OPENSSL" ecparam -genkey -name SM2 -out ca.key
"$OPENSSL" req -x509 -new -sm3 -key ca.key -subj "/CN=AGW GM Test CA" \
  -days 3650 \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,keyCertSign,cRLSign" \
  -addext "subjectKeyIdentifier=hash" \
  -out ca.crt

for role in sign enc; do
  "$OPENSSL" ecparam -genkey -name SM2 -out "$role.key"
  "$OPENSSL" req -new -sm3 -key "$role.key" -subj "/CN=AGW $role" -out "$role.csr"
  "$OPENSSL" x509 -req -sm3 -in "$role.csr" -CA ca.crt -CAkey ca.key \
    -CAcreateserial -days 3650 -extfile "$role-ext.cnf" -extensions default -out "$role.crt"
done

"$OPENSSL" verify -CAfile ca.crt sign.crt
"$OPENSSL" verify -CAfile ca.crt enc.crt

"$OPENSSL" s_server -enable_ntls -ntls -accept "$PORT" \
  -sign_cert sign.crt -sign_key sign.key -enc_cert enc.crt -enc_key enc.key \
  -cipher "$CIPHER" -www > server.log 2>&1 &
SERVER_PID=$!

RESP=""
HANDSHAKE_OK=0
for _ in $(seq 1 30); do
  RESP="$(printf 'GET / HTTP/1.0\r\n\r\n' | timeout 15 "$OPENSSL" s_client \
    -enable_ntls -ntls -connect "127.0.0.1:$PORT" \
    -servername localhost -CAfile ca.crt -verify_return_error \
    -sign_cert sign.crt -sign_key sign.key \
    -enc_cert enc.crt -enc_key enc.key \
    -cipher "$CIPHER" 2>&1 || true)"
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
  echo "$RESP" | tail -n 40 >&2
  echo "--- s_server ---" >&2
  tail -n 40 server.log >&2 || true
  exit 1
fi

echo "$RESP" | grep -q 'Verify return code: 0 (ok)' || {
  echo "ERROR: NTLS 双证书链未通过校验" >&2
  echo "$RESP" | tail -n 40 >&2
  exit 1
}
echo "$RESP" | grep -q 'NTLSv1.1' || {
  echo "ERROR: 连接没有协商到 NTLSv1.1" >&2
  echo "$RESP" | tail -n 40 >&2
  exit 1
}

echo "[gm] SM2/NTLS 握手 OK（NTLSv1.1，签名/加密双证书 keyUsage 校验通过）"
