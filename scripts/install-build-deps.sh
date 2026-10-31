#!/usr/bin/env bash
# Install only build-stage packages inside the target distribution.
set -euo pipefail

DISTRO="${1:?用法: install-build-deps.sh <openeuler|ubuntu>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

case "$DISTRO" in
  openeuler)
    bash "$SCRIPT_DIR/configure-openeuler-repo.sh"
    dnf -y --setopt=max_parallel_downloads=10 makecache
    dnf -y --setopt=install_weak_deps=False \
      --setopt=max_parallel_downloads=10 install \
      autoconf automake binutils bzip2 ca-certificates cmake curl diffutils findutils \
      gawk gcc gcc-c++ git libtool make patch perl perl-Digest-SHA perl-IPC-Cmd \
      pkgconf pcre-devel pcre2-devel readline-devel openldap-devel libxml2-devel \
      libxslt-devel libyaml-devel zlib-devel unzip wget which xz
    dnf clean all
    rm -rf /var/cache/dnf
    ;;
  ubuntu)
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y --no-install-recommends \
      autoconf automake binutils bzip2 build-essential ca-certificates cmake curl \
      diffutils file findutils gawk git libldap2-dev libreadline-dev libtool \
      libpcre2-dev libpcre3-dev libxml2-dev libxslt1-dev libyaml-dev patch \
      perl pkg-config zlib1g-dev unzip wget xz-utils
    update-alternatives --set awk /usr/bin/gawk
    apt-get clean
    rm -rf /var/lib/apt/lists/*
    ;;
  *)
    echo "错误: 不支持的目标发行版 $DISTRO" >&2
    exit 1
    ;;
esac

command -v gcc
command -v g++
command -v gawk
command -v make
command -v perl
command -v ar
gawk --version | sed -n '1p' | grep -q 'GNU Awk'
