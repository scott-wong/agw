# AGW

AGW 是一个独立、开放的 API 网关发行版，基于 [Apache APISIX](https://github.com/apache/apisix)。
只交付两件东西——一个 RPM 与一个容器镜像——并且只承诺一条可验证的平台基线；
TLS 运行时改用 [Tongsuo（铜锁）](https://github.com/Tongsuo-Project/Tongsuo)，
开箱提供国密（SM2/SM3/SM4、NTLS）能力。

- 关系表述：**based on Apache APISIX**。AGW 不改动上游的路由、插件与协议行为，
  差异全部在发行形态（见下表）。
- 承诺平台：**Anolis OS 8.10 × x86_64**；其他平台未经验证，不做承诺。
- v1 范围：只做网关本体。管理台（Admin UI）、etcd 与企业增强均不在交付物内。

## 交付物

| 交付物 | 名称 | 说明 |
|--------|------|------|
| RPM（EL8） | `agw-3.18.0-agw.2.el8.x86_64.rpm` | 唯一 RPM；不交付 `apisix-runtime` / `apisix` 中间包 |
| 镜像 | `ghcr.io/scott-wong/agw:3.18.0-agw.2` | 标签 `3.18.0-agw.2`（不可移动）、`3.18.0`、`latest` |

发布资产挂在 GitHub Release 上，附带发布镜像的 CycloneDX SBOM 与记录
RPM SHA256 / 镜像 digest 的 `release-manifest.json`。

容器默认以**非 root** 用户 `appuser（uid 10001）` 运行；APISIX 需要写的目录
（`/usr/local/apisix/conf`、`/usr/local/apisix/logs` 与 nginx 的 5 个 `*_temp`）
已在镜像内显式授权。需要挂载配置或日志卷时，请保证挂载点对该 uid 可写。

## 基线

唯一事实源是 `scripts/baseline.env`；`make fetch` 在构建前逐个校验，漂移即失败。

| 项 | 锁定值 |
|----|--------|
| 网关 | Apache APISIX `3.18.0` @ `0796d9c2cbedb1f8bf8194292ff526599f4fde20` |
| 运行时 | OpenResty `1.31.1.1`（release tarball，SHA256 校验） |
| TLS | [Tongsuo](https://github.com/Tongsuo-Project/Tongsuo) `master` @ `540603a3ff952ce00590bca022015feffbfb7597`（tag `8.5.0-pre2`，OpenSSL 3.5.4 内核），构建参数含 `enable-ntls` |
| 运行时模块 | 7 个上游模块，全部锁定 tag + commit |
| 交付镜像基础层 | `ghcr.io/scott-wong/anolis-secure:latest`，锁定 manifest digest `sha256:80a5453d…be265f1`，运行用户 `10001:10001` |

`ngx_multi_upstream_module` 与 `apisix-nginx-module` 会直接 patch nginx / OpenResty
bundle 源码，这是 OpenResty 版本的硬约束；OpenResty `1.31.1.1` 的适配以 vendored
补丁形式放在 `vendor-patches/`（上游 master + 对应 PR），来源 PR 与回退条件写在
各 `patch.sh` 头注。

交付镜像的基础层是自建的加固 Anolis 8.10 基线，上游每周一重建，因此 `:latest`
会前进；`make fetch` 校验它当前指向的 digest 是否仍等于登记值，漂移即红灯，
必须先重扫供应链门禁再更新 `BASE_IMAGE_DIGEST`。

## 与上游 APISIX 的差异

| 方面 | 上游 APISIX 3.18.0 | AGW |
|------|--------------------|-----|
| 响应头 | `Server: APISIX/<版本>` | `Server: agw`（打包期改写，standalone 冒烟断言） |
| TLS 运行时 | 官方预编译 OpenResty | 对 Tongsuo 编译的 OpenResty，启用 `enable-ntls` |
| 国密插件 | 需自行启用，且依赖 Tongsuo 运行时 | `gm` 进入默认插件表；RPM/镜像冒烟做真实 SM2 双证书 NTLS 握手 |
| 基础镜像与运行用户 | 各发行形态各自为政，容器默认 root | 统一自建加固基础层，以非 root `appuser:10001` 运行 |
| 交付形态 | deb / rpm / apk / Docker / Helm | 仅 RPM（EL8）+ Anolis 8.10 镜像 |
| 管理台 | 上游独立产品 | 不交付 |
| 配置中心 | etcd 内置/外置均可 | etcd 必须外置（3.5.x / 3.6）；支持 standalone 文件驱动（`config_provider: yaml`） |

## 国密（GM / NTLS）

运行时链接 Tongsuo 的 `libssl.so.3` / `libcrypto.so.3`，因此 SM2 双证书 NTLS
开箱可用：

```sh
/usr/local/openresty/tongsuo/bin/openssl version
# Tongsuo: Tongsuo 8.5.0-pre2 (Library: Tongsuo 8.5.0-pre2)
```

APISIX 默认 cipher 不含国密套件，终止国密 TLS 时需在 `conf/config.yaml` 中显式加入：

```yaml
apisix:
  ssl:
    ssl_ciphers: ECDHE-SM2-WITH-SM4-SM3:HIGH:!aNULL:!MD5
```

`gm` 插件（动态配置国密双证书）已进入 AGW 构建的默认插件表，可按上游
`docs/zh/latest/plugins/gm.md` 通过 Admin API 按 SNI 配置双证书。

## 目录

```text
VERSION                 版本唯一事实源
Makefile                fetch / build-rpm / build-docker / verify / verify-docker / release-assets / clean
scripts/                构建脚本 + baseline.env（基线事实源）
vendor-patches/         序号化 vendor 补丁模块（来源 PR 与回退条件见各 patch.sh 头注）
modules/                AGW 自研模块（v1 空占位，零自研）
packaging/rpm/          运行时镜像与最终 RPM 构建 Dockerfile + fpm 输入树 + Tongsuo openssl.cnf
packaging/docker/       交付镜像 Dockerfile（自建加固 Anolis 8.10 基础层 + 非 root 运行）
test/smoke/             冒烟资产（限流 lua、standalone 配置、Tongsuo 国密握手、运行时断言）
evidence/01…10/         证据包（权威归档；04-sbom / 09-ip 由 CI 回填）
docs/build-notes.md     构建链路说明
docs/adr/               架构决策记录
```

## 本地构建（需 Docker）

```sh
make fetch          # 校验全部基线 pin，取 APISIX 快照至 build/src
make build-rpm      # 运行时镜像 -> 最终 agw RPM（out/ 只保留一个产品 RPM）
make verify         # Anolis 8.10 容器：装 RPM + Tongsuo/国密 + openresty -V + apisix version + 限流 lua
make build-docker   # 备料 rpms/ 并组装交付镜像 agw:<版本>
make verify-docker  # 镜像冒烟：apisix init + standalone Server: agw 断言 + SM2/NTLS 握手
make clean
```

## CI/CD

全部在 GitHub Actions + GHCR 上完成，没有其他 CI 系统。

- `.github/workflows/build.yml`（push main / PR / 手工）：基线校验 → 两段 RPM →
  Anolis 8.10 RPM 冒烟 → 交付镜像 + standalone/国密冒烟 → 自研比例 →
  供应链门禁（SBOM + Grype HIGH + Trivy HIGH/CRITICAL）→ 去字符 grep 门禁。
- `.github/workflows/publish.yml`（tag `v*` / 手工）：构建最终 RPM，推送三个标签的
  镜像到 GHCR，回拉镜像重跑 standalone/国密冒烟，再把 RPM、镜像 SBOM 与
  `release-manifest.json` 发布到 GitHub Release。

两个工作流都自洽：不引用任何外部仓库的 reusable workflow 或 composite action。

发布不可变：`<版本>` 标签与 Git tag 一律不移动，重新发布只能 bump `VERSION`。

## 许可

Apache License 2.0 — 见 [LICENSE](./LICENSE)。
