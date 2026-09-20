#!/usr/bin/env bash
# verify-debrand.sh — 去字符 grep 门禁：AGW 是独立开放项目，仓库内不得出现
# 内部产品/组织/渠道痕迹（众澄 / zc-agw / eunited / codeup / 云效 / ACR），
# 分发路径与构建配置也不得出现上游未使用的发行形态（dashboard / apisix-base /
# debian / bookworm）。
#
# 白名单（Allowlist，非品牌化位置）：
#   ./LICENSE                     Apache-2.0 原文
#   ./packaging/fpm/Dockerfile    fpm 打包工具镜像（apt 语法必需的 DEBIAN_FRONTEND）
# evidence/ 由 CI 回填事实记录（SBOM 依赖名等），不属品牌化位置。
# 关系性表述（based on Apache APISIX）不在禁词内。
set -euo pipefail
cd "$(dirname "$0")/.."

ALLOWED=(
  "./LICENSE"
  "./packaging/fpm/Dockerfile"
)
# 禁词：内部痕迹 + 未使用发行形态。`\bacr\b` 用词边界，避免误伤 across 之类单词。
PATTERN='众澄|\bzc\b|zc[-_]agw|eunited|codeup|云效|aliyuncs|\bacr\b|dashboard|apisix-base|debian|bookworm'

HITS=$(grep -rniI -E "$PATTERN" \
  --exclude-dir=.git --exclude-dir=evidence --exclude-dir=distfiles \
  --exclude=verify-debrand.sh \
  . || true)

if [ -z "$HITS" ]; then
  echo "[debrand] 零命中，门禁通过"
  exit 0
fi

FAIL=0
while IFS= read -r line; do
  file="${line%%:*}"
  ok=0
  for a in "${ALLOWED[@]}"; do
    [[ "$file" == "$a" ]] && ok=1
  done
  if [ "$ok" -eq 0 ]; then
    echo "[debrand] 违规: $line"
    FAIL=1
  fi
done <<< "$HITS"

if [ "$FAIL" -ne 0 ]; then
  echo "[debrand] 门禁失败：存在白名单外的禁词命中" >&2
  exit 1
fi
echo "[debrand] 命中均在白名单内，门禁通过"
