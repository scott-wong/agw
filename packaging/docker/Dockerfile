# syntax=docker/dockerfile:1.7
#
# Two final images, built independently inside their target distributions:
#   openeuler-final -> quay.io/openeuler/openeuler:24.03-lts-sp4
#   ubuntu-final    -> ubuntu:24.04
#
# No runtime tree is copied between distributions. The final stages inherit
# the base image's default user (root) and do not add a USER directive.

ARG OPENEULER_BASE=quay.io/openeuler/openeuler:24.03-lts-sp4@sha256:17c15554be2a5bc46023acb6e04d609d77642b8c20e236e88deb18e41ae4558e
ARG UBUNTU_BASE=ubuntu:24.04@sha256:fe81560990fae86dc4743202b2cb4d3df98d0bcf949173cecef15ce1127ef852
ARG NODE_BASE=node:22-alpine@sha256:0e1754758c2df4cfa3e68d59e2e1b7374bb7fd9ea6328eaaacf15cc934af8202

# ---------------------------------------------------------------------------
# Documentation builder
# ---------------------------------------------------------------------------
FROM ${NODE_BASE} AS docs-builder

ARG NPM_REGISTRY=

WORKDIR /opt/agw
RUN apk add --no-cache bash ca-certificates python3 tar
COPY docs-viewer/ /opt/agw/docs-viewer/
COPY scripts/baseline.env scripts/build-apisix-docs.py scripts/build-apisix-docs.sh /opt/agw/scripts/
COPY distfiles/apisix-*.tar.gz /opt/agw/distfiles/
RUN if [ -n "$NPM_REGISTRY" ]; then \
      npm config set registry "$NPM_REGISTRY"; \
    fi \
    && cd /opt/agw/docs-viewer \
    && npm ci --ignore-scripts --no-audit --no-fund \
    && cd /opt/agw \
    && bash scripts/build-apisix-docs.sh

# ---------------------------------------------------------------------------
# Admin UI builder
# ---------------------------------------------------------------------------
FROM ${NODE_BASE} AS dashboard-builder

ARG DASHBOARD_SHA
ARG DASHBOARD_SOURCE_SHA256
ARG NPM_REGISTRY=

WORKDIR /opt/agw
RUN apk add --no-cache bash ca-certificates coreutils git patch python3

COPY scripts/baseline.env scripts/build-apisix-dashboard.sh /opt/agw/scripts/
COPY distfiles/apisix-dashboard-*.tar.gz distfiles/apisix-dashboard-*.json /opt/agw/distfiles/
COPY patches/apisix-dashboard/ /opt/agw/patches/apisix-dashboard/

RUN --mount=type=cache,target=/root/.cache/node/corepack \
    --mount=type=cache,target=/root/.local/share/pnpm/store \
    test -n "$DASHBOARD_SHA" \
    && test -n "$DASHBOARD_SOURCE_SHA256" \
    && DISTFILES=/opt/agw/distfiles \
       PATCH_DIR=/opt/agw/patches/apisix-dashboard \
       OUTPUT=/opt/agw/ui-dist \
       PROVENANCE_OUTPUT=/opt/agw/dashboard-provenance.json \
       NPM_REGISTRY="$NPM_REGISTRY" \
       bash /opt/agw/scripts/build-apisix-dashboard.sh \
    && rm -rf /tmp/agw-dashboard-build

# ---------------------------------------------------------------------------
# openEuler builder
# ---------------------------------------------------------------------------
FROM ${OPENEULER_BASE} AS openeuler-builder

ENV DISTRO=openeuler
WORKDIR /opt/agw

COPY scripts/configure-openeuler-repo.sh scripts/install-build-deps.sh /opt/agw/scripts/
RUN bash scripts/install-build-deps.sh openeuler

