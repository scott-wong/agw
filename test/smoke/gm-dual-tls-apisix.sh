#!/usr/bin/env bash
# APISIX-level same-SNI test for standard TLS and TLCP.
set -euo pipefail

OPENSSL="${1:-/usr/local/openresty/tongsuo/bin/openssl}"
APISIX=/usr/local/bin/apisix
PORT=9443
SNI=agw-tlcp.test
TMPDIR_GM="$(mktemp -d)"

cleanup() {
  "$APISIX" stop >/dev/null 2>&1 || true
  rm -rf "$TMPDIR_GM"
}
trap cleanup EXIT

test -x "$OPENSSL"
"$OPENSSL" version | grep -q '^Tongsuo: Tongsuo 8.5.0 '

cd "$TMPDIR_GM"

cat > sign-ext.cnf <<'EOF'
[default]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature,nonRepudiation
extendedKeyUsage = serverAuth,clientAuth
subjectAltName = DNS:agw-tlcp.test
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
EOF

cat > enc-ext.cnf <<'EOF'
[default]
basicConstraints = critical,CA:FALSE
keyUsage = critical,keyEncipherment,dataEncipherment
extendedKeyUsage = serverAuth,clientAuth
subjectAltName = DNS:agw-tlcp.test
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
EOF

cat > standard-ext.cnf <<'EOF'
[default]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = serverAuth
subjectAltName = DNS:agw-tlcp.test
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
EOF

"$OPENSSL" ecparam -genkey -name SM2 -out ca.key
"$OPENSSL" req -x509 -new -sm3 -key ca.key -subj "/CN=AGW TLCP Test CA" \
  -days 3650 \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,keyCertSign,cRLSign" \
  -addext "subjectKeyIdentifier=hash" \
  -out ca.crt

for role in server_sign server_enc client_sign client_enc; do
  "$OPENSSL" ecparam -genkey -name SM2 -out "$role.key"
  "$OPENSSL" req -new -sm3 -key "$role.key" -subj "/CN=$role" -out "$role.csr"
done

"$OPENSSL" x509 -req -sm3 -in server_sign.csr -CA ca.crt -CAkey ca.key \
  -CAcreateserial -days 3650 -extfile sign-ext.cnf -extensions default \
  -out server_sign.crt
"$OPENSSL" x509 -req -sm3 -in server_enc.csr -CA ca.crt -CAkey ca.key \
  -CAcreateserial -days 3650 -extfile enc-ext.cnf -extensions default \
  -out server_enc.crt
"$OPENSSL" x509 -req -sm3 -in client_sign.csr -CA ca.crt -CAkey ca.key \
  -CAcreateserial -days 3650 -extfile sign-ext.cnf -extensions default \
  -out client_sign.crt
"$OPENSSL" x509 -req -sm3 -in client_enc.csr -CA ca.crt -CAkey ca.key \
  -CAcreateserial -days 3650 -extfile enc-ext.cnf -extensions default \
  -out client_enc.crt

"$OPENSSL" ecparam -genkey -name prime256v1 -out standard.key
"$OPENSSL" ecparam -genkey -name prime256v1 -out standard_ca.key
"$OPENSSL" req -x509 -new -sha256 -key standard_ca.key \
  -subj "/CN=AGW Standard TLS Test CA" -days 3650 \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,keyCertSign,cRLSign" \
  -addext "subjectKeyIdentifier=hash" \
  -out standard_ca.crt
"$OPENSSL" req -new -sha256 -key standard.key \
  -subj "/CN=agw-tlcp.test" -out standard.csr
"$OPENSSL" x509 -req -sha256 -in standard.csr \
  -CA standard_ca.crt -CAkey standard_ca.key \
  -CAcreateserial -days 3650 -extfile standard-ext.cnf -extensions default \
  -out standard.crt

