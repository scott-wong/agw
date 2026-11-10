#!/usr/bin/env bash
# External-etcd/Admin API smoke. Proves the default traditional deployment mode
# still starts against an external etcd and applies server_header to Admin API.
set -euo pipefail

IMAGE="${1:?用法: smoke-etcd.sh <image>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/baseline.env"

NETWORK="agw-etcd-net-$$"
ETCD_NAME="agw-etcd-$$"
AGW_NAME="agw-etcd-gw-$$"
CONFIG="$ROOT/test/smoke/etcd-config.yaml"
UI_TMP=""

cleanup() {
  docker logs "$AGW_NAME" > /tmp/agw-etcd-gw.log 2>&1 || true
  docker logs "$ETCD_NAME" > /tmp/agw-etcd.log 2>&1 || true
  docker rm -f "$AGW_NAME" "$ETCD_NAME" >/dev/null 2>&1 || true
  docker network rm "$NETWORK" >/dev/null 2>&1 || true
  if [ -n "$UI_TMP" ]; then
    rm -rf "$UI_TMP"
  fi
}
trap cleanup EXIT

docker network create "$NETWORK" >/dev/null
docker run -d --rm --name "$ETCD_NAME" --network "$NETWORK" --network-alias etcd \
  "${ETCD_TEST_IMAGE}@${ETCD_TEST_IMAGE_DIGEST}" \
  /usr/local/bin/etcd \
  --name agw-smoke \
  --data-dir /tmp/etcd-data \
  --advertise-client-urls http://0.0.0.0:2379 \
  --listen-client-urls http://0.0.0.0:2379 >/dev/null

for _ in $(seq 1 30); do
  if docker exec "$ETCD_NAME" /usr/local/bin/etcdctl endpoint health >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
docker exec "$ETCD_NAME" /usr/local/bin/etcdctl endpoint health

docker run -d --rm --name "$AGW_NAME" --network "$NETWORK" \
  -e ETCD_HOST=etcd \
  -p 19080:9080 -p 19180:9180 \
  -v "$ROOT/test/smoke:/smoke:ro" \
  --entrypoint bash \
  "$IMAGE" -c '
    install -m 0644 /smoke/etcd-config.yaml /usr/local/apisix/conf/config.yaml
    exec /usr/local/bin/agw-entrypoint
  ' >/dev/null

for _ in $(seq 1 60); do
  if curl -sS -o /dev/null http://127.0.0.1:19180/apisix/admin/routes \
      -H 'X-API-KEY: agw-smoke-admin-key'; then
    break
  fi
  if ! docker inspect -f '{{.State.Running}}' "$AGW_NAME" 2>/dev/null | grep -q true; then
    echo "ERROR: AGW 容器提前退出" >&2
    cat /tmp/agw-etcd-gw.log >&2 || true
    exit 1
  fi
  sleep 1
done
docker exec "$AGW_NAME" sh -c '
  if grep -q "init_worker_by_lua error" /usr/local/apisix/logs/error.log; then
    cat /usr/local/apisix/logs/error.log
    exit 1
  fi
'

curl -fsS -D /tmp/agw-admin-headers.txt -o /tmp/agw-admin-body.json \
  http://127.0.0.1:19180/apisix/admin/routes \
  -H 'X-API-KEY: agw-smoke-admin-key'

echo "[etcd] bundled Admin UI"
curl -sS -D /tmp/agw-ui-redirect.headers -o /dev/null \
  http://127.0.0.1:19180/ui
grep -Fxq $'HTTP/1.1 301 Moved Permanently\r' /tmp/agw-ui-redirect.headers
grep -Fxq $'Location: /ui/\r' /tmp/agw-ui-redirect.headers

curl -fsS -D /tmp/agw-ui-headers.txt -o /tmp/agw-ui-index.html \
  http://127.0.0.1:19180/ui/
grep -Fxq $'HTTP/1.1 200 OK\r' /tmp/agw-ui-headers.txt
grep -Fxiq $'Cache-Control: no-store\r' /tmp/agw-ui-headers.txt
test "$(grep -ci '^Server:' /tmp/agw-ui-headers.txt || true)" -eq 1
grep -Fxq $'Server: agw-etcd\r' /tmp/agw-ui-headers.txt
grep -Fq '<title>AGW Dashboard</title>' /tmp/agw-ui-index.html
grep -Fq 'href="/ui/agw-favicon.svg"' /tmp/agw-ui-index.html
curl -fsS -o /dev/null http://127.0.0.1:19180/ui/agw-favicon.svg
curl -fsS -o /dev/null http://127.0.0.1:19180/ui/favicon.ico

asset="$(grep -o 'src="/ui/assets/[^"]*\.js"' /tmp/agw-ui-index.html |
  sed -n '1s|^src="/ui/||;1s|"$||;1p')"
test -n "$asset"
curl -fsS -o /dev/null "http://127.0.0.1:19180/ui/$asset"

curl -fsS -o /tmp/agw-ui-fallback.html \
  http://127.0.0.1:19180/ui/not-a-real-route
cmp -s /tmp/agw-ui-index.html /tmp/agw-ui-fallback.html

tr -d '\r' < /tmp/agw-admin-headers.txt
test "$(grep -ci '^Server:' /tmp/agw-admin-headers.txt || true)" -eq 1
test "$(awk '
  BEGIN { IGNORECASE = 1 }
  /^Server:/ {
    sub(/^[^:]+:[[:space:]]*/, "")
    sub(/\r$/, "")
    print
    exit
  }
' /tmp/agw-admin-headers.txt)" = "agw-etcd"
python3 - <<'PY'
import json
with open('/tmp/agw-admin-body.json', encoding='utf-8') as handle:
    data = json.load(handle)
assert data.get('total') == 0, data
PY

if [ "${UI_SMOKE:-0}" = "1" ]; then
  echo "[etcd] Admin UI browser smoke"
  command -v openssl >/dev/null
  test -d "$ROOT/test/ui/node_modules"
  UI_TMP="$(mktemp -d)"
  openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days 2 \
    -subj "/CN=ui-smoke.test" -addext "subjectAltName=DNS:ui-smoke.test" \
    -keyout "$UI_TMP/key.pem" -out "$UI_TMP/cert.pem" >/dev/null 2>&1
  (
    cd "$ROOT/test/ui"
    AGW_UI_BASE_URL="http://127.0.0.1:19180" \
      AGW_ADMIN_KEY='agw-smoke-admin-key' \
      AGW_UI_TEST_CERT="$UI_TMP/cert.pem" \
      AGW_UI_TEST_KEY="$UI_TMP/key.pem" \
      npm test
  )
fi

curl -sS -D /tmp/agw-data-headers.txt -o /dev/null \
  http://127.0.0.1:19080/no-such-route
tr -d '\r' < /tmp/agw-data-headers.txt
test "$(grep -ci '^Server:' /tmp/agw-data-headers.txt || true)" -eq 1
test "$(awk '
  BEGIN { IGNORECASE = 1 }
  /^Server:/ {
    sub(/^[^:]+:[[:space:]]*/, "")
    sub(/\r$/, "")
    print
    exit
  }
' /tmp/agw-data-headers.txt)" = "agw-etcd"

echo "[etcd] external etcd + Admin API + Admin UI + data-plane Server header OK"
