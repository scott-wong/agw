#!/usr/bin/env bash
set -euo pipefail
set -x

# 基线事实源：scripts/baseline.env（Tongsuo/OpenResty 版本与 commit、运行时模块版本/commit、
# OpenResty tarball SHA256）
SCRIPT_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_BASE/baseline.env"

runtime_version=${runtime_version:-0.0.0}


debug_args=${debug_args:-}
OPENSSL_CONF_PATH=${OPENSSL_CONF_PATH:-$PWD/packaging/rpm/conf/tongsuo/openssl.cnf}


OR_PREFIX=${OR_PREFIX:="/usr/local/openresty"}
# Tongsuo（国密 TLS 库，见 scripts/baseline.env）随运行时一起装在 OR_PREFIX 下，
# 由 RPM 一并打包；不依赖发行版自带的 openssl。
OPENSSL_PREFIX=${OPENSSL_PREFIX:=$OR_PREFIX/tongsuo}
zlib_prefix=${OR_PREFIX}/zlib
pcre_prefix=${OR_PREFIX}/pcre

cc_opt=${cc_opt:-"-DNGX_LUA_ABORT_AT_PANIC -I$zlib_prefix/include -I$pcre_prefix/include -I$OPENSSL_PREFIX/include"}
ld_opt=${ld_opt:-"-L$zlib_prefix/lib -L$pcre_prefix/lib -L$OPENSSL_PREFIX/lib64 -Wl,-rpath,$zlib_prefix/lib:$pcre_prefix/lib:$OPENSSL_PREFIX/lib64"}


# dependencies for building openresty
# 1.31.1.1 是锁定的 OpenResty release 基线（scripts/baseline.env）。
# The API7 patch modules' upstream patch.sh scripts do not recognize it yet
# (upstream PRs api7/ngx_multi_upstream_module#21 and api7/apisix-nginx-module#125
# fix that), so this repo vendors the patched scripts under vendor-patches/ and
# overlays them onto the cloned modules; the 1.29.2 patch sets apply to 1.31.1
# as-is.
OPENRESTY_VERSION=$OPENRESTY_VERSION
# OPENRESTY_SOURCE=master builds from the openresty/openresty master branch
# (via util/mirror-tarballs) instead of a pinned release tarball. The real
# version is read from the repo's util/ver at build time. AGW 发行版 MUST NOT
# 使用 master 模式产出版本号（判非发行）。
OPENRESTY_SOURCE=${OPENRESTY_SOURCE:-"release"}
# Provenance stamp recorded for every build so the workflow can tell which
# OpenResty source the runtime was built against.
OR_SOURCE_STAMP=${OR_SOURCE_STAMP:-"release-${OPENRESTY_VERSION}"}
if [[ ! "$OPENRESTY_VERSION" =~ ^[0-9]+(\.[0-9]+)+$ ]]; then
    echo "ERROR: invalid OPENRESTY_VERSION: $OPENRESTY_VERSION" >&2
    exit 1
fi
ngx_multi_upstream_module_ver="$NGX_MULTI_UPSTREAM_MODULE_VERSION"
mod_dubbo_ver="$MOD_DUBBO_VERSION"
apisix_nginx_module_ver="$APISIX_NGINX_MODULE_VERSION"
if [[ ! "$apisix_nginx_module_ver" =~ ^[A-Za-z0-9._/-]+$ ]]; then
    echo "ERROR: invalid apisix_nginx_module_ver: $apisix_nginx_module_ver" >&2
    exit 1
fi
wasm_nginx_module_ver="$WASM_NGINX_MODULE_VERSION"
lua_var_nginx_module_ver="$LUA_VAR_NGINX_MODULE_VERSION"
lua_resty_events_ver="$LUA_RESTY_EVENTS_VERSION"
ngx_http_ffi_client_ver="$NGX_HTTP_FFI_CLIENT_VERSION"
if [[ ! "$ngx_http_ffi_client_ver" =~ ^[A-Za-z0-9._/-]+$ ]]; then
    echo "ERROR: invalid ngx_http_ffi_client_ver: $ngx_http_ffi_client_ver" >&2
    exit 1
fi
ngx_http_ffi_client_dir="ngx_http_ffi_client-${ngx_http_ffi_client_ver}"


