#!/usr/bin/env bash
# Final-stage assembly: prune build-only files, initialize APISIX, and grant
# only logs/temp directories to the Nginx worker account.
set -euo pipefail

DISTRO="${1:?用法: prepare-image.sh <openeuler|ubuntu>}"
IMAGE_VARIANT="${2:?缺少镜像变体}"
IMAGE_VERSION="${3:?缺少镜像版本}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/baseline.env"

export PATH="/usr/local/bin:/usr/local/openresty/bin:/usr/local/openresty/luajit/bin:$PATH"
export LD_LIBRARY_PATH="/usr/local/openresty/tongsuo/lib:/usr/local/openresty/pcre/lib:/usr/local/openresty/zlib/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

case "$DISTRO" in
  openeuler)
    grep -qi '^ID="openEuler"' /etc/os-release
    grep -q '24.03' /etc/os-release
    BASE_REF="$OPENEULER_BASE_REF"
    ;;
  ubuntu)
    grep -qi '^ID=ubuntu' /etc/os-release
    grep -q '24.04' /etc/os-release
    BASE_REF="$UBUNTU_BASE_REF"
    ;;
  *)
    echo "错误: 不支持的目标发行版 $DISTRO" >&2
    exit 1
    ;;
esac

# The final stages are independent of the builder and therefore contain no
# compiler. Remove headers and static archives that OpenResty's install target
# copies by default but which are not needed at runtime.
rm -rf \
  /usr/local/openresty/include \
  /usr/local/openresty/luajit/include \
  /usr/local/openresty/pcre/include \
  /usr/local/openresty/zlib/include \
  /usr/local/openresty/tongsuo/include
find /usr/local/openresty -type f -name '*.a' -delete
find /usr/local/openresty -type d -name pkgconfig -prune -exec rm -rf {} +

echo "[prepare] checking native runtime dependencies"
while IFS= read -r binary; do
  magic="$(od -An -tx1 -N4 "$binary" 2>/dev/null | tr -d ' \n')"
  [ "$magic" = "7f454c46" ] || continue
  if ldd "$binary" 2>/dev/null | grep -q 'not found'; then
    echo "ERROR: $binary 存在未解析动态库" >&2
    ldd "$binary" >&2 || true
    exit 1
  fi
done < <(find /usr/local/openresty /usr/local/apisix -type f \
  \( -name '*.so' -o -name '*.so.*' -o -perm -111 \) -print)

/usr/local/bin/apisix init
/usr/local/openresty/bin/openresty -t -p /usr/local/apisix -c conf/nginx.conf

test -f /usr/local/apisix/conf/nginx.conf
grep -q 'local ver_header = "agw"' /usr/local/apisix/apisix/cli/config.lua
grep -q '^    "gm",$' /usr/local/apisix/apisix/cli/config.lua

install -d -o 65534 -g 65534 -m 0750 /usr/local/apisix/logs
for dir in client_body_temp proxy_temp fastcgi_temp uwsgi_temp scgi_temp; do
  install -d -o 65534 -g 65534 -m 0750 "/usr/local/apisix/$dir"
done

install -d /usr/local/share/agw
cp "$ROOT/LICENSE" /usr/local/share/agw/LICENSE
{
  echo "product=AGW"
  echo "version=$IMAGE_VERSION"
  echo "upstream=Apache APISIX $APISIX_TAG"
  echo "variant=$IMAGE_VARIANT"
  echo "baseOs=$DISTRO"
  echo "baseReference=$BASE_REF"
  echo "runtimeUser=$RUNTIME_USER (inherited)"
  echo "nginxWorkerUser=$NGINX_WORKER_USER"
  echo "tongsuoCveParity=$TONGSUO_CVE_PARITY"
} > /usr/local/share/agw/image-provenance.txt

cat /usr/local/share/agw/image-provenance.txt
