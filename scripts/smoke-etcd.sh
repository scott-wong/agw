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

cleanup() {
  docker logs "$AGW_NAME" > /tmp/agw-etcd-gw.log 2>&1 || true
  docker logs "$ETCD_NAME" > /tmp/agw-etcd.log 2>&1 || true
  docker rm -f "$AGW_NAME" "$ETCD_NAME" >/dev/null 2>&1 || true
  docker network rm "$NETWORK" >/dev/null 2>&1 || true
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
  -v "$CONFIG:/usr/local/apisix/conf/config.yaml:ro" \
  "$IMAGE" >/dev/null

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

curl -fsS -D /tmp/agw-admin-headers.txt -o /tmp/agw-admin-body.json \
  http://127.0.0.1:19180/apisix/admin/routes \
  -H 'X-API-KEY: agw-smoke-admin-key'
tr -d '\r' < /tmp/agw-admin-headers.txt
test "$(grep -ci '^Server:' /tmp/agw-admin-headers.txt || true)" -eq 1
grep -i '^Server:' /tmp/agw-admin-headers.txt | grep -Fxq 'Server: agw-etcd'
python3 - <<'PY'
import json
with open('/tmp/agw-admin-body.json', encoding='utf-8') as handle:
    data = json.load(handle)
assert data.get('total') == 0, data
PY

curl -sS -D /tmp/agw-data-headers.txt -o /dev/null \
  http://127.0.0.1:19080/no-such-route
tr -d '\r' < /tmp/agw-data-headers.txt
test "$(grep -ci '^Server:' /tmp/agw-data-headers.txt || true)" -eq 1
grep -i '^Server:' /tmp/agw-data-headers.txt | grep -Fxq 'Server: agw-etcd'

echo "[etcd] external etcd + Admin API + data-plane Server header OK"
