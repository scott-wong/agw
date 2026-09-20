#!/usr/bin/env bash
set -euo pipefail
set -x

ARCH=${ARCH:-`(uname -m | tr '[:upper:]' '[:lower:]')`}


install_apisix_dependencies_rpm() {
    install_dependencies_rpm
    install_openresty_rpm
    install_luarocks
}

install_dependencies_rpm() {
    # install basic dependencies
    if [[ $IMAGE_BASE == "registry.access.redhat.com/ubi9/ubi" ]]; then
        yum install -y --disablerepo=* --enablerepo=ubi-9-appstream-rpms --enablerepo=ubi-9-baseos-rpms wget tar gcc gcc-c++ automake autoconf libtool make git which unzip sudo
        yum install -y --disablerepo=* --enablerepo=ubi-9-appstream-rpms --enablerepo=ubi-9-baseos-rpms yum-utils
    else
        yum install -y wget tar gcc gcc-c++ automake autoconf libtool make curl git which unzip sudo
        yum install -y yum-utils
    fi
}



install_openresty_rpm() {
    # libxml2-devel, libxslt-devel and zlib-devel are required to build the
    # lua-resty-saml dependency (xmlsec1 + saml.c); diffutils provides cmp/diff
    # used by its configure script (absent on UBI); cmake builds rapidjson.
    yum install -y pcre pcre-devel pcre2 pcre2-devel openldap-devel libxml2 libxml2-devel libxslt libxslt-devel zlib-devel diffutils cmake
}

install_luarocks() {
    wget https://raw.githubusercontent.com/apache/apisix/master/utils/linux-install-luarocks.sh
    chmod +x linux-install-luarocks.sh
    ./linux-install-luarocks.sh
}

install_etcd() {
    ETCD_ARCH="amd64"
    if [[ $ARCH == "arm64" ]] || [[ $ARCH == "aarch64" ]]; then
        ETCD_ARCH="arm64"
    fi
    wget https://github.com/etcd-io/etcd/releases/download/"${RUNNING_ETCD_VERSION}"/etcd-"${RUNNING_ETCD_VERSION}"-linux-"${ETCD_ARCH}".tar.gz
    tar -zxvf etcd-"${RUNNING_ETCD_VERSION}"-linux-"${ETCD_ARCH}".tar.gz
}

version_gt() { test "$(echo "$@" | tr " " "\n" | sort -V | head -n 1)" != "$1"; }

is_newer_version() {
    if [ "${checkout_v}" = "master" -o "${checkout_v:0:7}" = "release" ];then
        return 0
    fi

    if [ "${checkout_v:0:1}" = "v" ];then
        version_gt "${checkout_v:1}" "2.2"
    else
        version_gt "${checkout_v}" "2.2"
    fi
}

install_rust() {
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sudo sh -s -- -y
    source "$HOME/.cargo/env"
}