COPY scripts/baseline.env scripts/build-apisix-runtime.sh /opt/agw/scripts/
COPY packaging/openssl/openssl.cnf /opt/agw/packaging/openssl/openssl.cnf
COPY distfiles/ /opt/agw/distfiles/
RUN DISTFILES=/opt/agw/distfiles \
       OPENSSL_CONF_PATH=/opt/agw/packaging/openssl/openssl.cnf \
       bash scripts/build-apisix-runtime.sh

COPY scripts/install-luarocks.sh /opt/agw/scripts/
RUN bash scripts/install-luarocks.sh

COPY scripts/install-apisix.sh /opt/agw/scripts/
COPY patches/ /opt/agw/patches/
RUN DISTFILES=/opt/agw/distfiles bash scripts/install-apisix.sh \
    && rm -rf /tmp/agw-runtime-build /tmp/agw-luarocks-build /tmp/agw-apisix-build

# ---------------------------------------------------------------------------
# Ubuntu builder
# ---------------------------------------------------------------------------
FROM ${UBUNTU_BASE} AS ubuntu-builder

ENV DISTRO=ubuntu
WORKDIR /opt/agw

COPY scripts/install-build-deps.sh /opt/agw/scripts/
RUN bash scripts/install-build-deps.sh ubuntu

COPY scripts/baseline.env scripts/build-apisix-runtime.sh /opt/agw/scripts/
COPY packaging/openssl/openssl.cnf /opt/agw/packaging/openssl/openssl.cnf
COPY distfiles/ /opt/agw/distfiles/
RUN DISTFILES=/opt/agw/distfiles \
       OPENSSL_CONF_PATH=/opt/agw/packaging/openssl/openssl.cnf \
       bash scripts/build-apisix-runtime.sh

COPY scripts/install-luarocks.sh /opt/agw/scripts/
RUN bash scripts/install-luarocks.sh

COPY scripts/install-apisix.sh /opt/agw/scripts/
COPY patches/ /opt/agw/patches/
RUN DISTFILES=/opt/agw/distfiles bash scripts/install-apisix.sh \
    && rm -rf /tmp/agw-runtime-build /tmp/agw-luarocks-build /tmp/agw-apisix-build

# ---------------------------------------------------------------------------
# openEuler final image
# ---------------------------------------------------------------------------
FROM ${OPENEULER_BASE} AS openeuler-final

ARG AGW_VERSION=3.19.0-agw.13
ARG DASHBOARD_SHA
ARG DASHBOARD_SOURCE_SHA256

LABEL org.opencontainers.image.title="AGW" \
      org.opencontainers.image.description="AGW API gateway, based on Apache APISIX" \
      org.opencontainers.image.version="${AGW_VERSION}" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.source="https://github.com/scott-wong/agw" \
      org.opencontainers.image.base.name="quay.io/openeuler/openeuler:24.03-lts-sp4" \
      org.opencontainers.image.base.digest="sha256:17c15554be2a5bc46023acb6e04d609d77642b8c20e236e88deb18e41ae4558e" \
      org.opencontainers.image.vendor="AGW" \
      io.agw.variant="openeuler" \
      io.agw.dashboard.source.commit="${DASHBOARD_SHA}" \
      io.agw.dashboard.source.sha256="${DASHBOARD_SOURCE_SHA256}" \
      io.agw.runtime-user="root (inherited)" \
      io.agw.nginx-worker-user="nobody"

ENV PATH=/usr/local/bin:/usr/local/openresty/bin:/usr/local/openresty/luajit/bin:$PATH \
    APISIX_HOME=/usr/local/apisix

WORKDIR /usr/local/apisix
COPY scripts/ /opt/agw/scripts/
COPY LICENSE /opt/agw/LICENSE
RUN bash /opt/agw/scripts/install-runtime-deps.sh openeuler

