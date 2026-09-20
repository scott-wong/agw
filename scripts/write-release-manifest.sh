#!/usr/bin/env bash
# write-release-manifest.sh — 生成正式发布清单（RPM SHA256 + 镜像 digest + 源码定位）。
# 用法（环境变量）：见下方 :? 断言；OUT 默认 release-manifest.json。
set -euo pipefail

RELEASE_VERSION="${RELEASE_VERSION:?缺少 RELEASE_VERSION}"
IMAGE_REPOSITORY="${IMAGE_REPOSITORY:?缺少 IMAGE_REPOSITORY}"
IMAGE_DIGEST="${IMAGE_DIGEST:?缺少 IMAGE_DIGEST}"
RPM_FILE="${RPM_FILE:?缺少 RPM_FILE}"
SOURCE_COMMIT="${SOURCE_COMMIT:?缺少 SOURCE_COMMIT}"
SOURCE_REPOSITORY="${SOURCE_REPOSITORY:-https://github.com/scott-wong/agw}"
WORKFLOW_RUN_URL="${WORKFLOW_RUN_URL:-}"
OUT="${OUT:-release-manifest.json}"

test -f "$RPM_FILE"
case "$(basename "$RPM_FILE")" in
  agw-*.rpm) ;;
  *)
    echo "错误: 正式 RPM 文件名不符合 agw-*.rpm: $RPM_FILE" >&2
    exit 1
    ;;
esac
if [[ ! "$IMAGE_DIGEST" =~ ^sha256:[0-9a-f]{64}$ ]]; then
  echo "错误: 非法镜像 digest: $IMAGE_DIGEST" >&2
  exit 1
fi

if command -v sha256sum >/dev/null 2>&1; then
  RPM_SHA256="$(sha256sum "$RPM_FILE" | awk '{print $1}')"
else
  RPM_SHA256="$(shasum -a 256 "$RPM_FILE" | awk '{print $1}')"
fi
UPSTREAM_VERSION="${RELEASE_VERSION%%-*}"
CREATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

python3 - "$OUT" "$RELEASE_VERSION" "$UPSTREAM_VERSION" "$SOURCE_REPOSITORY" \
  "$SOURCE_COMMIT" "$WORKFLOW_RUN_URL" "$RPM_FILE" "$RPM_SHA256" \
  "$IMAGE_REPOSITORY" "$IMAGE_DIGEST" "$CREATED_AT" <<'PY'
import json
import os
import sys

(
    output,
    release_version,
    upstream_version,
    source_repository,
    source_commit,
    workflow_run_url,
    rpm_file,
    rpm_sha256,
    image_repository,
    image_digest,
    created_at,
) = sys.argv[1:]

manifest = {
    "schemaVersion": 1,
    "product": "AGW",
    "version": release_version,
    "upstreamVersion": upstream_version,
    "createdAt": created_at,
    "source": {
        "repository": source_repository,
        "commit": source_commit,
        "tag": f"v{release_version}",
        "workflowRun": workflow_run_url,
    },
    "artifacts": {
        "rpm": {
            "name": os.path.basename(rpm_file),
            "sha256": rpm_sha256,
        },
        "image": {
            "repository": image_repository,
            "digest": image_digest,
            "tags": [release_version, upstream_version, "latest"],
            "platform": "linux/amd64",
            "baseOs": "Anolis 8.10",
        },
    },
}

with open(output, "w", encoding="utf-8") as handle:
    json.dump(manifest, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY

echo "[manifest] 已生成 $OUT"
cat "$OUT"