install_apisix() {
    mkdir -p /tmp/build/output/apisix/usr/bin/
    cd /apisix

    # patch rockspec file to install with local repo
    sed -re '/^\s*source\s*=\s*\{$/{:src;n;s/^(\s*url\s*=).*$/\1".\/apisix",/;/\}/!bsrc}' \
         -e '/^\s*source\s*=\s*\{$/{:src;n;/^(\s*branch\s*=).*$/d;/\}/!bsrc}' \
         -i apisix-master-${iteration}.rockspec

    # install rust
    install_rust

    # build the lib and specify the storage path of the package installed
    # To be removed after https://github.com/luarocks/luarocks/issues/1797 is fixed
    luarocks make ./apisix-master-${iteration}.rockspec --tree=/tmp/build/output/apisix/usr/local/apisix/deps --local
    chown -R "$(whoami)":"$(whoami)" /tmp/build/output
    cd ..
    # copy the compiled files to the package install directory
    cp /tmp/build/output/apisix/usr/local/apisix/deps/lib64/luarocks/rocks-5.1/apisix/master-"${iteration}"/bin/apisix /tmp/build/output/apisix/usr/bin/ || true
    cp /tmp/build/output/apisix/usr/local/apisix/deps/lib/luarocks/rocks-5.1/apisix/master-"${iteration}"/bin/apisix /tmp/build/output/apisix/usr/bin/ || true
    # modify the apisix entry shell to be compatible with version 2.2 and 2.3
    if is_newer_version "${checkout_v}"; then
        echo 'use shell '
    else
        bin='#! /usr/local/openresty/luajit/bin/luajit\npackage.path = "/usr/local/apisix/?.lua;" .. package.path'
        sed -i "1s@.*@$bin@" /tmp/build/output/apisix/usr/bin/apisix
    fi
    cp -r /usr/local/apisix/* /tmp/build/output/apisix/usr/local/apisix/
    # apisix/ui is optional: keep packaging it when present (the separate admin
    # UI product is not delivered), but do not fail the build when the upstream
    # source carries no ui/ dir.
    if [ -d /apisix/ui ]; then
        cp -r /apisix/ui /tmp/build/output/apisix/usr/local/apisix/ui
    fi
    mv /tmp/build/output/apisix/usr/local/apisix/deps/share/lua/5.1/apisix /tmp/build/output/apisix/usr/local/apisix/
    # AGW branding: neutralize the upstream Server response header.
    # Upstream only supports APISIX/<ver> vs APISIX via enable_server_tokens,
    # so a custom value is applied to the packaged tree at build time.
    sed -i 's|local ver_header = "APISIX/" .. core.version.VERSION|local ver_header = "agw"|' \
        /tmp/build/output/apisix/usr/local/apisix/apisix/init.lua
    sed -i 's|ver_header = "APISIX"|ver_header = "agw"|' \
        /tmp/build/output/apisix/usr/local/apisix/apisix/init.lua
    grep -q 'ver_header = "agw"' /tmp/build/output/apisix/usr/local/apisix/apisix/init.lua

    # GM (国密) 插件默认启用：APISIX 3.18 的默认插件表在 apisix/cli/config.lua，
    # conf/config.yaml 只是用户覆盖层（数组项被整体替换，故默认表在此改写）。
    # gm 插件依赖运行时链接 Tongsuo（TLS 基线见 scripts/baseline.env）。
    # 使用侧启用国密 TLS 时，需在 conf/config.yaml 里把国密套件写进
    # apisix.ssl.ssl_ciphers（APISIX 默认 cipher 不含国密），
    # 口径见上游 docs/zh/latest/plugins/gm.md。
    apisix_default_conf=/tmp/build/output/apisix/usr/local/apisix/apisix/cli/config.lua
    test -f "$apisix_default_conf"
    sed -i '0,/^    "real-ip",$/s//    "real-ip",\n    "gm",/' "$apisix_default_conf"
    grep -q '^    "gm",$' "$apisix_default_conf"
    if is_newer_version "${checkout_v}"; then
        bin='package.path = "/usr/local/apisix/?.lua;" .. package.path'
        sed -i "1s@.*@$bin@" /tmp/build/output/apisix/usr/local/apisix/apisix/cli/apisix.lua
    else
        echo ''
    fi
    sed -i '1i package.path = "/usr/local/apisix/deps/share/lua/5.1/?/init.lua;" .. package.path' /tmp/build/output/apisix/usr/local/apisix/apisix/cli/apisix.lua
    # delete unnecessary files
    rm -rf /tmp/build/output/apisix/usr/local/apisix/deps/lib64/luarocks
    rm -rf /tmp/build/output/apisix/usr/local/apisix/deps/lib/luarocks/rocks-5.1/apisix/master-"${iteration}"/doc
}

install_golang() {
    GO_VERSION="1.19.6"
    GO_ARCH="amd64"
    if [[ $ARCH == "arm64" ]] || [[ $ARCH == "aarch64" ]]; then
        GO_ARCH="arm64"
    fi
    wget https://dl.google.com/go/go"${GO_VERSION}".linux-"${GO_ARCH}".tar.gz
    tar -xzf go"${GO_VERSION}".linux-"${GO_ARCH}".tar.gz
    mv go /usr/local
}




case_opt=$1
shift

case ${case_opt} in
install_apisix_dependencies_rpm)
    install_apisix_dependencies_rpm
    ;;
install_openresty_rpm)
    install_openresty_rpm
    ;;
install_etcd)
    install_etcd
    ;;
install_apisix)
    install_apisix
    ;;
install_luarocks)
    install_luarocks
    ;;
esac
