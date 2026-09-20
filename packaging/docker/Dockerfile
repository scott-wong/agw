# Anolis OS 8.10 base for APISIX RPM installation
# Reference: https://github.com/apache/apisix-docker/blob/master/redhat/Dockerfile
# This Dockerfile installs the locally built APISIX RPMs (built by publish-rpm.yml)
# via `dnf localinstall` instead of pulling from apiseven repo.
FROM registry.openanolis.cn/openanolis/anolisos:8.10

# No ARG needed for version when using local RPMs, but keep for label compatibility
ARG APISIX_VERSION

# Dependencies resolve from Anolis 8.10 base repos (AppStream/CRB) — verified
# by the RPM smoke job. EPEL 8 is archived upstream (mirrors 404), so it is
# intentionally NOT enabled here. The redis module is disabled to avoid
# conflicts (mirrors apisix-docker/redhat/Dockerfile behavior).
# Convert the base image's read-only bdb_ro RPM database to sqlite before
# installing the product RPM in the next layer. `dnf -y update` already triggers
# this conversion in the rpm package %posttrans; when the build runs on a
# buildx container driver (double overlayfs) that replacement fails with
# "failed to replace old database with new database!", so fall back to the
# recovery rpm itself prints: replace /var/lib/rpm with the rpmrebuilddb files.
RUN set -x \
    && (dnf module disable -y redis || true) \
    && dnf -y update \
    && rm -f /var/lib/rpm/__db* \
    && if [ ! -f /var/lib/rpm/rpmdb.sqlite ]; then \
         if [ -z "$(ls -d /var/lib/rpmrebuilddb.* 2>/dev/null)" ]; then \
           rpm --rebuilddb || true; \
         fi; \
         if [ ! -f /var/lib/rpm/rpmdb.sqlite ]; then \
           newdb="$(ls -dt /var/lib/rpmrebuilddb.* 2>/dev/null | head -n1)"; \
           test -n "$newdb"; \
           rm -rf /var/lib/rpm/* /var/lib/rpm/.[!.]* 2>/dev/null || true; \
           cp -a "$newdb"/. /var/lib/rpm/; \
         fi; \
       fi \
    && rm -rf /var/lib/rpmrebuilddb.* \
    && test -f /var/lib/rpm/rpmdb.sqlite \
    && rpm -q rpm \
    && dnf clean all \
    && rm -rf /var/cache/dnf /var/cache/yum

# Copy RPMs staged by the workflow (expects rpms/*.rpm at build context root)
# The workflow copies the artifact agw-*.rpm into ./rpms/
COPY rpms/*.rpm /tmp/

# Install APISIX RPMs. Using `localinstall` resolves dependencies from Anolis
# base + EPEL + AppStream. --nogpgcheck is required for locally built packages.
# install_weak_deps=False keeps image lean. Keep yum/dnf cache cleanup to reduce layers.
# 最后清除 Anolis 基础层自带的 Python 打包负载：Trivy/Grype 固定将
# /usr/share/python-wheels/*.whl（pip 9.0.3、setuptools 39.2.0）与
# platform-python-setuptools 的 dist-info 判为 HIGH。最终 RPM 的运行时依赖只有
# openldap/pcre/which/libxml2/libxslt，入口是 /usr/bin/apisix（OpenResty/Lua），
# 不使用 pip/setuptools。dnf 会拒绝卸载受保护的 wheel 包，因此用 rpm -e --nodeps；
# 卸载后 dnf 仍可正常工作（本仓镜像构建阶段已验证）。
RUN set -x \
    && dnf -y localinstall /tmp/*.rpm --nogpgcheck --setopt=install_weak_deps=False \
    && for pkg in python3-pip-wheel python3-setuptools-wheel \
                 platform-python-pip platform-python-setuptools python3-setuptools; do \
         if rpm -q "$pkg" >/dev/null 2>&1; then rpm -e --nodeps "$pkg"; fi; \
       done \
    && test -z "$(find /usr/lib/python3.6/site-packages -maxdepth 1 \
         \( -name 'setuptools*' -o -name 'pip*' \) -print -quit 2>/dev/null)" \
    && test -z "$(find /usr/share/python-wheels -maxdepth 1 -type f -name '*.whl' \
         -print -quit 2>/dev/null)" \
    && dnf clean all \
    && rm -rf /var/cache/dnf /var/cache/yum /tmp/*.rpm \
    && /usr/local/openresty/bin/openresty -V 2>&1 | head -n 5 \
    && /usr/bin/apisix version \
    && apisix help 2>&1 | head -n 20

EXPOSE 9080 9443

STOPSIGNAL SIGQUIT

CMD ["sh", "-c", "/usr/bin/apisix init && /usr/bin/apisix init_etcd && /usr/local/openresty/bin/openresty -p /usr/local/apisix -g 'daemon off;'"]
