# AGW build entry points. VERSION is the version source of truth; source pins
# live in scripts/baseline.env and are verified before any image build.
SHELL := /bin/bash

FULL_VERSION := $(shell tr -d ' \n' < VERSION)
UPSTREAM_VERSION := $(shell cut -d- -f1 < VERSION)
VARIANT ?= openeuler
IMAGE ?= agw:$(FULL_VERSION)-$(VARIANT)
PLATFORM ?= linux/amd64

.PHONY: help fetch evidence build-image build-images verify-image verify-images \
        verify-etcd verify static clean

help:
	@echo "AGW $(FULL_VERSION)"
	@echo "  fetch         校验全部基线并下载/校验源码归档到 distfiles/"
	@echo "  evidence      根据版本、基线、补丁和模块刷新 evidence/"
	@echo "  build-image   VARIANT=openeuler|ubuntu IMAGE=<ref> 构建单个最终镜像"
	@echo "  build-images  顺序构建两个最终镜像"
	@echo "  verify-image  IMAGE=<ref> VARIANT=<variant> 镜像冒烟（含 Server header/国密）"
	@echo "  verify-etcd   IMAGE=<ref> 外置 etcd + Admin API 冒烟"
	@echo "  verify        静态检查（shell/Lua patch/workflow YAML）"
	@echo "  clean         清理 build/ distfiles/ 与本地镜像输入"

fetch:
	bash scripts/verify-baseline.sh

evidence:
	python3 scripts/gen-evidence.py

build-image:
	test -d distfiles
	test -f distfiles/apisix-$(UPSTREAM_VERSION).tar.gz
	docker build \
		--platform $(PLATFORM) \
		--target $(VARIANT)-final \
		--build-arg AGW_VERSION=$(FULL_VERSION) \
		-t $(IMAGE) \
		-f packaging/docker/Dockerfile .

build-images:
	$(MAKE) build-image VARIANT=openeuler IMAGE=agw:$(FULL_VERSION)-openeuler
	$(MAKE) build-image VARIANT=ubuntu IMAGE=agw:$(FULL_VERSION)-ubuntu

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

static: verify

clean:
	rm -rf build distfiles out rpms
