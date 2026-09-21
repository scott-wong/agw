# AGW 构建入口（product-repo-contract 公共动词）
# 版本事实源：VERSION（3.18.0-agw.2）；基线事实源：scripts/baseline.env
SHELL := /bin/bash

UPSTREAM_VERSION := $(shell cut -d- -f1 < VERSION)
AGW_RELEASE := $(shell cut -d- -f2 < VERSION)
FULL_VERSION := $(shell cat VERSION | tr -d ' \n')
APISIX_TAG := $(shell grep '^APISIX_TAG=' scripts/baseline.env | cut -d= -f2)
IMAGE_LOCAL := agw:$(FULL_VERSION)
ANOLIS := registry.openanolis.cn/openanolis/anolisos:8.10

# 两段 RPM 中间镜像命名空间（不进交付物）
BUILD_NS := agw-build

.PHONY: help fetch build-rpm build-docker verify verify-docker release-assets clean \
        clean-build-images build-fpm build-runtime-image package-runtime build-apisix-image package-apisix

help:
	@echo "AGW $(FULL_VERSION) — 公共动词："
	@echo "  fetch          基线漂移校验（模块 tag commit + OpenResty/Tongsuo + tarball SHA256）并取 APISIX 快照至 build/src"
	@echo "  build-rpm      运行时镜像 -> agw RPM（out/ 只保留最终 RPM）"
	@echo "  build-docker   备料 rpms/ 并组装交付镜像 $(IMAGE_LOCAL)"
	@echo "  verify         Anolis 8.10 容器内 RPM 安装冒烟（Tongsuo/国密 + openresty -V + apisix version + 限流 lua）"
	@echo "  verify-docker  镜像冒烟（apisix init + standalone Server: agw 断言 + SM2/NTLS 握手）"
	@echo "  release-assets build-rpm + 备料 rpms/（只收敛最终 agw RPM）"
	@echo "  clean          清理构建工作区"

# ---- fetch：基线校验 + 上游快照 ----
.PHONY: fetch
fetch:
	bash scripts/verify-baseline.sh
	rm -rf build/src
	git clone --depth 1 -b $(APISIX_TAG) https://github.com/apache/apisix.git build/src
	git -C build/src rev-parse HEAD

# ---- 两段 RPM 链 ----
.PHONY: build-fpm
build-fpm:
	docker build -t api7/fpm - < packaging/fpm/Dockerfile

.PHONY: build-runtime-image
build-runtime-image: build-fpm
	docker build -t $(BUILD_NS)/runtime:0.0.0 \
		--build-arg RUNTIME_VERSION=0.0.0 \
		--build-arg OPENRESTY_SOURCE=release \
		--build-arg IMAGE_BASE=rockylinux \
		--build-arg IMAGE_TAG=8 \
		-f packaging/rpm/Dockerfile.runtime .

.PHONY: package-runtime
package-runtime: build-runtime-image
	docker build -t $(BUILD_NS)/package-runtime:0.0.0 \
		--build-arg RUNTIME_IMAGE=$(BUILD_NS)/runtime:0.0.0 \
		--build-arg PACKAGE_TYPE=rpm \
		--build-arg PACKAGE_VERSION=0.0.0 \
		--build-arg ITERATION=0 \
		--build-arg RUNTIME_VERSION=0.0.0 \
		--build-arg ARTIFACT=apisix-runtime \
		-f packaging/rpm/Dockerfile.package-runtime .
	docker run -d --rm --name agw-output --net="host" $(BUILD_NS)/package-runtime:0.0.0
	rm -rf output-runtime && docker cp agw-output:/output ./output-runtime
	docker stop agw-output

.PHONY: build-apisix-image
build-apisix-image: build-runtime-image
	rm -rf ./apisix
	git clone --depth 1 -b $(UPSTREAM_VERSION) https://github.com/apache/apisix.git ./apisix
	docker build -t $(BUILD_NS)/apisix:$(UPSTREAM_VERSION) \
		--build-arg RUNTIME_IMAGE=$(BUILD_NS)/runtime:0.0.0 \
		--build-arg PACKAGE_TYPE=rpm \
		--build-arg RUNTIME_VERSION=0.0.0 \
		--build-arg checkout_v=$(UPSTREAM_VERSION) \
		--build-arg IMAGE_BASE=rockylinux \
		--build-arg IMAGE_TAG=8 \
		--build-arg CODE_PATH=./apisix \
		-f packaging/rpm/Dockerfile.apisix .

