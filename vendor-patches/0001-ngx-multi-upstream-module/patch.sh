#!/usr/bin/env bash
# Vendored from api7/ngx_multi_upstream_module（补丁来源：上游 master + PR #21，
# 使 patch.sh 识别 openresty-1.31.1.*，复用 nginx-1.29.2 补丁集与新增
# nginx-1.31.1.patch）。回退条件：上游合入 PR #21 并发布含该修复的正式
# release 后，删除本覆盖、回归纯上游脚本。
# 序号：0001（应用顺序见 scripts/build-apisix-runtime.sh）
set -euo pipefail

err() {
 >&2 echo "$@"
}

usage() {
 err "usage: $1 ThePathOfYourOpenRestySrcDirectory"
 exit 1
}

failed_to_cd() {
 err "failed to cd $1"
 exit 1
}

# Vendored from api7/ngx_multi_upstream_module (upstream master + PR #21,
# which recognizes openresty-1.31.1.* by reusing the nginx-1.29.2 patch set).
# Drop this overlay once the upstream PR merges and a release tag picks it up.

if [[ $# != 1 ]]; then
 usage "$0"
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "$1" == *openresty-1.19.3.* ]]; then
 patch="$script_dir/nginx-1.19.3.patch"
 dir="$1/bundle/nginx-1.19.3"
elif [[ "$1" == *openresty-1.19.9.* ]]; then
 patch="$script_dir/nginx-1.19.9.patch"
 dir="$1/bundle/nginx-1.19.9"
elif [[ "$1" == *openresty-1.21.4.* ]]; then
 patch="$script_dir/nginx-1.21.4.patch"
 dir="$1/bundle/nginx-1.21.4"
elif [[ "$1" == *openresty-1.25.3.* ]]; then
 patch="$script_dir/nginx-1.25.3.patch"
 dir="$1/bundle/nginx-1.25.3"
elif [[ "$1" == *openresty-1.27.1.* ]]; then
 patch="$script_dir/nginx-1.27.1.patch"
 dir="$1/bundle/nginx-1.27.1"
elif [[ "$1" == *openresty-1.29.2.* ]]; then
 patch="$script_dir/nginx-1.29.2.patch"
 dir="$1/bundle/nginx-1.29.2"
elif [[ "$1" == *openresty-1.31.1.* ]]; then
    patch="$script_dir/nginx-1.31.1.patch"
    dir="$1/bundle/nginx-1.31.1"
else
 err "can't detect OpenResty version"
 exit 1
fi

cd "$dir" || failed_to_cd "$dir"
echo "Start to patch $patch to $dir..."
patch -p0 --verbose < "$patch"
