#!/usr/bin/env bash
set -euo pipefail

export PATH="/usr/local/bin:/usr/local/openresty/bin:/usr/local/openresty/luajit/bin:$PATH"

/usr/local/bin/apisix init
/usr/local/bin/apisix init_etcd

exec /usr/local/openresty/bin/openresty \
  -p /usr/local/apisix \
  -g 'daemon off;'
