# Anolis OS 8.10 加固基础层 + APISIX RPM 安装
# 基础层：ghcr.io/scott-wong/anolis-secure（自建、每周重建、默认非 root 用户
# appuser:10001）。`:latest` 会随上游重建前进，因此 digest 固定登记在
# scripts/baseline.env 的 BASE_IMAGE_DIGEST，由 `make fetch` 强制校验；决策见
# docs/adr/0005-delivery-image-hardened-base.md。
# 安装方式：`dnf localinstall` 本仓构建的最终 RPM（不依赖上游制品仓库）。
# Reference: https://github.com/apache/apisix-docker/blob/master/redhat/Dockerfile
FROM ghcr.io/scott-wong/anolis-secure:latest

# 安装 RPM 必须 root：基础层默认 USER appuser，这里显式提权，末尾再切回 10001:10001。
USER root

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
    && rm -rf /var/cache/dnf /var/cache/yum /tmp/*.rpm

# 运行期用户是基础层自带的 appuser(10001)。RPM 装出来的 conf/ 与 logs/ 属 root:root，
# 而 APISIX 必须在运行期写它们（`apisix init` 生成 conf/nginx.conf；nginx 写 error.log /
# pid / *_temp）。这里显式授权，然后在**切换后的运行期用户**下真跑一次 init —— 权限不对
# 就在构建期失败，不会留到运行期。
# nginx 的 5 个 temp 路径沿用编译默认值（相对 prefix），APISIX 模板未显式改写，
# 因此按 prefix=/usr/local/apisix 预建并授权，避免运行期去写 /usr/local/apisix 根目录。
RUN set -x \
    && install -d -o 10001 -g 10001 -m 0755 /usr/local/apisix/logs \
    && install -d -o 10001 -g 10001 -m 0750 \
         /usr/local/apisix/client_body_temp /usr/local/apisix/proxy_temp \
         /usr/local/apisix/fastcgi_temp /usr/local/apisix/uwsgi_temp \
         /usr/local/apisix/scgi_temp \
    && chown -R 10001:10001 /usr/local/apisix/conf /usr/local/apisix/logs

USER 10001:10001

RUN set -x \
    && /usr/bin/apisix init \
    && test -f /usr/local/apisix/conf/nginx.conf \
    && test -w /usr/local/apisix/conf \
    && test -w /usr/local/apisix/logs \
    && /usr/local/openresty/bin/openresty -V 2>&1 | sed -n '1,5p' \
    && /usr/bin/apisix version \
    && apisix help 2>&1 | sed -n '1,20p'

EXPOSE 9080 9443

STOPSIGNAL SIGQUIT

CMD ["sh", "-c", "/usr/bin/apisix init && /usr/bin/apisix init_etcd && /usr/local/openresty/bin/openresty -p /usr/local/apisix -g 'daemon off;'"]
