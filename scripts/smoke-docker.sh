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

# Docker passes the command's arguments after the shell script. Values are
# derived from the third/fourth arguments to avoid interpolating test strings
# into the shell program itself.
run_header_case_with_env() {
  local config="$1" expected="$2" label="$3"
  echo "[smoke] Server header: ${label}"
  docker run --rm \
    --entrypoint bash \
    -e EXPECTED_VALUE="$expected" \
    -e EXPECTED_LABEL="$label" \
    -e EXPECTED_COUNT=1 \
    -v "$SMOKE_DIR/$config:/usr/local/apisix/conf/config.yaml:ro" \
    -v "$SMOKE_DIR/standalone-apisix.yaml:/usr/local/apisix/conf/apisix.yaml:ro" \
    "$IMAGE" -exc '
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
      exec 3<>/dev/tcp/127.0.0.1/9080
      printf "HEAD /no-such-route HTTP/1.0\r\nHost: 127.0.0.1\r\n\r\n" >&3
      timeout 10 cat <&3 > /tmp/server-headers.txt || true
      exec 3>&-
      tr -d "\r" < /tmp/server-headers.txt
      count=$(grep -ci "^Server:" /tmp/server-headers.txt || true)
      test "$count" -eq "$EXPECTED_COUNT"
      if [ "$EXPECTED_COUNT" -eq 1 ]; then
        awk "tolower(\$1) == \"server:\" {sub(/^[^:]+:[[:space:]]*/, \"\"); print}" /tmp/server-headers.txt \
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
  -v "$SMOKE_DIR/standalone-config-disabled.yaml:/usr/local/apisix/conf/config.yaml:ro" \
  -v "$SMOKE_DIR/standalone-apisix.yaml:/usr/local/apisix/conf/apisix.yaml:ro" \
  "$IMAGE" -exc '
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
    exec 3<>/dev/tcp/127.0.0.1/9080
    printf "HEAD /no-such-route HTTP/1.0\r\nHost: 127.0.0.1\r\n\r\n" >&3
    timeout 10 cat <&3 > /tmp/server-headers.txt || true
    exec 3>&-
    tr -d "\r" < /tmp/server-headers.txt
    count=$(grep -ci "^Server:" /tmp/server-headers.txt || true)
    test "$count" -eq "$EXPECTED_COUNT"
  '

for invalid in server-header-invalid-empty.yaml server-header-invalid-control.yaml server-header-invalid-long.yaml; do
  echo "[smoke] reject invalid config: ${invalid}"
  if docker run --rm \
      --entrypoint bash \
      -v "$SMOKE_DIR/$invalid:/usr/local/apisix/conf/config.yaml:ro" \
      "$IMAGE" -c '/usr/local/bin/apisix init >/tmp/invalid.log 2>&1'; then
    echo "ERROR: 非法 server_header 被接受: $invalid" >&2
    exit 1
  fi
done

echo "[smoke] all image checks OK"