.PHONY: package-apisix
package-apisix: build-apisix-image
	docker build -t $(BUILD_NS)/package-apisix:$(UPSTREAM_VERSION) \
		--build-arg APISIX_IMAGE=$(BUILD_NS)/apisix:$(UPSTREAM_VERSION) \
		--build-arg VERSION=$(UPSTREAM_VERSION) \
		--build-arg PACKAGE_TYPE=rpm \
		--build-arg PACKAGE_VERSION=$(UPSTREAM_VERSION) \
		--build-arg ITERATION=$(AGW_RELEASE) \
		--build-arg OPENRESTY=apisix-runtime \
		--build-arg RUNTIME_VERSION=0.0.0 \
		--build-arg ARTIFACT=agw \
		-f packaging/rpm/Dockerfile.package-apisix .
	docker run -d --rm --name agw-output --net="host" $(BUILD_NS)/package-apisix:$(UPSTREAM_VERSION)
	rm -rf output-apisix && docker cp agw-output:/output ./output-apisix
	docker stop agw-output

.PHONY: build-rpm
build-rpm: package-apisix
	rm -rf out
	mkdir -p out
	mv output-apisix/*.rpm out/
	rm -rf output-apisix
	test -n "$$(find out -maxdepth 1 -type f -name 'agw-*.rpm' -print -quit)"
	test -z "$$(find out -maxdepth 1 -type f \( -name 'apisix-runtime-*.rpm' -o -name 'apisix-*.rpm' \) -print -quit)"
	ls -lh out/

# ---- 发布物备料 ----
.PHONY: release-assets
release-assets: build-rpm
	rm -rf rpms
	mkdir -p rpms
	cp out/agw-*.rpm rpms/
	ls -lh rpms/
	$(MAKE) clean-build-images

# ---- 清理供应链门禁同 job 重建留下的中间镜像 ----
.PHONY: clean-build-images
clean-build-images:
	# 只删除本目标创建的镜像；交付镜像 agw:* 不在此命名空间。
	docker image rm \
		$(BUILD_NS)/package-apisix:$(UPSTREAM_VERSION) \
		$(BUILD_NS)/apisix:$(UPSTREAM_VERSION) \
		$(BUILD_NS)/package-runtime:0.0.0 \
		$(BUILD_NS)/runtime:0.0.0 \
		api7/fpm \
		2>/dev/null || true
	# 删除中间镜像删标签后留下的层，不触碰 BuildKit/gha cache。
	docker image prune -f

# ---- 交付镜像 ----
.PHONY: build-docker
build-docker:
	test -n "$(wildcard out/agw-*.rpm)" || { echo "错误: out/ 无最终 agw RPM，先 make build-rpm"; exit 1; }
	rm -rf rpms
	mkdir -p rpms
	cp out/agw-*.rpm rpms/
	docker build -t $(IMAGE_LOCAL) -f packaging/docker/Dockerfile .

# ---- verify：RPM 冒烟（Anolis 8.10 底座 + Tongsuo 国密断言）----
.PHONY: verify
verify:
	test -n "$(wildcard out/agw-*.rpm)" || { echo "错误: out/ 无最终 agw RPM，先 make build-rpm"; exit 1; }
	docker run --rm \
		-v "$$PWD/out":/output \
		-v "$$PWD/test/smoke":/smoke:ro \
		$(ANOLIS) bash -exc '\
			dnf -y localinstall /output/agw-*.rpm --nogpgcheck \
			&& bash /smoke/runtime-smoke.sh \
		'
	@echo "verify: RPM 冒烟 OK"

# ---- verify-docker：镜像冒烟（standalone Server 头断言 + 国密握手）----
.PHONY: verify-docker
verify-docker:
	docker image inspect $(IMAGE_LOCAL) > /dev/null || { echo "错误: 镜像不存在，先 make build-docker"; exit 1; }
	bash scripts/smoke-docker.sh $(IMAGE_LOCAL)
	@echo "verify-docker: 镜像冒烟 OK"

.PHONY: clean
clean:
	rm -rf build out output output-apisix output-runtime rpms apisix apisix-runtime
