# 基线来源说明（02-source）

基线事实源：`scripts/baseline.env`（唯一事实源，改基线＝改此文件 + `make fetch` 校验 + 换 `VERSION`）。

## 网关基线（based on Apache APISIX）

| 项 | 值 |
|----|----|
| 上游 tag | `3.18.0` |
| commit | `0796d9c2cbedb1f8bf8194292ff526599f4fde20` |
| 源码 tarball SHA256 | `5cf1e2b1cf57208b6b4a63cb64a853449501c3c7548348ea9af84cac3f7b0ca5` |

## 运行时基线（OpenResty release 线）

| 项 | 值 |
|----|----|
| 版本 | `1.31.1.1` |
| tarball SHA256 | `65b78baadd3f0984055de89bf13f4a1932e5bfe9c31932037a134ea2b1a0ce42` |

## TLS 基线（Tongsuo，替代 OpenSSL）

| 项 | 值 |
|----|----|
| 仓库 | `https://github.com/Tongsuo-Project/Tongsuo.git` |
| 分支 | `master` |
| commit | `540603a3ff952ce00590bca022015feffbfb7597` |
| 追溯 tag | `8.5.0-pre2`（与上述 commit 同点） |
| 上游内核版本 | OpenSSL `3.5.4` / Tongsuo `8.5.0-pre2` |
| 安装前缀 | `/usr/local/openresty/tongsuo`（`libdir=lib64`） |
| 配置 | `./config shared enable-ntls`（国密 NTLS 双证书） |

`master` 是滚动分支，故以 commit 为准；`scripts/verify-baseline.sh` 同时校验
`refs/heads/master` 与追溯 tag，两者任一漂移即红灯。上游 `api7/tongsuo` 已不可用，
基线使用 Tongsuo 官方仓库；国密构建口径参考 `apache/apisix` 与 `api7/apisix-plugin-gm` 文档。

## 运行时模块（tag + commit，见 scripts/baseline.env）

共 7 个模块（其中 `apisix-nginx-module` 含 stream / meta 两个子编译单元）。

| 模块 | 版本 | commit |
|------|------|--------|
| ngx_multi_upstream_module | 1.3.4 | `fc195137f180d8aba27c9eeedf291dd812bf096b` |
| apisix-nginx-module | 1.19.10 | `c3d122f52a61e4fbc2775c29ce0d8d5e8f80b7a8` |
| wasm-nginx-module | 0.7.0 | `0b4b31d6ecfdbc587e8ea455ed6e920a98aadff1` |
| lua-var-nginx-module | v0.5.3 | `dc04c71e14e8a0407831f9019043d7e6da61b3c3` |
| mod_dubbo | 1.0.2 | `4aabf9448fe4a49ca71009af8e03645ee5dadd15` |
| lua-resty-events | 0.2.0 | `8448a92cec36ac04ea522e78f6496ba03c9b1fd8` |
| ngx_http_ffi_client | v0.1.3 | `ea8374ddf416ee2553a8aff60189310ca1b6b0c0` |

其中 `ngx_multi_upstream_module` 与 `apisix-nginx-module` 直接 patch nginx / OpenResty bundle 源码，是 OpenResty 版本的硬约束（详见 `docs/build-notes.md`「TLS 基线：Tongsuo（国密）」与 README「基线」）。

版本号 `3.18.0-agw.2` 可据此反查双基线。`OPENRESTY_SOURCE=master` 判非发行。

## 交付镜像基础层

| 项 | 值 |
|----|----|
| 镜像 | `ghcr.io/scott-wong/anolis-secure:latest`（自建加固 Anolis 8.10，上游每周一重建） |
| 锁定的 index digest | `sha256:80a5453d4ddf4842f5d4a5c3cd154544f05bf0b5ed475d1f9e4f9ee62be265f1` |
| amd64 平台 manifest | `sha256:a3ed8f85a7000d0404b06f0475b5bb53cc9432b42911dbc373a4b299093f1586` |
| 运行用户 | `10001:10001`（基础层自带的 `appuser`） |

`latest` 是滚动 tag，故 `scripts/verify-baseline.sh` 校验 tag 当前指向的 manifest
digest 是否仍等于登记值：漂移即红灯，必须先重扫供应链门禁（Grype/Trivy + 例外复核）
再更新 `scripts/baseline.env` 的 `BASE_IMAGE_DIGEST`。决策与落地方式见
`docs/adr/0005-delivery-image-hardened-base.md`。
