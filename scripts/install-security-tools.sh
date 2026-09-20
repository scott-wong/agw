#!/usr/bin/env bash
set -euo pipefail
# install-security-tools.sh — 安装固定版本的 SBOM 与漏洞扫描工具
# 用法: ./scripts/install-security-tools.sh [syft|grype|trivy|all ...]
# 环境变量:
#   INSTALL_DIR  安装目录（默认 /usr/local/bin）

INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"
DOWNLOAD_TIMEOUT="${DOWNLOAD_TIMEOUT:-120}"
DOWNLOAD_RETRIES="${DOWNLOAD_RETRIES:-0}"

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" 2>/dev/null | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'
  else
    echo "错误: 未找到 sha256sum/shasum" >&2
    return 1
  fi
}

download_file() {
  local url="$1"
  local output="$2"

  if command -v curl >/dev/null 2>&1; then
    curl --fail --location --show-error --silent \
      --connect-timeout 15 --max-time "$DOWNLOAD_TIMEOUT" \
      --retry "$DOWNLOAD_RETRIES" --retry-delay 2 \
      --speed-limit 4096 --speed-time 20 \
      --output "$output" "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget --timeout=30 --dns-timeout=15 --connect-timeout=15 \
      --read-timeout=60 --tries=1 --output-document="$output" "$url"
  else
    echo "错误: 需要 curl 或 wget" >&2
    return 1
  fi
}

install_tool() {
  local tool="$1"
  local version=""
  local asset=""
  local expected_sha256=""

  case "$tool" in
    syft)
      version="v1.51.1"
      asset="syft_1.51.1_linux_amd64.tar.gz"
      expected_sha256="8fcb33017a0dc1058298c923c436d19dfa68ae93968e0b423248542e3afb9fc3"
      ;;
    grype)
      version="v0.118.0"
      asset="grype_0.118.0_linux_amd64.tar.gz"
      expected_sha256="1d444c5e7360471815f7158f71935fcecc68a3c417d85c7344f770854300bba2"
      ;;
    trivy)
      version="v0.74.0"
      asset="trivy_0.74.0_Linux-64bit.tar.gz"
      expected_sha256="2ae6fe3ee734b7fdf11335663e18c75ea12dccc76062f09f164a3b0f8be4371a"
      ;;
    *)
      echo "错误: 不支持的工具 $tool" >&2
      return 1
      ;;
  esac

  local release_url="https://github.com/anchore/${tool}/releases/download/${version}/${asset}"
  if [[ "$tool" == "trivy" ]]; then
    release_url="https://github.com/aquasecurity/trivy/releases/download/${version}/${asset}"
  fi
  local urls=(
    "https://ghfast.top/${release_url}"
    "https://gh-proxy.com/${release_url}"
    "https://ghproxy.net/${release_url}"
    "$release_url"
  )

  local work_dir
  work_dir="$(mktemp -d)"
  local archive="$work_dir/$asset"
  local downloaded=false

  for url in "${urls[@]}"; do
    echo "[tools] 下载 ${tool} ${version}: $url"
    rm -f "$archive"
    if ! download_file "$url" "$archive"; then
      echo "[tools] 下载失败，继续尝试下一来源" >&2
      continue
    fi
    actual_sha256="$(sha256_of "$archive")"
    if [[ "$actual_sha256" == "$expected_sha256" ]]; then
      downloaded=true
      break
    fi
    echo "[tools] SHA256 不匹配，继续尝试下一来源" >&2
    echo "  期望: $expected_sha256" >&2
    echo "  实际: $actual_sha256" >&2
  done

  if [[ "$downloaded" != true ]]; then
    rm -rf "$work_dir"
    echo "错误: ${tool} ${version} 所有下载源均失败" >&2
    exit 1
  fi
  echo "[tools] ${tool} ${version} SHA256 校验通过"

  if ! tar -xzf "$archive" -C "$work_dir"; then
    rm -rf "$work_dir"
    echo "错误: ${tool} 解压失败" >&2
    exit 1
  fi

  local binary_path="$work_dir/$tool"
  if [[ ! -f "$binary_path" ]]; then
    binary_path="$(find "$work_dir" -type f -name "$tool" -perm -u+x | head -n 1)"
  fi
  if [[ -z "$binary_path" || ! -f "$binary_path" ]]; then
    rm -rf "$work_dir"
    echo "错误: 解压后未找到 ${tool} 二进制" >&2
    exit 1
  fi

  mkdir -p "$INSTALL_DIR"
  install -m 0755 "$binary_path" "$INSTALL_DIR/$tool"
  rm -rf "$work_dir"
  echo "[tools] 已安装 $INSTALL_DIR/$tool"
}

if [[ "$#" -eq 0 || "${1:-}" == "all" ]]; then
  set -- syft grype trivy
fi

for tool in "$@"; do
  install_tool "$tool"
done
