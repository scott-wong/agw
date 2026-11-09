#!/usr/bin/env bash
# Final-stage assembly: prune build-only files, initialize APISIX, and grant
# only logs/temp directories to the Nginx worker account.
set -euo pipefail

DISTRO="${1:?用法: prepare-image.sh <openeuler|ubuntu>}"
IMAGE_VARIANT="${2:?缺少镜像变体}"
IMAGE_VERSION="${3:?缺少镜像版本}"
DASHBOARD_SHA="${DASHBOARD_SHA:?缺少 DASHBOARD_SHA}"
DASHBOARD_SOURCE_SHA256="${DASHBOARD_SOURCE_SHA256:?缺少 DASHBOARD_SOURCE_SHA256}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/baseline.env"

export PATH="/usr/local/bin:/usr/local/openresty/bin:/usr/local/openresty/luajit/bin:$PATH"

ln -sfn /usr/local/openresty/bin/openresty /usr/local/bin/openresty
ln -sfn /usr/local/openresty/bin/resty /usr/local/bin/resty

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

# Keep this cleanup idempotent for locally built images. The builder already
# prunes these paths so the final COPY does not carry their bytes in a layer.
rm -rf \
  /usr/local/openresty/include \
  /usr/local/openresty/luajit/include \
  /usr/local/openresty/pcre/include \
  /usr/local/openresty/zlib/include \
  /usr/local/openresty/tongsuo/include \
  /usr/local/openresty/pod
find /usr/local/openresty -type f -name '*.a' -delete
find /usr/local/openresty -type d -name pkgconfig -prune -exec rm -rf {} +
test ! -e /usr/local/openresty/include
test ! -e /usr/local/openresty/pod
test -L /usr/local/bin/openresty
test -L /usr/local/bin/resty

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
grep -Fq 'location ^~ /ui/docs/' /usr/local/apisix/conf/nginx.conf
test -f /usr/local/apisix/ui/index.html
grep -Fq '<title>AGW Dashboard</title>' /usr/local/apisix/ui/index.html
test -n "$(find /usr/local/apisix/ui/assets -type f -name '*.js' -print -quit)"
test -f /usr/local/apisix/ui/docs/index.html
grep -Fq '<title>AGW 文档</title>' /usr/local/apisix/ui/docs/index.html
grep -Fq 'relativePath: true' /usr/local/apisix/ui/docs/index.html
test -f /usr/local/apisix/ui/docs/zh/latest/README.md
test -f /usr/local/apisix/ui/docs/en/latest/README.md
test -f /usr/local/apisix/ui/docs/zh/latest/_sidebar.md
test -f /usr/local/apisix/ui/docs/en/latest/_sidebar.md
grep -Fq '](/zh/latest/' /usr/local/apisix/ui/docs/zh/latest/_sidebar.md
grep -Fq '](/en/latest/' /usr/local/apisix/ui/docs/en/latest/_sidebar.md
grep -Fq 'src="/ui/docs/assets/images/' \
  /usr/local/apisix/ui/docs/zh/latest/architecture-design/apisix.md
! grep -R -I -q -E '\]\(/ui/docs/(zh|en)/latest/' /usr/local/apisix/ui/docs
! grep -R -I -q -E "href=[\"']/ui/docs/(zh|en)/latest/" /usr/local/apisix/ui/docs
test ! -e /usr/local/apisix/ui/docs/assets/images/apisix.png
test ! -e /usr/local/apisix/ui/docs/assets/images/apisix-seed.svg
test ! -e /usr/local/apisix/ui/docs/assets/images/apache.png
! grep -R -I -q -F 'https://apisix.apache.org/docs/' /usr/local/apisix/ui
! grep -R -I -q -F 'https://github.com/apache/apisix-dashboard/issues/1407' \
  /usr/local/apisix/ui
! grep -R -I -q -F '帮助我们进行翻译' /usr/local/apisix/ui
! grep -R -I -q -F 'Apache APISIX Dashboard' /usr/local/apisix/ui
! grep -R -I -q -F 'APISIX Dashboard' /usr/local/apisix/ui
! grep -R -I -q -F 'Help Us Translate' /usr/local/apisix/ui
test ! -e /usr/local/apisix/ui/assets/apisix-logo.svg
test -f /usr/local/share/agw/dashboard-source.json
grep -q 'local ver_header = "agw"' /usr/local/apisix/apisix/init.lua
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
  echo "dashboardSource=https://github.com/apache/apisix-dashboard"
  echo "dashboardCommit=$DASHBOARD_SHA"
  echo "dashboardSourceSha256=$DASHBOARD_SOURCE_SHA256"
  echo "runtimeUser=$RUNTIME_USER (inherited)"
  echo "nginxWorkerUser=$NGINX_WORKER_USER"
  echo "tongsuoCveParity=$TONGSUO_CVE_PARITY"
} > /usr/local/share/agw/image-provenance.txt

cat /usr/local/share/agw/image-provenance.txt
