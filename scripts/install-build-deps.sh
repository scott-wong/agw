#!/usr/bin/env bash
# Install only build-stage packages inside the target distribution.
set -euo pipefail

DISTRO="${1:?用法: install-build-deps.sh <openeuler|ubuntu>}"

case "$DISTRO" in
  openeuler)
    dnf -y makecache
    dnf -y --setopt=install_weak_deps=False install \
      autoconf automake bzip2 ca-certificates cmake curl diffutils findutils \
      gcc gcc-c++ git libtool make patch perl perl-Digest-SHA perl-IPC-Cmd \
      pkgconf readline-devel openldap-devel libxml2-devel \
      libxslt-devel libyaml-devel wget which xz
    dnf clean all
    rm -rf /var/cache/dnf
    ;;
  ubuntu)
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y --no-install-recommends \
      autoconf automake bzip2 build-essential ca-certificates cmake curl \
      diffutils file findutils git libldap2-dev libreadline-dev libtool \
      libxml2-dev libxslt1-dev libyaml-dev patch perl pkg-config wget xz-utils
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
command -v make
command -v perl
