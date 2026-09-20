#!/usr/bin/env bash
# gen-self-ratio.sh — 产出自研比例 self-developed-ratio.json（口径见 09-ip/SELF_DEVELOPED.md）
# 用法: bash scripts/gen-self-ratio.sh [output]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT="${1:-$ROOT/evidence/09-ip/self-developed-ratio.json}"
VERSION="$(tr -d ' \n' < "$ROOT/VERSION")"

# 分子：vendor patch 新增行 + modules/ 代码行。AGW v1 当前为 0。
NUM_PATCH=0
if ls "$ROOT"/vendor-patches/*.patch >/dev/null 2>&1; then
  NUM_PATCH=$(grep -h '^+' "$ROOT"/vendor-patches/*.patch | grep -v '^+++' | wc -l | tr -d ' ')
fi
NUM_MOD=0
if [ -d "$ROOT/modules" ]; then
  NUM_MOD=$(find "$ROOT/modules" -type f \
    \( -name '*.c' -o -name '*.h' -o -name '*.cpp' -o -name '*.hpp' \
       -o -name '*.java' -o -name '*.xml' -o -name '*.go' -o -name '*.rs' \
       -o -name '*.py' -o -name '*.sh' \) \
    -exec cat {} + 2>/dev/null | wc -l | tr -d ' ')
fi
NUM=$((NUM_PATCH + NUM_MOD))

# 分母：APISIX 3.18.0 基线源码行。要求先执行 make fetch，缺失时硬失败。
DENOM_PATH="$ROOT/build/src"
if [ ! -d "$DENOM_PATH" ]; then
  echo "错误: 分母根目录缺失 build/src（先执行 make fetch）" >&2
  exit 1
fi
DENOM=$(find "$DENOM_PATH" -type f \
  \( -name '*.lua' -o -name '*.c' -o -name '*.h' \) \
  -exec cat {} + 2>/dev/null | wc -l | tr -d ' ')
if [ "$DENOM" -eq 0 ]; then
  echo "错误: 分母为 0" >&2
  exit 1
fi

RATIO=$(python3 -c "print(round($NUM/$DENOM, 6))")
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
mkdir -p "$(dirname "$OUT")"
cat > "$OUT" <<JSON
{
  "product": "AGW",
  "version": "$VERSION",
  "numerator": $NUM,
  "numerator_detail": {"vendor_patch_added_lines": $NUM_PATCH, "module_code_lines": $NUM_MOD},
  "denominator": $DENOM,
  "denominator_detail": "APISIX 3.18.0 基线源码行数（lua/c/h）",
  "ratio": $RATIO,
  "measured_at": "$TS"
}
JSON
echo "[ratio] $NUM / $DENOM = $RATIO -> $OUT"
