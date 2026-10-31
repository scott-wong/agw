# AGW

AGW 是一个独立开放的 API 网关发行版，基于 [Apache APISIX](https://github.com/apache/apisix)。
当前版本线基于 APISIX `3.19.0`，使用 OpenResty `1.31.8.1` 与
[Tongsuo（铜锁）](https://github.com/Tongsuo-Project/Tongsuo) `8.5.0` 构建，
只交付两个 `linux/amd64` 容器镜像：

- `ghcr.io/scott-wong/agw:<版本>-openeuler`
- `ghcr.io/scott-wong/agw:<版本>-ubuntu`

不交付 RPM、fpm 中间包、离线镜像 tar，也不提供全局 `<版本>` / `latest` 标签。
两个部署变体分别使用：

- openEuler `24.03-lts-sp4`
- Ubuntu `24.04`

上游关系表述固定为 **based on Apache APISIX**。路由、插件和协议行为沿用上游；
AGW 的差异集中在运行时、交付镜像、默认品牌头和少量发行配置。

## 交付标签

`VERSION` 当前为 `3.19.0-agw.4`，对应上游 `3.19.0`。每个变体有三个标签：

| 变体 | 不可移动版本标签 | 上游线标签 | 浮动标签 |
|------|------------------|------------|----------|
| openEuler | `<版本>-openeuler` | `<上游版本>-openeuler` | `latest-openeuler` |
| Ubuntu | `<版本>-ubuntu` | `<上游版本>-ubuntu` | `latest-ubuntu` |

例如：

```text
ghcr.io/scott-wong/agw:3.19.0-agw.4-openeuler
ghcr.io/scott-wong/agw:3.19.0-openeuler
ghcr.io/scott-wong/agw:latest-openeuler

ghcr.io/scott-wong/agw:3.19.0-agw.4-ubuntu
ghcr.io/scott-wong/agw:3.19.0-ubuntu
ghcr.io/scott-wong/agw:latest-ubuntu
```

正式发布必须先为两个变体推送 candidate 镜像，全部测试与供应链门禁通过后，
才把 candidate 的精确 digest 提升为最终标签。任一 candidate 失败时不会创建
GitHub Release。已经存在的正式标签不会被移动；重新发布必须 bump `VERSION`。

## 基线

`scripts/baseline.env` 是唯一事实源，`make fetch` 会校验 tag commit、源码归档
SHA256 和基础镜像 digest：

| 项 | 锁定值 |
|----|--------|
| APISIX | `3.19.0` @ `473043623c161966f3f6ef4e8f12d2d8667a12d2` |
| APISIX Admin UI | `apisix_3.19.0-0_amd64.deb`，固定 SHA256 |
| OpenResty | `1.31.8.1` |
| Tongsuo | `8.5.0`（OpenSSL 3.5.4 内核，启用 TLCP/NTLS） |
| API7 runtime 构建口径 | `apisix-runtime/1.4.2` @ `6aaa033823d3b041952a1da6360b5d11ccb99c08` |
| PCRE2 | `10.49`，源码构建并安装在 OpenResty 前缀内 |
| zlib | `1.3.2`，源码构建并安装在 OpenResty 前缀内 |
| wasmtime C API | `v0.38.1`，固定归档 SHA256 |
| openEuler 基础镜像 | `quay.io/openeuler/openeuler:24.03-lts-sp4`，按 index digest 固定 |
| Ubuntu 基础镜像 | `ubuntu:24.04`，按 index digest 固定 |

两个运行时都在各自目标发行版内编译；不会把 openEuler 的编译结果复制到 Ubuntu，
或反向复制。最终阶段使用干净基础镜像，只复制运行所需目录，不带编译器、头文件、
开发包或构建缓存。

## 运行用户

最终镜像不设置 `USER`，因此继承基础镜像的默认用户。当前两个基础镜像默认均为
`root`。Nginx master 继续以 root 启动，worker 按 OpenResty 默认降权到 `nobody`；
只有 `/usr/local/apisix/logs` 与五个 `*_temp` 目录授予 worker 写权限。

## 可配置 `Server` 头

AGW 通过跟踪补丁扩展 APISIX 配置，不使用构建期字符串替换：

```yaml
apisix:
  server_header: agw
```

- 缺省或设置为非空安全字符串：发送该值。
- 设置为 `false`：完全抑制 `Server` 头，包括 Nginx 默认值。
- 空字符串、CR/LF、控制字符、首尾空白或超过 64 字节的值会在配置校验阶段被拒绝。

自定义示例：

```yaml
apisix:
  server_header: edge-gateway
```

该配置作用于数据面、Admin API 和 APISIX 生成的错误响应。上游的
`enable_server_tokens` 不再决定 AGW 的 `Server` 值。

## 国密与 TLS

运行时动态链接 Tongsuo 的 `libssl.so` / `libcrypto.so`，`gm` 插件加入默认插件表。
需要终止 TLCP 流量时，在配置中显式选择国密套件。Tongsuo 在线路上仍报告
`NTLSv1.1`，对应 GB/T 38636-2020 TLCP：

```yaml
apisix:
  ssl:
    ssl_ciphers: ECDHE-SM2-SM4-GCM-SM3:ECDHE-SM2-SM4-CBC-SM3:ECC-SM2-SM4-GCM-SM3:ECC-SM2-SM4-CBC-SM3:HIGH:!aNULL:!MD5
```

AGW 的 `gm` 跟踪补丁允许同一个 SNI 同时配置普通 TLS 和 TLCP。SSL 对象中
`cert`/`key` 是 SM2 加密证书对，`certs[1]`/`keys[1]` 是 SM2 签名证书对，
后续 `certs`/`keys` 项作为普通 TLS 证书安装：

```yaml
ssls:
  - snis: [s15.example.com]
    gm: true
    cert: <SM2 encryption certificate>
    key: <SM2 encryption key>
    certs:
      - <SM2 signing certificate>
      - <standard TLS certificate>
    keys:
      - <SM2 signing key>
      - <standard TLS key>
```

镜像冒烟会生成独立测试 CA、SM2 签名/加密证书和普通 P-256 证书，在真实 APISIX
进程中验证普通 TLS、TLCP ECC、TLCP ECDHE strict（GCM/CBC）及双证书
`keyUsage`。OpenSSL 默认安全等级保持 2，不通过降低安全等级绕过校验。

Chrome、Edge、Firefox 和 Safari 不原生支持 TLCP；客户端仍需国密浏览器或
TLCP 测试客户端，并信任相应 SM2 根证书。

AGW 不对标 OpenSSL 的 CVE 修复状态；发布清单记录
`tongsuoCveParity: not-audited`，不宣称两者安全等价。

最终镜像内置 APISIX Dashboard UI，访问路径为 Admin API 的 `/ui/`。UI 静态文件
从同版本官方 APISIX `3.19.0-0` 包中提取并校验 SHA256，AGW 的 OpenResty、
Tongsuo 与 APISIX 服务端代码仍由本仓独立构建。

Dashboard SVG 详情页会归一化 Admin API 隐藏私钥后缺失的 `keys` 字段，避免带
`certs` 的 SSL 对象详情页抛出 `Cannot read properties of undefined (reading 'id')`。

## etcd 与 standalone

默认部署仍为外置 etcd + Admin API：

```yaml
deployment:
  role: traditional
  role_traditional:
    config_provider: etcd
  etcd:
    host:
      - http://etcd:2379
```

文件驱动的 standalone 模式继续支持：

```yaml
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml
```

CI 会分别验证 standalone 启动、外置 etcd 启动、Admin API 和数据面响应头。

## 构建

需要 Docker/Buildx 与网络。版本和 SHA256 校验通过后才会进入编译：

```sh
make fetch
make build-image VARIANT=openeuler IMAGE=agw:3.19.0-agw.4-openeuler
make build-image VARIANT=ubuntu IMAGE=agw:3.19.0-agw.4-ubuntu
make verify-image VARIANT=openeuler IMAGE=agw:3.19.0-agw.4-openeuler
make verify-image VARIANT=ubuntu IMAGE=agw:3.19.0-agw.4-ubuntu
make verify-etcd IMAGE=agw:3.19.0-agw.4-openeuler
```

常用入口：

| 命令 | 作用 |
|------|------|
| `make fetch` | 校验基线并准备 `distfiles/` |
| `make evidence` | 从版本、基线、补丁和模块事实刷新 `evidence/` |
| `make build-images` | 分别构建两个最终镜像 |
| `make verify` | shell、YAML、补丁和 Lua 语法静态检查 |
| `make verify-images` | 两个镜像的运行时、品牌头、普通 TLS/TLCP 双栈冒烟 |
| `make verify-etcd` | 外置 etcd 与 Admin API 冒烟 |
| `make clean` | 清理 `build/`、`distfiles/` 等本地产物 |

## CI 与发布

所有构建、测试、镜像和发布都在 GitHub 完成。

- `build-openeuler.yml`：独立的 openEuler 基线、构建、回拉冒烟与供应链门禁。
- `build-ubuntu.yml`：独立的 Ubuntu 基线、构建、回拉冒烟与供应链门禁。
- 两个构建流互不等待；一个变体失败不会跳过或阻塞另一个变体。
- `publish.yml`：tag `v<版本>` 触发；两个 candidate 构建、回拉、冒烟与 Trivy
  全部通过后，以精确 digest 提升最终标签，再回拉最终标签复验并创建 Release。

Trivy `v0.76.1` 是唯一阻断扫描器，阻断级别为 `HIGH,CRITICAL`，同时启用 secret
扫描。Syft 只负责生成 CycloneDX SBOM，因为 Trivy 不能完整编目 LuaRocks。
Trivy 当前仍不提供 openEuler OS RPM 漏洞库覆盖；`dnf updateinfo --security`
只作为非阻断证据，不声称等同 Ubuntu 覆盖。

Release 附件只包含：

- `agw-<版本>-openeuler.cyclonedx.json`
- `agw-<版本>-ubuntu.cyclonedx.json`
- `release-manifest.json`（`schemaVersion: 2`）

## 许可

Apache License 2.0，见 [LICENSE](./LICENSE)。
