#!/usr/bin/env bash
# Generate release-manifest.json schemaVersion 2 for the two image variants.
set -euo pipefail

RELEASE_VERSION="${RELEASE_VERSION:?缺少 RELEASE_VERSION}"
SOURCE_COMMIT="${SOURCE_COMMIT:?缺少 SOURCE_COMMIT}"
OPENEULER_DIGEST="${OPENEULER_DIGEST:?缺少 OPENEULER_DIGEST}"
UBUNTU_DIGEST="${UBUNTU_DIGEST:?缺少 UBUNTU_DIGEST}"
OPENEULER_SBOM="${OPENEULER_SBOM:?缺少 OPENEULER_SBOM}"
UBUNTU_SBOM="${UBUNTU_SBOM:?缺少 UBUNTU_SBOM}"
WORKFLOW_RUN_URL="${WORKFLOW_RUN_URL:-}"
SOURCE_REPOSITORY="${SOURCE_REPOSITORY:-https://github.com/scott-wong/agw}"
OUT="${OUT:-release-manifest.json}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/baseline.env"

for digest in "$OPENEULER_DIGEST" "$UBUNTU_DIGEST"; do
  [[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]] || {
    echo "错误: 非法镜像 digest: $digest" >&2
    exit 1
  }
done
test -f "$OPENEULER_SBOM"
test -f "$UBUNTU_SBOM"

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

UPSTREAM_VERSION="${RELEASE_VERSION%%-*}"
CREATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

python3 - "$OUT" "$RELEASE_VERSION" "$UPSTREAM_VERSION" "$SOURCE_REPOSITORY" \
  "$SOURCE_COMMIT" "$WORKFLOW_RUN_URL" "$CREATED_AT" \
  "$OPENEULER_DIGEST" "$UBUNTU_DIGEST" "$OPENEULER_SBOM" "$UBUNTU_SBOM" \
  "$(sha256_of "$OPENEULER_SBOM")" "$(sha256_of "$UBUNTU_SBOM")" \
  "$AGW_IMAGE_REPOSITORY" "$OPENEULER_BASE_REF" "$OPENEULER_BASE_INDEX_DIGEST" \
  "$OPENEULER_BASE_AMD64_DIGEST" "$UBUNTU_BASE_REF" "$UBUNTU_BASE_INDEX_DIGEST" \
  "$UBUNTU_BASE_AMD64_DIGEST" "$TRIVY_VERSION" "$SYFT_VERSION" \
  "$RUNTIME_USER" "$NGINX_WORKER_USER" "$TONGSUO_CVE_PARITY" <<'PY'
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
    created_at,
    openeuler_digest,
    ubuntu_digest,
    openeuler_sbom,
    ubuntu_sbom,
    openeuler_sbom_sha,
    ubuntu_sbom_sha,
    image_repository,
    openeuler_base_ref,
    openeuler_base_index_digest,
    openeuler_base_amd64_digest,
    ubuntu_base_ref,
    ubuntu_base_index_digest,
    ubuntu_base_amd64_digest,
    trivy_version,
    syft_version,
    runtime_user,
    nginx_worker_user,
    tongsuo_cve_parity,
) = sys.argv[1:]


def image_record(variant, digest, sbom, sbom_sha, base_ref, index_digest, amd64_digest):
    return {
        "repository": image_repository,
        "digest": digest,
        "tags": [
            f"{release_version}-{variant}",
            f"{upstream_version}-{variant}",
            f"latest-{variant}",
        ],
        "platform": "linux/amd64",
        "baseOs": "openEuler 24.03 LTS SP4" if variant == "openeuler" else "Ubuntu 24.04",
        "baseImage": {
            "reference": base_ref,
            "indexDigest": index_digest,
            "amd64Digest": amd64_digest,
        },
        "runtimeUser": runtime_user,
        "nginxWorkerUser": nginx_worker_user,
        "sbom": {
            "name": os.path.basename(sbom),
            "sha256": sbom_sha,
            "format": "CycloneDX JSON",
        },
    }


manifest = {
    "schemaVersion": 2,
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
    "releasePolicy": {
        "candidateImagesRequired": 2,
        "promoteOnlyAfterAllCandidatesPass": True,
        "offlineImageTar": False,
    },
    "artifacts": {
        "images": {
            "openeuler": image_record(
                "openeuler",
                openeuler_digest,
                openeuler_sbom,
                openeuler_sbom_sha,
                openeuler_base_ref,
                openeuler_base_index_digest,
                openeuler_base_amd64_digest,
            ),
            "ubuntu": image_record(
                "ubuntu",
                ubuntu_digest,
                ubuntu_sbom,
                ubuntu_sbom_sha,
                ubuntu_base_ref,
                ubuntu_base_index_digest,
                ubuntu_base_amd64_digest,
            ),
        }
    },
    "security": {
        "tongsuoCveParity": tongsuo_cve_parity,
        "vulnerabilityScanner": {
            "name": "Trivy",
            "version": trivy_version,
            "blockingSeverities": ["HIGH", "CRITICAL"],
            "secretScanning": "blocking",
            "openEulerOsRpmCoverage": "unsupported",
        },
        "sbomGenerator": {
            "name": "Syft",
            "version": syft_version,
            "reason": "CycloneDX lifecycle coverage includes LuaRocks dependencies",
        },
    },
}

with open(output, "w", encoding="utf-8") as handle:
    json.dump(manifest, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY

echo "[manifest] 已生成 $OUT"
cat "$OUT"
