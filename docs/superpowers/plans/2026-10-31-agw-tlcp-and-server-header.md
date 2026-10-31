# AGW TLCP 双栈与 Server Header Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将同 SNI 普通 TLS/TLCP 双栈补丁并入 AGW 镜像，并让 Server Header 冒烟稳定覆盖真实的 worker 配置读取。

**Architecture:** APISIX 的 `gm` 插件负责 TLCP 双证书，AGW 跟踪补丁增加同 SNI 普通 TLS 证书安装；镜像冒烟在真实 APISIX 进程中验证两种握手。Server Header 测试改为容器内复制配置并检查 worker 初始化日志。

**Tech Stack:** Apache APISIX 3.19.0、OpenResty 1.31.8.1、Tongsuo 8.5.0、Bash、Docker。

**Spec:** `docs/superpowers/specs/2026-10-31-agw-tlcp-and-server-header-design.md`

## Global Constraints

- 版本使用 `3.19.0-agw.3`。
- 镜像仍支持 `openeuler` 与 `ubuntu` 两个独立变体。
- 普通 TLS 与 TLCP 必须使用同一端口和同一 SNI。
- TLCP 自动化以 Tongsuo ECC/ECDHE SM2 套件为准。
- 不提交私钥、生产证书或宿主机凭据。

### Task 1: 固化 Server Header 冒烟边界

**Files:**
- Modify: `scripts/smoke-docker.sh`
- Modify: `scripts/smoke-etcd.sh`

**Interfaces:**
- Consumes: `test/smoke/*.yaml` 夹具。
- Produces: 与宿主机文件权限无关的 Server Header 和 etcd 冒烟。

- [x] **Step 1: 修改 standalone 冒烟，从 `/smoke` 复制配置到 APISIX 配置目录。**
- [x] **Step 2: 复制后显式 `chmod 0644`，并在请求前断言 error log 无 `init_worker_by_lua error`。**
- [x] **Step 3: 修改 etcd 冒烟，以容器内 wrapper 复制并 chmod 配置后再执行镜像 entrypoint。**
- [x] **Step 4: 对当前 Ubuntu 镜像运行修改后的 Server Header 用例，期望自定义值返回 `agw-custom`。**

### Task 2: 纳入 TLCP 双栈补丁并增加 APISIX 级测试

**Files:**
- Create: `patches/apisix/0002-agw-gm-dual-tls.patch`
- Create: `test/smoke/gm-dual-tls-apisix.sh`
- Modify: `scripts/install-apisix.sh`
- Modify: `scripts/static-checks.sh`
- Modify: `scripts/smoke-docker.sh`
- Modify: `test/smoke/runtime-smoke.sh`

**Interfaces:**
- Consumes: APISIX 上游 `apisix/plugins/gm.lua`。
- Produces: `gm: true` SSL 对象支持 `certs[1]` 为 SM2 签名证书、`certs[2]` 为普通 TLS 证书。

- [x] **Step 1: 增加运行时断言，检查镜像内 `gm.lua` 含 `set_standard_pem_ssl_key`，先对当前镜像运行并确认失败。**
- [x] **Step 2: 增加 APISIX 级 TLCP 测试脚本，生成测试证书并在普通 TLS、TLCP ECC、TLCP ECDHE strict 下请求 `/no-such-route`。**
- [x] **Step 3: 对当前未集成补丁的镜像运行测试脚本，期望证书配置或普通 TLS 分支失败。**
- [x] **Step 4: 新增 `0002` 补丁，安装脚本按文件名顺序应用全部补丁。**
- [x] **Step 5: 更新静态检查，应用全部补丁并解析 `apisix/plugins/gm.lua`。**
- [x] **Step 6: 重新构建 Ubuntu 镜像并运行 TLCP 测试，期望三类握手均通过。**

### Task 3: 版本、文档与证据

**Files:**
- Modify: `VERSION`
- Modify: `packaging/docker/Dockerfile`
- Modify: `README.md`
- Modify: `docs/build-notes.md`
- Modify: `scripts/gen-evidence.py`
- Regenerate: `evidence/**`

**Interfaces:**
- Consumes: 完成的补丁和测试。
- Produces: `3.19.0-agw.3` 的构建与发布事实。

- [x] **Step 1: 将版本更新为 `3.19.0-agw.3`。**
- [x] **Step 2: 更新 README、构建说明和证据生成文案，明确普通 TLS/TLCP 同 SNI 双栈。**
- [x] **Step 3: 运行 `make evidence` 并执行 `make verify`。**

### Task 4: 镜像验证与 s15 切换

**Files:**
- No repository file changes.

- [x] **Step 1: 在 s15 构建 `agw:3.19.0-agw.3-ubuntu`。**
- [x] **Step 2: 运行 `smoke-docker.sh` 与 `smoke-etcd.sh`。**
- [x] **Step 3: 将 s15 Compose 切到新镜像，移除 `gm-dual-tls.lua` 外部挂载。**
- [x] **Step 4: 验证普通 HTTPS、TLCP ECC、TLCP ECDHE strict、Admin UI 和路由数量。**