# OpenResty 不捆绑国密能力：nginx 需要用 Tongsuo（铜锁）作为 TLS 库才能提供
# NTLS 双证书（SM2/SM4/SM3）。构建口径参考 api7/apisix-plugin-gm
# doc/gm.md 的 `./config shared enable-ntls`，差异有两处：
#   1) 仓库改用官方 Tongsuo-Project/Tongsuo（api7/tongsuo 已不可用），master 锁 commit；
#   2) 加 --libdir=lib64（RPM 体系），Tongsuo 已移除的 enable-camellia /
#      enable-seed / enable-md2 不再传入（Configure 会判 Unsupported options）。
install_tongsuo(){
    rm -rf Tongsuo
    git clone --depth 1 --branch "$TONGSHUO_REF" "$TONGSHUO_REPO" Tongsuo
    local got
    got=$(git -C Tongsuo rev-parse HEAD)
    if [ "$got" != "$TONGSHUO_COMMIT" ]; then
        echo "ERROR: 基线漂移 — Tongsuo $TONGSHUO_REF 期望 $TONGSHUO_COMMIT，实际 $got" >&2
        exit 1
    fi
    echo "Tongsuo $TONGSHUO_VERSION ($TONGSHUO_COMMIT), OpenSSL core $TONGSHUO_OPENSSL_VERSION"
    cd Tongsuo || exit 1
    # Configure（openssl 3.x 线）需要 IPC::Cmd
    cpanm IPC/Cmd.pm
    export LDFLAGS="-Wl,-rpath,$zlib_prefix/lib:$OPENSSL_PREFIX/lib64"
    ./config shared enable-ntls zlib \
      enable-rfc3779 enable-cms enable-rc5 enable-weak-ssl-ciphers \
      --prefix=$OPENSSL_PREFIX \
      --libdir=lib64               \
      --with-zlib-lib=$zlib_prefix/lib \
      --with-zlib-include=$zlib_prefix/include
    make -j $(nproc) LD_LIBRARY_PATH= CC="gcc"
    sudo make install_sw install_ssldirs
    # xmlsec1（lua-resty-saml 的构建依赖）只探测 <prefix>/lib/libcrypto.{so,a}，
    # 而本仓库按 RPM 体系使用 --libdir=lib64。补一个 lib -> lib64 兼容链接，
    # 让构建期依赖解析与运行期 rpath（仍为 lib64）各自可用。
    if [ ! -e "$OPENSSL_PREFIX/lib/libcrypto.so" ] && [ ! -e "$OPENSSL_PREFIX/lib/libcrypto.a" ]; then
        sudo rmdir "$OPENSSL_PREFIX/lib" 2>/dev/null || true
        sudo ln -sfn lib64 "$OPENSSL_PREFIX/lib"
    fi
    test -e "$OPENSSL_PREFIX/lib/libcrypto.so" || test -e "$OPENSSL_PREFIX/lib/libcrypto.a"
    if [ -f "$OPENSSL_CONF_PATH" ]; then
        sudo cp "$OPENSSL_CONF_PATH" "$OPENSSL_PREFIX"/ssl/openssl.cnf
    fi
    # 冒烟：命令行工具的 "Tongsuo:" 行是编译期印记，缺了说明链到了别的 TLS 库
    "$OPENSSL_PREFIX"/bin/openssl version | grep -q "^Tongsuo: Tongsuo " || {
        echo "ERROR: $OPENSSL_PREFIX/bin/openssl 不是 Tongsuo 构建" >&2
        exit 1
    }
    cd ..
}

