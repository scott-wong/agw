#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/scripts/baseline.env"

MODE="${1:?用法: check-image-size.sh <--compressed|--local> <openeuler|ubuntu> <image>}"
VARIANT="${2:?缺少镜像变体}"
TARGET="${3:?缺少镜像引用}"

case "$VARIANT" in
  openeuler|ubuntu) ;;
  *)
    echo "错误: 不支持的镜像变体: $VARIANT" >&2
    exit 1
    ;;
esac

UPPER="$(printf '%s' "$VARIANT" | tr '[:lower:]' '[:upper:]')"
case "$MODE" in
  --compressed)
    LIMIT_VAR="MAX_COMPRESSED_MIB_${UPPER}"
    command -v crane >/dev/null || {
      echo "错误: compressed 模式需要 crane" >&2
      exit 1
    }
    command -v jq >/dev/null || {
      echo "错误: compressed 模式需要 jq" >&2
      exit 1
    }
    LIMIT_MIB="${!LIMIT_VAR:-}"
    ACTUAL_BYTES="$(crane manifest --platform linux/amd64 "$TARGET" |
      jq -er '[.layers[].size] | add')"
    ;;
  --local)
    LIMIT_VAR="MAX_LOCAL_MIB_${UPPER}"
    command -v docker >/dev/null || {
      echo "错误: local 模式需要 docker" >&2
      exit 1
    }
    LIMIT_MIB="${!LIMIT_VAR:-}"
    ACTUAL_BYTES="$(docker image inspect "$TARGET" --format '{{.Size}}')"
    ;;
  *)
    echo "错误: 模式必须是 --compressed 或 --local" >&2
    exit 1
    ;;
esac

if [ -z "${LIMIT_MIB:-}" ]; then
  echo "错误: 未在 scripts/baseline.env 中配置 $LIMIT_VAR" >&2
  exit 1
fi

MAX_BYTES=$((LIMIT_MIB * 1024 * 1024))
ACTUAL_MIB="$(awk -v bytes="$ACTUAL_BYTES" 'BEGIN { printf "%.2f", bytes / 1048576 }')"
printf '[size] %s %s: %s MiB (limit: %s MiB)\n' \
  "$VARIANT" "${MODE#--}" "$ACTUAL_MIB" "$LIMIT_MIB"

if [ "$ACTUAL_BYTES" -gt "$MAX_BYTES" ]; then
  echo "错误: ${VARIANT} 镜像超过大小预算" >&2
  exit 1
fi
