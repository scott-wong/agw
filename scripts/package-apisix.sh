#!/usr/bin/env bash
set -euo pipefail
set -x
mkdir /output
dist=$(cat /tmp/dist)

ARCH=${ARCH:-`(uname -m | tr '[:upper:]' '[:lower:]')`}

# Determine the dependencies
# Runtime libraries bundled under /usr/local/openresty (OpenSSL, libyaml) must
# NOT appear in the package's requires: libyaml-devel is a build-time leftover
# and uninstallable on a bare target host (run #3 failed on
# `nothing provides libyaml-devel`). Only true runtime deps stay listed.
dep_ldap="openldap"
dep_pcre="pcre"
dep_which="which"
# saml-auth plugin's saml.so links libxml2 and libxslt
dep_libxml2="libxml2"
dep_libxslt="libxslt"

# Determine the name of artifact
# The defaut is apisix
artifact="apisix"
if [ "$ARTIFACT" != "0" ]
then
	artifact=${ARTIFACT}
fi

fpm -f -s dir -t "$PACKAGE_TYPE" \
        --"$PACKAGE_TYPE"-dist "$dist" \
        -n "$artifact" \
        -a "$(uname -i)" \
        -v "$PACKAGE_VERSION" \
        --iteration "$ITERATION" \
        -d "$dep_ldap" \
        -d "$dep_pcre" \
        -d "$dep_which" \
        -d "$dep_libxml2" \
        -d "$dep_libxslt" \
        --post-install post-install-apisix-runtime.sh \
        --description 'Apache APISIX is a distributed gateway for APIs and Microservices, focused on high performance and reliability.' \
        --license "ASL 2.0" \
        -C /tmp/build/output/apisix \
        -p /output \
        --url 'http://apisix.apache.org/' \
        --config-files usr/lib/systemd/system/apisix.service \
        --config-files usr/lib/systemd/system/openresty.service \
        --config-files usr/local/apisix/conf/config.yaml

