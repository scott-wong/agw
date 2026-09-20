#!/usr/bin/env bash
set -euo pipefail
set -x

ARCH=${ARCH:-`(uname -m | tr '[:upper:]' '[:lower:]')`}
BUILD_PATH=${BUILD_PATH:-`pwd`}




build_apisix_runtime_rpm() {
    if [[ "$IMAGE_BASE" == "rockylinux" || "$IMAGE_BASE" == "centos" ]]; then
        # RHEL/Rocky/CentOS el8/el9 toolchain. perl-core provides the core
        # modules OpenSSL's Configure needs (FindBin, Pod::Usage, ...); the
        # granular perl-FindBin is hidden by modular filtering on el8.
        # perl-App-cpanminus (cpanm, from EPEL) is required by
        # build-apisix-runtime.sh.
        yum install -y epel-release || true
        yum install -y --allowerasing \
            sudo git patch readline-devel perl-core perl-IPC-Cmd perl-App-cpanminus \
            gcc gcc-c++ make xz curl wget gnupg2 ca-certificates which tar findutils yum-utils
    else
        # UBI (default)
        dnf install -y yum-utils
        yum -y install --disablerepo=* --enablerepo=ubi-9-appstream-rpms --enablerepo=ubi-9-baseos-rpms gcc gcc-c++ patch wget git make sudo xz cpanminus
    fi

    command -v gcc
    gcc --version

    # OpenResty signs el8 packages with the legacy (SHA1) key and el9+ packages
    # with the new pubkey2 (RSA/SHA256). el8's crypto policy still accepts SHA1
    # but el9's rejects it, so pick the matching repo to keep GPG verification on.
    if [[ "$IMAGE_TAG" == "8" ]]; then
        yum-config-manager --add-repo https://openresty.org/package/centos/openresty.repo
    else
        yum-config-manager --add-repo https://openresty.org/package/centos/openresty2.repo
    fi
    yum -y install openresty-pcre-devel openresty-zlib-devel

    export_openresty_variables
    ${BUILD_PATH}/scripts/build-apisix-runtime.sh
}



export_openresty_variables() {
    export openssl_prefix=/usr/local/openresty/tongsuo
    export zlib_prefix=/usr/local/openresty/zlib
    export pcre_prefix=/usr/local/openresty/pcre
    export OR_PREFIX=/usr/local/openresty

    export cc_opt="-DNGX_LUA_ABORT_AT_PANIC -I${zlib_prefix}/include -I${pcre_prefix}/include -I${openssl_prefix}/include"
    export ld_opt="-L${zlib_prefix}/lib -L${pcre_prefix}/lib -L${openssl_prefix}/lib64 -Wl,-rpath,${zlib_prefix}/lib:${pcre_prefix}/lib:${openssl_prefix}/lib64"
}


case_opt=$1

case ${case_opt} in
build_apisix_runtime_rpm)
    build_apisix_runtime_rpm
    ;;
esac
