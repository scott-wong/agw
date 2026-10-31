#!/usr/bin/env bash
# Image smoke: runtime, configurable Server header, invalid config rejection.
# Usage: smoke-docker.sh <image> <openeuler|ubuntu> [expected-version]
set -euo pipefail

IMAGE="${1:?用法: smoke-docker.sh <image> <variant> [version]}"
VARIANT="${2:?缺少 variant}"
EXPECTED_VERSION="${3:-$(tr -d ' \n' < "$(dirname "$0")/../VERSION")}"
EXPECTED_UPSTREAM="${EXPECTED_VERSION%%-*}"
SMOKE_DIR="$(cd "$(dirname "$0")/.." && pwd)/test/smoke"

case "$VARIANT" in
  openeuler) OS_PATTERN='ID="openEuler"' ;;
  ubuntu) OS_PATTERN='ID=ubuntu' ;;
  *) echo "错误: 未知 variant $VARIANT" >&2; exit 1 ;;
esac

echo "[smoke] image config: inherited root user"
test -z "$(docker image inspect --format '{{.Config.User}}' "$IMAGE")"

echo "[smoke] runtime"
docker run --rm --entrypoint bash -v "$SMOKE_DIR:/smoke:ro" "$IMAGE" /smoke/runtime-smoke.sh
docker run --rm --entrypoint bash "$IMAGE" -c \
  "grep -q '${OS_PATTERN}' /etc/os-release \
   && /usr/local/bin/apisix version | grep -q '${EXPECTED_UPSTREAM}' \
   && grep -q '^version=${EXPECTED_VERSION}$' /usr/local/share/agw/image-provenance.txt"

# Pass fixture names and expected values through the environment so the
# container-side shell program never interpolates host-controlled strings.
run_header_case_with_env() {
  local config="$1" expected="$2" label="$3"
  echo "[smoke] Server header: ${label}"
  docker run --rm \
    --entrypoint bash \
    -e CONFIG_NAME="$config" \
    -e EXPECTED_VALUE="$expected" \
    -e EXPECTED_COUNT=1 \
    -v "$SMOKE_DIR:/smoke:ro" \
    "$IMAGE" -exc '
      install -m 0644 "/smoke/$CONFIG_NAME" /usr/local/apisix/conf/config.yaml
      install -m 0644 /smoke/standalone-apisix.yaml /usr/local/apisix/conf/apisix.yaml
      /usr/local/bin/apisix init
      /usr/local/bin/apisix start
      trap "/usr/local/bin/apisix stop >/dev/null 2>&1 || true" EXIT
      for _ in $(seq 1 20); do
        if (exec 3<>/dev/tcp/127.0.0.1/9080) 2>/dev/null; then
          exec 3>&-
          break
        fi
        sleep 1
      done
      if grep -q "init_worker_by_lua error" /usr/local/apisix/logs/error.log; then
        cat /usr/local/apisix/logs/error.log
        exit 1
      fi
      exec 3<>/dev/tcp/127.0.0.1/9080
      printf "HEAD /no-such-route HTTP/1.0\r\nHost: 127.0.0.1\r\n\r\n" >&3
      timeout 10 cat <&3 > /tmp/server-headers.txt || true
      exec 3>&-
      tr -d "\r" < /tmp/server-headers.txt
      count=$(grep -ci "^Server:" /tmp/server-headers.txt || true)
      test "$count" -eq "$EXPECTED_COUNT"
      if [ "$EXPECTED_COUNT" -eq 1 ]; then
        tr -d "\r" < /tmp/server-headers.txt \
          | awk "tolower(\$1) == \"server:\" {sub(/^[^:]+:[[:space:]]*/, \"\"); print}" \
          | grep -Fxq "$EXPECTED_VALUE"
      fi
    '
}

run_header_case_with_env standalone-config.yaml agw default
run_header_case_with_env standalone-config-custom.yaml agw-custom custom

echo "[smoke] Server header: disabled"
docker run --rm \
  --entrypoint bash \
  -e EXPECTED_COUNT=0 \
  -v "$SMOKE_DIR:/smoke:ro" \
  "$IMAGE" -exc '
    install -m 0644 /smoke/standalone-config-disabled.yaml \
      /usr/local/apisix/conf/config.yaml
    install -m 0644 /smoke/standalone-apisix.yaml \
      /usr/local/apisix/conf/apisix.yaml
    /usr/local/bin/apisix init
    /usr/local/bin/apisix start
    trap "/usr/local/bin/apisix stop >/dev/null 2>&1 || true" EXIT
    for _ in $(seq 1 20); do
      if (exec 3<>/dev/tcp/127.0.0.1/9080) 2>/dev/null; then
        exec 3>&-
        break
      fi
      sleep 1
    done
      if grep -q "init_worker_by_lua error" /usr/local/apisix/logs/error.log; then
        cat /usr/local/apisix/logs/error.log
        exit 1
      fi
    exec 3<>/dev/tcp/127.0.0.1/9080
    printf "HEAD /no-such-route HTTP/1.0\r\nHost: 127.0.0.1\r\n\r\n" >&3
    timeout 10 cat <&3 > /tmp/server-headers.txt || true
    exec 3>&-
    tr -d "\r" < /tmp/server-headers.txt
    count=$(grep -ci "^Server:" /tmp/server-headers.txt || true)
    test "$count" -eq "$EXPECTED_COUNT"
  '

for invalid in \
    server-header-invalid-empty.yaml \
    server-header-invalid-control.yaml \
    server-header-invalid-long.yaml \
    server-header-invalid-quote.yaml \
    server-header-invalid-dollar.yaml; do
  echo "[smoke] reject invalid config: ${invalid}"
  if docker run --rm \
      --entrypoint bash \
      -e CONFIG_NAME="$invalid" \
      -v "$SMOKE_DIR:/smoke:ro" \
      "$IMAGE" -c '
        install -m 0644 "/smoke/$CONFIG_NAME" /usr/local/apisix/conf/config.yaml
        /usr/local/bin/apisix init >/tmp/invalid.log 2>&1
      '; then
    echo "ERROR: 非法 server_header 被接受: $invalid" >&2
    exit 1
  fi
done

echo "[smoke] same-SNI TLS/TLCP dual stack"
docker run --rm \
  --entrypoint bash \
  -v "$SMOKE_DIR:/smoke:ro" \
  "$IMAGE" /smoke/gm-dual-tls-apisix.sh

echo "[smoke] all image checks OK"