cat server_sign.crt ca.crt > server_sign_chain.crt
cat server_enc.crt ca.crt > server_enc_chain.crt
cat standard.crt standard_ca.crt > standard_chain.crt

cat > config.yaml <<'EOF'
apisix:
  node_listen:
    - port: 9080
  ssl:
    enable: true
    listen:
      - port: 9443
        enable_http3: false
    ssl_protocols: TLSv1.2 TLSv1.3
    ssl_ciphers: ECDHE-SM2-SM4-GCM-SM3:ECDHE-SM2-SM4-CBC-SM3:ECC-SM2-SM4-GCM-SM3:ECC-SM2-SM4-CBC-SM3:HIGH:!aNULL:!MD5
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml
EOF

{
  printf 'ssls:\n'
  printf '  - id: agw-tlcp-dual\n'
  printf '    snis:\n'
  printf '      - %s\n' "$SNI"
  printf '    gm: true\n'
  printf '    cert: |\n'
  sed 's/^/      /' server_enc_chain.crt
  printf '    key: |\n'
  sed 's/^/      /' server_enc.key
  printf '    certs:\n'
  printf '      - |\n'
  sed 's/^/        /' server_sign_chain.crt
  printf '      - |\n'
  sed 's/^/        /' standard_chain.crt
  printf '    keys:\n'
  printf '      - |\n'
  sed 's/^/        /' server_sign.key
  printf '      - |\n'
  sed 's/^/        /' standard.key
  printf '#END\n'
} > apisix.yaml

install -m 0644 config.yaml /usr/local/apisix/conf/config.yaml
install -m 0644 apisix.yaml /usr/local/apisix/conf/apisix.yaml

"$APISIX" init
"$APISIX" start

for _ in $(seq 1 30); do
  if (exec 3<>/dev/tcp/127.0.0.1/$PORT) 2>/dev/null; then
    exec 3>&-
    break
  fi
  sleep 1
done

if grep -q "init_worker_by_lua error" /usr/local/apisix/logs/error.log; then
  cat /usr/local/apisix/logs/error.log
  exit 1
fi

request() {
  local label="$1"
  local cafile="$2"
  shift 2
  local response
  response="$(printf 'GET /no-such-route HTTP/1.0\r\nHost: %s\r\nConnection: close\r\n\r\n' "$SNI" |
    timeout 15 "$OPENSSL" s_client -quiet -connect "127.0.0.1:$PORT" \
      -servername "$SNI" -verifyCAfile "$cafile" -verify_return_error "$@" 2>&1 || true)"
  if ! grep -q 'HTTP/1.1 404 Not Found' <<<"$response"; then
    echo "ERROR: ${label} 未返回 APISIX 404" >&2
    echo "$response" >&2
    exit 1
  fi
  echo "[tlcp] ${label} OK"
}

request "standard TLS 1.2" standard_ca.crt \
  -tls1_2 -cipher ECDHE-ECDSA-AES128-GCM-SHA256

for cipher in ECC-SM2-SM4-GCM-SM3 ECC-SM2-SM4-CBC-SM3; do
  request "TLCP ${cipher}" ca.crt \
    -enable_ntls -ntls -cipher "$cipher"
done

for cipher in ECDHE-SM2-SM4-GCM-SM3 ECDHE-SM2-SM4-CBC-SM3; do
  request "TLCP strict ${cipher}" ca.crt \
    -enable_ntls -ntls -enable_ntls_strict_ecdhe_cke \
    -sign_cert client_sign.crt -sign_key client_sign.key \
    -enc_cert client_enc.crt -enc_key client_enc.key \
    -cipher "$cipher"
done

if grep -qE '\[error\].*(init_worker_by_lua error|SSL_do_handshake\(\) failed)' \
    /usr/local/apisix/logs/error.log; then
  cat /usr/local/apisix/logs/error.log
  exit 1
fi

echo "[tlcp] same-SNI standard TLS + TLCP dual stack OK"
