#!/usr/bin/env bash
set -euo pipefail
set -x
mkdir /output
dist=$(cat /tmp/dist)
codename=$(cat /tmp/codename)

# Determine the name of artifact
# The defaut is apisix-runtime
artifact="apisix-runtime"
if [ "$ARTIFACT" != "0" ]; then
    artifact=${ARTIFACT}
fi

ARCH=${ARCH:-`(uname -m | tr '[:upper:]' '[:lower:]')`}

fpm -f -s dir -t "$PACKAGE_TYPE" \
    --"$PACKAGE_TYPE"-dist "$dist" \
    -n "$artifact" \
    -a "$(uname -i)" \
    -v "$RUNTIME_VERSION" \
    --iteration "$ITERATION" \
    --post-install post-install-apisix-runtime.sh \
    --description "APISIX's OpenResty distribution." \
    --license "ASL 2.0" \
    -C /tmp/build/output \
    -p /output \
    --url 'http://apisix.apache.org/' \
    --conflicts openresty \
    --config-files usr/lib/systemd/system/openresty.service \
    --prefix=/usr/local

PACKAGE_ARCH="amd64"
if [[ $ARCH == "arm64" ]] || [[ $ARCH == "aarch64" ]]; then
    PACKAGE_ARCH="arm64"
fi

