#!/usr/bin/env bash
# Install runtime libraries into the clean final stage. Compilers, headers,
# package-manager metadata and build tools are intentionally absent.
set -euo pipefail

DISTRO="${1:?用法: install-runtime-deps.sh <openeuler|ubuntu>}"

case "$DISTRO" in
  openeuler)
    dnf -y makecache
    dnf -y --setopt=install_weak_deps=False install \
      brotli ca-certificates findutils libgcc libstdc++ libxml2 libxslt \
      libyaml ncurses-libs openldap readline
    dnf clean all
    rm -rf /var/cache/dnf
    ;;
  ubuntu)
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y --no-install-recommends \
      ca-certificates findutils libbrotli1 libgcc-s1 libldap2 libncursesw6 \
      libreadline8t64 libstdc++6 libxml2 libxslt1.1 libyaml-0-2
    apt-get clean
    rm -rf /var/lib/apt/lists/*
    ;;
  *)
    echo "错误: 不支持的目标发行版 $DISTRO" >&2
    exit 1
    ;;
esac

if command -v gcc >/dev/null 2>&1 || command -v make >/dev/null 2>&1; then
  echo "错误: 最终镜像泄露了编译器/构建工具" >&2
  exit 1
fi
