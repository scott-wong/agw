# 构建链路说明

## 总览

`packaging/docker/Dockerfile` 有四个主要 target：

```text
openeuler-builder   openEuler 24.03 LTS SP4 内编译运行时与 APISIX
ubuntu-builder      Ubuntu 24.04 内独立编译运行时与 APISIX
openeuler-final     干净 openEuler 基础镜像 + 对应 builder 的运行时
ubuntu-final        干净 Ubuntu 基础镜像 + 对应 builder 的运行时
```

不存在跨发行版复制运行时目录。最终阶段不包含 gcc、g++、make、开发头文件、静态库
或包管理器构建缓存。

## 源码准备

`make fetch` 执行 `scripts/verify-baseline.sh`：

1. 用 `git ls-remote` 校验 APISIX、OpenResty、Tongsuo、build-tools、PCRE2 和
   7 个运行时模块的 tag commit。
2. 下载锁定归档到 `distfiles/`，逐个校验 SHA256。
3. 校验 openEuler、Ubuntu 与测试 etcd 镜像的 index digest。
4. 把 APISIX 源码解压到 `build/src/`，供静态检查与自研比例统计使用。

Docker 构建只读取已经校验过的 `distfiles/`，不会在 Dockerfile 中执行未校验的
版本发现。

## 运行时

`scripts/build-apisix-runtime.sh` 在目标发行版内：

1. 从源码编译 PCRE2 `10.49` 到 `/usr/local/openresty/pcre`。
2. 从源码编译 zlib `1.3.2` 到 `/usr/local/openresty/zlib`。
3. 编译 Tongsuo `8.5.0` 到 `/usr/local/openresty/tongsuo`，参数包含
   `shared enable-ntls zlib`，并统一使用 `--libdir=lib`。
4. 运行模块自带的 `patch.sh`；`apisix-nginx-module 1.20.3` 与
   `ngx_multi_upstream_module 1.4.1` 原生识别 OpenResty `1.31.8.1`，不再维护旧
   OpenResty 的本地 patch 覆盖。
5. 按 API7 runtime `1.4.2` 口径构建 OpenResty，链接 Tongsuo、PCRE2 与 zlib，
   并用 `ldd` 断言动态库来源。

`nginx` 刻意不传 `--with-openssl=`。该选项会用 Nginx 自己的参数重新配置源码，
破坏 Tongsuo 的 `enable-ntls` 口径；AGW 通过 include、library path 和 rpath 链接
动态 Tongsuo。

## APISIX

`scripts/install-luarocks.sh` 用 OpenResty 的 LuaJIT 安装固定版本 LuaRocks。
`scripts/install-apisix.sh`：

1. 解压 APISIX `3.19.0` 并应用
   `patches/apisix/0001-agw-server-header-and-gm.patch`。
2. 用 LuaRocks 构建依赖和 APISIX CLI。
3. 组装 `/usr/local/apisix`、`/usr/local/bin/apisix` 与依赖树。
4. 注入 `-DXMLSEC_NO_RIPEMD160=1`，适配 Tongsuo 不再导出
   `EVP_ripemd160` 的现实。

补丁做三件事：

- 增加 `apisix.server_header` 默认值 `agw`；
- 用 JSON Schema 拒绝空值、控制字符、首尾空白和超长值，并允许 `false`；
- 把 `gm` 加入默认插件表。

## 最终阶段

`scripts/install-runtime-deps.sh` 只安装运行库，并断言不存在 gcc/make。
`scripts/prepare-image.sh`：

- 清理 OpenResty 安装产生的头文件、静态库和 pkgconfig；
- 运行 `apisix init` 与 `openresty -t`；
- 断言默认配置包含 `server_header: agw` 与 `gm`；
- 把 `logs` 与五个 `*_temp` 目录授予 `65534:65534`，对应 `nobody` worker；
- 写入镜像来源、运行用户与 Tongsuo CVE 对标状态。

最终镜像不设置 `USER`，继承基础镜像默认用户。当前 openEuler 与 Ubuntu 基础镜像
默认均为 root。

## CI

`build.yml` 对两个变体并行构建和验证：

- `smoke-docker.sh`：运行时、默认/自定义/关闭 `Server` 头、无重复头、非法值拒绝、
  standalone 模式、SM2 双证书 NTLS 握手；
- `smoke-etcd.sh`：外置 etcd、Admin API、数据面；
- Syft：两个变体各自生成 CycloneDX SBOM；
- Trivy：唯一阻断扫描器，`HIGH,CRITICAL` + secret；
- openEuler 的 `dnf updateinfo --security`：仅非阻断证据。

`publish.yml` 先推送两个 candidate，再分别回拉冒烟和扫描。任一环节失败都不会创建
最终标签或 GitHub Release。提升使用 `crane tag` 指向 candidate 的精确 digest，
不是重新构建。

## 版本不可变性

`VERSION` 是唯一事实源，当前为 `3.19.0-agw.1`。Git tag 必须是
`v<版本>`。正式镜像标签不得移动；重新发布必须 bump `VERSION`。
