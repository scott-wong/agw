# AGW 网关发行版

AGW 是一个独立开放的 API 网关发行版：以 Apache APISIX `3.19.0` 为上游，
在 openEuler 与 Ubuntu 两个目标发行版内分别编译 OpenResty + Tongsuo 运行时，
只交付两个 `linux/amd64` 容器镜像。

## Language

**AGW**:
本仓交付的网关发行版名称；技术 id 一律小写 `agw`（服务名、镜像名、默认 `Server`
响应头）。
_Avoid_: 网关, gateway, apisix（指代产品时）

**基线**:
`scripts/baseline.env` 中锁定的上游事实合集：APISIX、OpenResty、Tongsuo、
PCRE2、zlib、LuaRocks、7 个运行时模块、源码归档 SHA256、基础镜像 digest 和安全
工具版本。
_Avoid_: 版本表, 依赖锁, lockfile

**变体**:
同一个 AGW 版本的两个交付目标，固定为 `openeuler` 与 `ubuntu`。每个变体都在自己的
基础镜像内完成编译和测试，不共享编译产物。
_Avoid_: 平台, flavor, distro image

**基础镜像**:
最终镜像的 `FROM`：`quay.io/openeuler/openeuler:24.03-lts-sp4` 或
`ubuntu:24.04`，两者都按 index digest 固定。最终镜像继承基础镜像默认用户；当前为
root。
_Avoid_: 运行时镜像, base layer

**运行时**:
编译到 `/usr/local/openresty` 的 OpenResty、Tongsuo、PCRE2、zlib 与运行时模块。
每个变体独立编译，最终阶段只复制运行所需文件。
_Avoid_: 基础镜像, OpenResty 镜像

**最终镜像**:
仓库 `ghcr.io/scott-wong/agw` 中以 `-openeuler` 或 `-ubuntu` 结尾的镜像。
不存在全局 `<版本>` 或 `latest` 标签，也不存在离线镜像 tar。
_Avoid_: 产品包, 主包

**候选镜像**:
发布流程中先推送的 `<版本>-<变体>-candidate`。只有两个候选都通过构建、回拉冒烟和
Trivy 后，才会按精确 digest 提升为最终标签。
_Avoid_: 预发布镜像, 临时标签

**`server_header`**:
AGW 扩展配置。缺省值 `agw`；字符串按原值发送；`false` 完全抑制 `Server` 头。
_Avoid_: 品牌开关, Server token

**国密**:
经 Tongsuo `enable-ntls` 提供的 SM2 双证书（签名证书 + 加密证书）传输能力；
APISIX 侧由默认启用的 `gm` 插件承载，须在 `ssl_ciphers` 显式选择国密套件。
_Avoid_: 商密, SM2-only, 国密开关

**发布清单**:
`scripts/write-release-manifest.sh` 产出的 `schemaVersion: 2` 事实记录，包含两个
镜像变体的 digest、标签、基础镜像、SBOM 哈希、运行用户和扫描范围。
_Avoid_: release notes, 发布说明

**Trivy 门禁**:
唯一阻断式漏洞与 secret 扫描。级别固定为 `HIGH,CRITICAL`。openEuler OS RPM
漏洞库覆盖为 `unsupported`，该限制必须显式记录。
_Avoid_: 双扫描器, 交叉验证

**去字符门禁**:
`scripts/verify-debrand.sh`，禁止仓库内出现内部组织、内部渠道与未使用发行形态的
痕迹。
_Avoid_: 敏感词扫描, 合规扫描