COPY --from=openeuler-builder /usr/local/openresty /usr/local/openresty
COPY --from=openeuler-builder /usr/local/apisix /usr/local/apisix
COPY --from=openeuler-builder /usr/local/bin/apisix /usr/local/bin/apisix
COPY --from=openeuler-builder /usr/local/share/agw /usr/local/share/agw
COPY --from=dashboard-builder /opt/agw/ui-dist /usr/local/apisix/ui
COPY --from=docs-builder /opt/agw/docs-dist /usr/local/apisix/ui/docs
COPY --from=dashboard-builder /opt/agw/dashboard-provenance.json /usr/local/share/agw/dashboard-source.json
COPY packaging/docker/agw-entrypoint.sh /usr/local/bin/agw-entrypoint

RUN chmod 0755 /usr/local/bin/agw-entrypoint \
    && DASHBOARD_SHA="$DASHBOARD_SHA" \
       DASHBOARD_SOURCE_SHA256="$DASHBOARD_SOURCE_SHA256" \
       bash /opt/agw/scripts/prepare-image.sh openeuler openeuler "$AGW_VERSION" \
    && rm -rf /opt/agw

EXPOSE 9080 9180 9443
STOPSIGNAL SIGQUIT
ENTRYPOINT ["/usr/local/bin/agw-entrypoint"]

# ---------------------------------------------------------------------------
# Ubuntu final image
# ---------------------------------------------------------------------------
FROM ${UBUNTU_BASE} AS ubuntu-final

ARG AGW_VERSION=3.19.0-agw.13
ARG DASHBOARD_SHA
ARG DASHBOARD_SOURCE_SHA256

LABEL org.opencontainers.image.title="AGW" \
      org.opencontainers.image.description="AGW API gateway, based on Apache APISIX" \
      org.opencontainers.image.version="${AGW_VERSION}" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.source="https://github.com/scott-wong/agw" \
      org.opencontainers.image.base.name="ubuntu:24.04" \
      org.opencontainers.image.base.digest="sha256:fe81560990fae86dc4743202b2cb4d3df98d0bcf949173cecef15ce1127ef852" \
      org.opencontainers.image.vendor="AGW" \
      io.agw.variant="ubuntu" \
      io.agw.dashboard.source.commit="${DASHBOARD_SHA}" \
      io.agw.dashboard.source.sha256="${DASHBOARD_SOURCE_SHA256}" \
      io.agw.runtime-user="root (inherited)" \
      io.agw.nginx-worker-user="nobody"

ENV PATH=/usr/local/bin:/usr/local/openresty/bin:/usr/local/openresty/luajit/bin:$PATH \
    APISIX_HOME=/usr/local/apisix

WORKDIR /usr/local/apisix
COPY scripts/ /opt/agw/scripts/
COPY LICENSE /opt/agw/LICENSE
RUN bash /opt/agw/scripts/install-runtime-deps.sh ubuntu

COPY --from=ubuntu-builder /usr/local/openresty /usr/local/openresty
COPY --from=ubuntu-builder /usr/local/apisix /usr/local/apisix
COPY --from=ubuntu-builder /usr/local/bin/apisix /usr/local/bin/apisix
COPY --from=ubuntu-builder /usr/local/share/agw /usr/local/share/agw
COPY --from=dashboard-builder /opt/agw/ui-dist /usr/local/apisix/ui
COPY --from=docs-builder /opt/agw/docs-dist /usr/local/apisix/ui/docs
COPY --from=dashboard-builder /opt/agw/dashboard-provenance.json /usr/local/share/agw/dashboard-source.json
COPY packaging/docker/agw-entrypoint.sh /usr/local/bin/agw-entrypoint

RUN chmod 0755 /usr/local/bin/agw-entrypoint \
    && DASHBOARD_SHA="$DASHBOARD_SHA" \
       DASHBOARD_SOURCE_SHA256="$DASHBOARD_SOURCE_SHA256" \
       bash /opt/agw/scripts/prepare-image.sh ubuntu ubuntu "$AGW_VERSION" \
    && rm -rf /opt/agw

EXPOSE 9080 9180 9443
STOPSIGNAL SIGQUIT
ENTRYPOINT ["/usr/local/bin/agw-entrypoint"]