if ([ $# -gt 0 ] && [ "$1" == "latest" ]) || [ "$runtime_version" == "0.0.0" ]; then
    debug_args="--with-debug"
fi

prev_workdir="$PWD"
repo=$(basename "$prev_workdir")
workdir=$(mktemp -d)
cd "$workdir" || exit 1


install_tongsuo

if [ "$OPENRESTY_SOURCE" == "master" ]; then
    rm -rf openresty-src openresty-master.tar.gz
    git clone --depth=1 https://github.com/openresty/openresty.git openresty-src
    OR_MASTER_COMMIT=$(git -C openresty-src rev-parse HEAD)
    echo "Building OpenResty from master commit $OR_MASTER_COMMIT"
    echo "$OR_MASTER_COMMIT" > /tmp/openresty-commit
    ( cd openresty-src && ./util/mirror-tarballs )
    OR_SRC_VERSION=$( cd openresty-src && ./util/ver )
    echo "$OR_SRC_VERSION" > /tmp/openresty-version
    echo "OpenResty master source version: $OR_SRC_VERSION"
    tar -zxvpf openresty-src/openresty-${OR_SRC_VERSION}.tar.gz > /dev/null
else
    # The release path also records a stamp; the file must exist in both modes
    # because the runtime Dockerfile COPYs it unconditionally.
    echo "$OR_SOURCE_STAMP" > /tmp/openresty-commit
    wget --no-check-certificate "https://openresty.org/download/openresty-${OPENRESTY_VERSION}.tar.gz"
    # 基线漂移门禁：tarball SHA256 必须与 scripts/baseline.env 登记一致
    echo "$OPENRESTY_SHA256  openresty-${OPENRESTY_VERSION}.tar.gz" | sha256sum -c - || {
        echo "ERROR: 基线漂移 — OpenResty tarball SHA256 mismatch" >&2
        exit 1
    }
    tar -zxvpf "openresty-${OPENRESTY_VERSION}.tar.gz" > /dev/null
fi
or_dir="openresty-${OPENRESTY_VERSION}"
if [ "$OPENRESTY_SOURCE" == "master" ]; then
    or_dir="openresty-${OR_SRC_VERSION}"
fi
echo "Using OpenResty source directory: $or_dir"

if [ "$repo" == lua-resty-events ]; then
    cp -r "$prev_workdir" ./lua-resty-events-${lua_resty_events_ver}
else
    git clone --depth=1 -b $lua_resty_events_ver \
        https://github.com/Kong/lua-resty-events.git \
        lua-resty-events-${lua_resty_events_ver}
fi

if [ "$repo" == ngx_multi_upstream_module ]; then
    cp -r "$prev_workdir" ./ngx_multi_upstream_module-${ngx_multi_upstream_module_ver}
else
    git clone --depth=1 -b $ngx_multi_upstream_module_ver \
        https://github.com/api7/ngx_multi_upstream_module.git \
        ngx_multi_upstream_module-${ngx_multi_upstream_module_ver}
fi

if [ "$repo" == mod_dubbo ]; then
    cp -r "$prev_workdir" ./mod_dubbo-${mod_dubbo_ver}
else
    git clone --depth=1 -b $mod_dubbo_ver \
        https://github.com/api7/mod_dubbo.git \
        mod_dubbo-${mod_dubbo_ver}
fi

if [ "$repo" == apisix-nginx-module ]; then
    cp -r "$prev_workdir" "./apisix-nginx-module-${apisix_nginx_module_ver}"
else
    git clone --depth=1 -b "$apisix_nginx_module_ver" -- \
        https://github.com/api7/apisix-nginx-module.git \
        "apisix-nginx-module-${apisix_nginx_module_ver}"
fi

if [ "$repo" == wasm-nginx-module ]; then
    cp -r "$prev_workdir" ./wasm-nginx-module-${wasm_nginx_module_ver}
else
    git clone --depth=1 -b $wasm_nginx_module_ver \
        https://github.com/api7/wasm-nginx-module.git \
        wasm-nginx-module-${wasm_nginx_module_ver}
fi

if [ "$repo" == lua-var-nginx-module ]; then
    cp -r "$prev_workdir" ./lua-var-nginx-module-${lua_var_nginx_module_ver}
else
    git clone --depth=1 -b $lua_var_nginx_module_ver \
        https://github.com/api7/lua-var-nginx-module \
        lua-var-nginx-module-${lua_var_nginx_module_ver}
fi

if [ "$repo" == ngx_http_ffi_client ]; then
    cp -r "$prev_workdir" "./$ngx_http_ffi_client_dir"
else
    git clone --depth=1 -b "$ngx_http_ffi_client_ver" \
        https://github.com/api7/ngx_http_ffi_client.git \
        "$ngx_http_ffi_client_dir"
fi

# 1.29.2.5 shares 1.29.2.4's bundle versions, so its patches apply cleanly;
# apisix-nginx-module's patch.sh only matches the literal "openresty-1.29.2.4"
# directory name. Hand the patch scripts an alias directory named for the
# version they target. (1.31.1.x is handled by the vendored scripts below and
# needs no alias.)
if [ "$or_dir" == "openresty-1.29.2.5" ]; then
    ln -s openresty-1.29.2.5 openresty-1.29.2.4
    patch_dir_alias="openresty-1.29.2.4"
else
    patch_dir_alias="$or_dir"
fi

# Overlay the vendored patch.sh scripts (upstream PRs
# api7/ngx_multi_upstream_module#21 and api7/apisix-nginx-module#125) so the
# cloned modules recognize openresty-1.31.1.*. The scripts resolve their patch
# files relative to their own location, so copy the whole overlay directory
# into each module. Keep in sync with the cloned module versions
# (vendor-patches/ 序号化 vendor 补丁模块，回退条件见各 patch.sh 头注).
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
cp "$script_dir"/../vendor-patches/0001-ngx-multi-upstream-module/* \
    ngx_multi_upstream_module-${ngx_multi_upstream_module_ver}/
cp "$script_dir"/../vendor-patches/0002-apisix-nginx-module/patch.sh \
    "apisix-nginx-module-${apisix_nginx_module_ver}/patch/patch.sh"

cd ngx_multi_upstream_module-${ngx_multi_upstream_module_ver} || exit 1
./patch.sh ../${patch_dir_alias}
cd ..

cd "apisix-nginx-module-${apisix_nginx_module_ver}/patch" || exit 1
./patch.sh ../../${patch_dir_alias}
cd ../..

cd wasm-nginx-module-${wasm_nginx_module_ver} || exit 1
./install-wasmtime.sh
cd ..


luajit_xcflags=${luajit_xcflags:="-DLUAJIT_NUMMODE=2 -DLUAJIT_ENABLE_LUA52COMPAT"}
no_pool_patch=${no_pool_patch:-}

cd ${or_dir} || exit 1

or_limit_ver=0.09
limit_ver=1.2.0
# Replace the bundled lua-resty-limit-traffic with API7's fork. The release
# tarball bundles it under a version that has drifted across releases, so
# match the bundle directory by prefix; OpenResty master dropped the bundle
# entirely, in which case API7's fork is installed into lualib after `make
# install` instead.
# -print -quit 取代 `| head -n 1`：head 提前退出会让 find 拿到 SIGPIPE（pipefail 下 141）。
limit_bundle_dir=$(find bundle -maxdepth 1 -type d -name 'lua-resty-limit-traffic-*' -print -quit)
if [ -n "$limit_bundle_dir" ]; then
    or_limit_ver=${limit_bundle_dir##*/}
    rm -rf "$limit_bundle_dir"
    wget "https://github.com/api7/lua-resty-limit-traffic/archive/refs/tags/v$limit_ver.tar.gz" -O "lua-resty-limit-traffic-$limit_ver.tar.gz"
    tar -xzf lua-resty-limit-traffic-$limit_ver.tar.gz
    mv lua-resty-limit-traffic-$limit_ver "bundle/$or_limit_ver"
else
    echo "lua-resty-limit-traffic not in bundle; will install API7's fork into lualib."
fi


# ngx_http_ffi_client compiles against lua-nginx-module's public API, which it
# reaches through the bundled copy rather than a separate checkout.
ngx_lua_bundle_dir=$(find bundle -maxdepth 1 -type d -name 'ngx_lua-*' -print -quit)
export NGX_HTTP_LUA_MODULE_DIR="$PWD/$ngx_lua_bundle_dir"

./configure --prefix="$OR_PREFIX" \
    --with-cc-opt="-DAPISIX_RUNTIME_VER=$runtime_version $cc_opt" \
    --with-ld-opt="-Wl,-rpath,$OR_PREFIX/wasmtime-c-api/lib $ld_opt" \
    $debug_args \
    --add-module=../mod_dubbo-${mod_dubbo_ver} \
    --add-module=../ngx_multi_upstream_module-${ngx_multi_upstream_module_ver} \
    --add-module="../apisix-nginx-module-${apisix_nginx_module_ver}" \
    --add-module="../apisix-nginx-module-${apisix_nginx_module_ver}/src/stream" \
    --add-module="../apisix-nginx-module-${apisix_nginx_module_ver}/src/meta" \
    --add-module=../wasm-nginx-module-${wasm_nginx_module_ver} \
    --add-module=../lua-var-nginx-module-${lua_var_nginx_module_ver} \
    --add-module=../lua-resty-events-${lua_resty_events_ver} \
    --add-module=../${ngx_http_ffi_client_dir} \
    --with-poll_module \
    --with-pcre-jit \
    --without-http_rds_json_module \
    --without-http_rds_csv_module \
    --without-lua_rds_parser \
    --with-stream \
    --with-stream_ssl_module \
    --with-stream_ssl_preread_module \
    --with-stream_realip_module \
    --with-http_v2_module \
    --with-http_v3_module \
    --without-mail_pop3_module \
    --without-mail_imap_module \
    --without-mail_smtp_module \
    --with-http_stub_status_module \
    --with-http_realip_module \
    --with-http_addition_module \
    --with-http_auth_request_module \
    --with-http_secure_link_module \
    --with-http_random_index_module \
    --with-http_gzip_static_module \
    --with-http_sub_module \
    --with-http_dav_module \
    --with-http_flv_module \
    --with-http_mp4_module \
    --with-http_gunzip_module \
    --with-threads \
    --with-compat \
    --with-luajit-xcflags="$luajit_xcflags" \
    $no_pool_patch \
    -j`nproc`

make -j`nproc`
sudo make install

# 链接门禁：nginx MUST 动态链接到本仓库 TLS 基线 Tongsuo 的 libssl/libcrypto。
# 这里刻意不传 `--with-openssl=`：nginx 的该选项要求 OpenSSL *源码目录* 并会
# 用 nginx 自己的参数重新 Configure（会丢掉 enable-ntls），把 SSL 静态编进 nginx；
# 上游国密构建口径（apache/apisix gm.md、api7/apisix-plugin-gm gm.md）走的是
# cc_opt/ld_opt 指向 Tongsuo + 动态库 rpath 这条路，NTLS/SM2 由 libssl.so.3 提供。
assert_tongsuo_linkage() {
    local nginx_bin="$OR_PREFIX/nginx/sbin/nginx" libs
    libs=$(ldd "$nginx_bin") || {
        echo "ERROR: 无法解析 $nginx_bin 的动态库" >&2
        exit 1
    }
    echo "$libs" | grep -E 'libssl|libcrypto' || {
        echo "ERROR: $nginx_bin 未链接 libssl/libcrypto" >&2
        exit 1
    }
    echo "$libs" | grep -E 'libssl\.so' | grep -q "$OPENSSL_PREFIX/lib64/" || {
        echo "ERROR: $nginx_bin 的 libssl 不是 $OPENSSL_PREFIX/lib64 下的 Tongsuo" >&2
        exit 1
    }
    echo "$libs" | grep -E 'libcrypto\.so' | grep -q "$OPENSSL_PREFIX/lib64/" || {
        echo "ERROR: $nginx_bin 的 libcrypto 不是 $OPENSSL_PREFIX/lib64 下的 Tongsuo" >&2
        exit 1
    }
    # 功能性印记：SM2 国密套件必须由运行时自带的 Tongsuo 提供
    "$OPENSSL_PREFIX"/bin/openssl ciphers -v 'ECDHE-SM2-SM4-GCM-SM3' \
        | grep -q 'NTLSv1.1' || {
        echo "ERROR: $OPENSSL_PREFIX 缺少 NTLS/SM2 国密套件" >&2
        exit 1
    }
    echo "Tongsuo linkage OK: $nginx_bin -> $OPENSSL_PREFIX/lib64"
}
assert_tongsuo_linkage
cd ..

# Install API7's lua-resty-limit-traffic into lualib when the OpenResty
# source (master) does not bundle it. Cwd here is $workdir.
if [ ! -d "$OR_PREFIX"/lualib/resty/limit ]; then
    if [ ! -d lua-resty-limit-traffic-$limit_ver ]; then
        wget "https://github.com/api7/lua-resty-limit-traffic/archive/refs/tags/v$limit_ver.tar.gz" -O "lua-resty-limit-traffic-$limit_ver.tar.gz"
        tar -xzf lua-resty-limit-traffic-$limit_ver.tar.gz
    fi
    echo "installing lua-resty-limit-traffic into $OR_PREFIX/lualib"
    sudo install -d "$OR_PREFIX"/lualib/resty/limit/
    sudo install -m 644 lua-resty-limit-traffic-$limit_ver/lib/resty/limit/*.lua "$OR_PREFIX"/lualib/resty/limit/
fi

cd lua-resty-events-${lua_resty_events_ver} || exit 1
sudo install -d "$OR_PREFIX"/lualib/resty/events/
sudo install -m 664 lualib/resty/events/*.lua "$OR_PREFIX"/lualib/resty/events/
sudo install -d "$OR_PREFIX"/lualib/resty/events/compat/
sudo install -m 644 lualib/resty/events/compat/*.lua "$OR_PREFIX"/lualib/resty/events/compat/
cd ..

# the C module needs its FFI bindings on the runtime's lua_package_path
sudo install -d "$OR_PREFIX"/lualib/resty/
sudo install -m 644 "$ngx_http_ffi_client_dir"/lib/resty/ngx_http_ffi_client.lua \
    "$OR_PREFIX"/lualib/resty/

cd "apisix-nginx-module-${apisix_nginx_module_ver}" || exit 1
sudo OPENRESTY_PREFIX="$OR_PREFIX" make install
cd ..

cd wasm-nginx-module-${wasm_nginx_module_ver} || exit 1
sudo OPENRESTY_PREFIX="$OR_PREFIX" make install
cd ..
