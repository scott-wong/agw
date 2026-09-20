# AGW 网关发行版

AGW 是一个独立开放的 API 网关发行版：以 Apache APISIX 为上游基线，用 Tongsuo
替代 OpenSSL 构建运行时，产出单一最终 RPM 与容器镜像。本文件固定这套语境里的
用词，避免文档、脚本、流水线各说各话。

## Language

**AGW**:
本仓交付的网关发行版名称；技术 id 一律小写 `agw`（服务名、RPM 包名、镜像名、`Server` 响应头）。
_Avoid_: 网关, gateway, apisix（指代产品时）

**基线**:
`scripts/baseline.env` 中锁定的上游版本事实合集——APISIX tag + commit、OpenResty tarball SHA256、Tongsuo commit、7 个运行时模块 tag + commit。
_Avoid_: 版本表, 依赖锁, lockfile

**运行时镜像**:
把 OpenResty、Tongsuo 与 7 个运行时模块编译到 `/usr/local/openresty` 的中间产物，只作为最终 RPM 的输入。
_Avoid_: 基础镜像, base image, openresty 镜像

**最终 RPM**:
唯一交付的 RPM，包名 `agw-<版本>.el8.x86_64.rpm`，内嵌运行时镜像的整棵目录树。
_Avoid_: 产品包, 主包, 网关包

**vendor-patches/**:
逐条登记的上游补丁模块，每条含来源 PR 与回退条件；不计入自研行数。
_Avoid_: patches/, third_party/, 第三方补丁

**modules/**:
AGW 自研模块目录；v1 为空占位。
_Avoid_: src/, lib/ 等泛化目录

**零自研**:
v1 的明确立场——不提供任何 AGW 原创代码，`self-developed-ratio.json` 的分子恒为 0。
_Avoid_: 无自研, 全自研

**国密**:
经 Tongsuo `enable-ntls` 提供的 SM2 双证书（签名证书 + 加密证书）传输能力；APISIX 侧由 `gm` 插件承载，须在 `ssl_ciphers` 显式选择国密套件。
_Avoid_: 商密, SM2-only, 国密开关

**发布清单**:
`scripts/write-release-manifest.sh` 产出的发布事实记录（版本、tag、workflowRun、镜像 digest、RPM SHA256）。
_Avoid_: release notes, 发布说明

**去字符门禁**:
`scripts/verify-debrand.sh`，禁止仓库内出现内部组织、内部渠道与未使用发行形态的痕迹。
_Avoid_: 敏感词扫描, 合规扫描
