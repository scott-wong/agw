# 3.19 发行线只交付 openEuler 与 Ubuntu 两个最终镜像

AGW 3.19 起放弃 RPM 与中间打包链，只交付两个 `linux/amd64` 最终镜像：
openEuler `24.03-lts-sp4` 与 Ubuntu `24.04`。两个镜像都在各自目标发行版内完整
编译 OpenResty、Tongsuo、PCRE2、zlib 与 APISIX，不跨发行版复制运行时树。

## 理由

- 跨发行版复制编译产物会隐式依赖未声明的 glibc、libstdc++ 与 OpenSSL ABI，难以
  审计。
- 多阶段 Dockerfile 已足以把编译器、头文件和开发包留在 builder，不再需要 RPM
  作为中间边界。
- 用户需要的是可直接运行的发行镜像，而不是再安装一次包。

## 决策

- 最终 target 固定为 `openeuler-final` 与 `ubuntu-final`。
- 基础镜像按 index digest 固定；基础镜像 tag 只用于人类阅读。
- 最终阶段不设置 `USER`，继承基础镜像默认用户（当前均为 root）；Nginx worker
  降权到 `nobody`，只授予 logs 与 temp 目录。
- 不交付 RPM、fpm 中间包和离线镜像 tar。
- `Server` 头由跟踪的 APISIX 补丁配置，默认 `agw`，`false` 抑制。
- 发布清单升级为 `schemaVersion: 2`，同时记录两个镜像的 digest、SBOM 和基础镜像。

## Consequences

- 构建时间与网络依赖增加，因为两个发行版分别下载依赖并编译。
- 任一变体失败即视为整个发布失败；不得只发布其中一个变体。
- openEuler 的 Trivy OS RPM 漏洞库覆盖仍为 `unsupported`，该限制必须在安全证据和
  发布清单中显式保留。
- 正式标签必须从两个 candidate 的精确 digest 提升，禁止重新构建后直接推送。
