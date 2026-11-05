# syntax=docker/dockerfile:1.7
#
# The upstream etcd image is intentionally shell-less.  This tiny build-only
# image supplies the exact etcdctl from the configured etcd image plus a shell
# for the one-shot Compose init service.  It is never the runtime etcd image.
ARG ETCD_IMAGE=quay.io/coreos/etcd:v3.7.3

FROM ${ETCD_IMAGE} AS etcd

FROM alpine:3.22

COPY --from=etcd /usr/local/bin/etcdctl /usr/local/bin/etcdctl

ENTRYPOINT ["/bin/sh", "-c"]
