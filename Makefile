# AGW build entry points. VERSION is the version source of truth; source pins
# live in scripts/baseline.env and are verified before any image build.
SHELL := /bin/bash

FULL_VERSION := $(shell tr -d ' \n' < VERSION)
UPSTREAM_VERSION := $(shell cut -d- -f1 < VERSION)
VARIANT ?= openeuler
IMAGE ?= agw:$(FULL_VERSION)-$(VARIANT)
PLATFORM ?= linux/amd64
DASHBOARD_SHA ?=
DASHBOARD_SOURCE_SHA256 ?=
NPM_REGISTRY ?=

.PHONY: help fetch evidence build-image build-images verify-image verify-images \
        verify-etcd verify static clean dashboard-fetch

help:
	@echo "AGW $(FULL_VERSION)"
	@echo "  fetch         校验全部基线并下载/校验源码归档到 distfiles/"
	@echo "  dashboard-fetch 解析并下载当前 apache/apisix-dashboard master"
	@echo "  evidence      根据版本、基线、补丁和模块刷新 evidence/"
	@echo "  build-image   VARIANT=openeuler|ubuntu IMAGE=<ref> 构建单个最终镜像"
	@echo "  build-images  顺序构建两个最终镜像"
	@echo "  verify-image  IMAGE=<ref> VARIANT=<variant> 镜像冒烟（含 Server header/国密）"
	@echo "  verify-etcd   IMAGE=<ref> 外置 etcd + Admin API 冒烟"
	@echo "  verify        静态检查（shell/Lua patch/workflow YAML/CHANGELOG）"
	@echo "  clean         清理 build/ distfiles/ 与本地镜像输入"

fetch:
	bash scripts/verify-baseline.sh

evidence:
	python3 scripts/gen-evidence.py

build-image:
	test -d distfiles
	test -f distfiles/apisix-$(UPSTREAM_VERSION).tar.gz
	@set -euo pipefail; \
		sha="$(DASHBOARD_SHA)"; \
		if [ -z "$$sha" ]; then sha="$$(bash scripts/dashboard-source.sh resolve)"; fi; \
		source_sha="$(DASHBOARD_SOURCE_SHA256)"; \
		if [ -z "$$source_sha" ]; then source_sha="$$(bash scripts/dashboard-source.sh fetch "$$sha")"; fi; \
		docker build \
			--platform $(PLATFORM) \
			--target $(VARIANT)-final \
			--build-arg AGW_VERSION=$(FULL_VERSION) \
			--build-arg DASHBOARD_SHA="$$sha" \
			--build-arg DASHBOARD_SOURCE_SHA256="$$source_sha" \
			--build-arg NPM_REGISTRY="$(NPM_REGISTRY)" \
			-t $(IMAGE) \
			-f packaging/docker/Dockerfile .

build-images:
	@set -euo pipefail; \
		sha="$(DASHBOARD_SHA)"; \
		if [ -z "$$sha" ]; then sha="$$(bash scripts/dashboard-source.sh resolve)"; fi; \
		source_sha="$(DASHBOARD_SOURCE_SHA256)"; \
		if [ -z "$$source_sha" ]; then source_sha="$$(bash scripts/dashboard-source.sh fetch "$$sha")"; fi; \
		$(MAKE) build-image VARIANT=openeuler IMAGE=agw:$(FULL_VERSION)-openeuler \
			DASHBOARD_SHA="$$sha" DASHBOARD_SOURCE_SHA256="$$source_sha"; \
		$(MAKE) build-image VARIANT=ubuntu IMAGE=agw:$(FULL_VERSION)-ubuntu \
			DASHBOARD_SHA="$$sha" DASHBOARD_SOURCE_SHA256="$$source_sha"

verify-image:
	test -n "$(IMAGE)"
	bash scripts/smoke-docker.sh "$(IMAGE)" "$(VARIANT)" "$(FULL_VERSION)"

verify-images:
	$(MAKE) verify-image VARIANT=openeuler IMAGE=agw:$(FULL_VERSION)-openeuler
	$(MAKE) verify-image VARIANT=ubuntu IMAGE=agw:$(FULL_VERSION)-ubuntu

verify-etcd:
	test -n "$(IMAGE)"
	bash scripts/smoke-etcd.sh "$(IMAGE)"

verify:
	bash scripts/static-checks.sh

dashboard-fetch:
	@set -euo pipefail; \
		sha="$(DASHBOARD_SHA)"; \
		if [ -z "$$sha" ]; then sha="$$(bash scripts/dashboard-source.sh resolve)"; fi; \
		source_sha="$$(bash scripts/dashboard-source.sh fetch "$$sha")"; \
		printf 'dashboard_sha=%s\ndashboard_source_sha256=%s\n' "$$sha" "$$source_sha"

static: verify

clean:
	rm -rf build distfiles out rpms
