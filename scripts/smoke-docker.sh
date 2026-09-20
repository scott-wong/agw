#!/usr/bin/env bash
# smoke-docker.sh — 交付镜像冒烟：运行时（Tongsuo/国密/限流 lua）+ apisix init
# + standalone 文件驱动启动断言 Server: agw（去字符门禁）。用法: smoke-docker.sh <image>
set -euo pipefail
IMAGE=${1:?用法: smoke-docker.sh <image>}
SMOKE_DIR="$(cd "$(dirname "$0")/.." && pwd)/test/smoke"

echo "[smoke] ${IMAGE} version"
docker run --rm "$IMAGE" /usr/bin/apisix version
echo "[smoke] openresty -V"
docker run --rm "$IMAGE" /usr/local/openresty/bin/openresty -V 2>&1 | head -n 5
echo "[smoke] tongsuo openssl version"
docker run --rm "$IMAGE" /usr/local/openresty/tongsuo/bin/openssl version
echo "[smoke] runtime + gm plugin + SM2/NTLS handshake"
docker run --rm -v "$SMOKE_DIR:/smoke:ro" "$IMAGE" bash /smoke/runtime-smoke.sh
echo "[smoke] apisix init (no etcd)"
docker run --rm "$IMAGE" bash -exc '
  /usr/bin/apisix init
  test -f /usr/local/apisix/conf/nginx.conf
'
echo "[smoke] standalone Server header branding"
docker run --rm \
  -v "$SMOKE_DIR/standalone-config.yaml:/usr/local/apisix/conf/config.yaml" \
  -v "$SMOKE_DIR/standalone-apisix.yaml:/usr/local/apisix/conf/apisix.yaml" \
  "$IMAGE" bash -exc '
    /usr/bin/apisix init
    # File-driven standalone (role data_plane + config_provider yaml)
    # needs no etcd; `apisix start` skips init_etcd for data_plane.
    /usr/bin/apisix start
    for i in 1 2 3 4 5 6; do
      (echo > /dev/tcp/127.0.0.1/9080) 2>/dev/null && break
      sleep 2
    done
    exec 3<>/dev/tcp/127.0.0.1/9080
    printf "HEAD /no-such-route HTTP/1.0\r\nHost: 127.0.0.1\r\n\r\n" >&3
    head -8 <&3 | tee /tmp/resp.txt
    grep -i "^Server: agw" /tmp/resp.txt
    /usr/bin/apisix stop
  '
echo "[smoke] all OK"
