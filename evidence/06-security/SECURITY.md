# 安全扫描（06-security）

## CI 门禁（GitHub Actions）

两个工作流的扫描职责不同：

- `build.yml`（分支 / PR / 手动）：Syft 生成镜像 CycloneDX SBOM；Grype 扫描镜像
  （`-c .grype.yaml`），HIGH 及以上失败即红灯；Trivy 扫描镜像（自动加载仓库根
  `.trivyignore`），HIGH/CRITICAL 失败即红灯；SBOM、SARIF 与门禁结果随 Actions
  artifact 归档。
- `publish.yml`（tag `v*` 或手动）：Syft 生成**发布用**镜像 SBOM 并附到 GitHub
  Release；**不**重复执行 Grype/Trivy。发布只从 `build.yml` 全绿的 commit 打 tag，
  门禁证据由该 run 承担，发布清单记录 `source.commit` 与 `workflowRun` 以便回溯。
  发布镜像 digest 与 build 流被扫描的本地构建镜像不同，属已知缺口，见文末。

## 风险接受批次索引

| 批次 | 登记日期 | 触发场景 | 台账 | 新增 CVE | 例外条目 | 复核到期 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | 2026-09-14 | 首次镜像基线扫描 | `.grype.yaml` / `.trivyignore` | 19 | 27 | 2026-10-14 |
| 2 | 2026-09-20 | `build.yml` 供应链门禁 Grype 步骤 | 同上 | 7 | 10 | 2026-10-14 |
| 合计 | — | — | — | 26 | 37 | 2026-10-14 |

## 镜像加固（2026-09-14）

镜像门禁首次运行即失败，问题定位为 Anolis 基础层的 Python 打包负载：

- Trivy：`python-pkg` 5×HIGH —— `pip 9.0.3`（CVE-2019-20916、CVE-2021-3572）与
  `setuptools 39.2.0`（CVE-2022-40897、CVE-2024-6345、CVE-2025-47273）；
- Grype：除上述同类负载外另有 HIGH，需以完整报告定位。

处置：镜像安装最终 RPM 后卸载 `python3-pip-wheel`、`python3-setuptools-wheel`、
`platform-python-setuptools`（必要时含 `platform-python-pip`、`python3-setuptools`），
并在 Dockerfile 内断言 wheel 与 dist-info 已消失。依据：

1. 最终 RPM 的 requires 只有 `openldap`、`pcre`、`which`、`libxml2`、`libxslt`；
2. 镜像入口是 `/usr/bin/apisix`（OpenResty/Lua），运行时不使用 pip/setuptools；
3. `dnf` 拒绝卸载受保护的 wheel 包，故用 `rpm -e --nodeps`；卸载后 dnf 仍可使用。

流水线同时调整为：Grype/Trivy 完整报告落盘并随制品归档，日志只输出 High/Critical
行，并记录两个扫描器版本，避免再次出现“失败但看不到具体 CVE”的情况。

## 已批准风险接受（2026-09-14 批次）

等价镜像基线（Anolis 8.10 × x86_64，与本仓 Dockerfile 同一基础层）门禁结果：
Grype 报出 21 条 HIGH、0 条 CRITICAL，全部命中 Anolis 8.10 基础层 RPM 数据库
（`/var/lib/rpm/rpmdb.sqlite`）；Trivy `v0.74.0` 对同一镜像无 HIGH/CRITICAL。
连同首次登记并已生效的 `CVE-2026-53613`（util-linux 6 个子包），本批次共 19 个
CVE、27 条「CVE + 组件 + 版本」例外，登记在 `.grype.yaml` 与 `.trivyignore`。

AGW `build.yml` 对同一基线重新扫描的结论：本批 19 个 CVE 全部由 Grype 复现，例外按
登记继续保持；同一 run 另新增 7 个 CVE，按第二批登记，见文末。Trivy 对同镜像未报出
这些 CVE 的原因是它不识别 Anolis OS、根本不解析 RPM 数据库（见「扫描器实际覆盖面」），
不构成交叉验证。扫描报告（SARIF/SBOM）随 Actions run 归档，run URL 由发布清单
`workflowRun` 字段记录。

### 无修复依据

- Dockerfile 构建阶段已执行 `dnf -y update`，镜像内版本即 Anolis 8.10 仓库当前最新；
- Grype 匹配数据源为 `redhat:distro:redhat:8`，能给出修复版本的条目（如 expat
  `CVE-2026-45186` → `0:2.5.0-2.el8_10`）均为 RHEL el8_10 勘误，Anolis 8 尚未合入；
- 其余条目 Grype `Fix Version` 为空（未知/未修复），Anolis 侧无可用升级目标。

### 例外清单

| CVE | 组件 | 已装版本 | 说明 |
| --- | --- | --- | --- |
| CVE-2026-53613 | util-linux, libblkid, libfdisk, libmount, libsmartcols, libuuid | 2.32.1-48.0.1.an8 | Grype fix 状态 N/A |
| CVE-2026-63382 / 63383 / 63384 / 63385 / 63387 / 63388 | libevent | 2.1.8-5.el8 | RHEL 侧已修，Anolis 未合入 |
| CVE-2026-8458, CVE-2026-8927 | curl, libcurl | 7.61.1-35.0.2.an8.13 | 同上 |
| CVE-2026-86145, CVE-2026-89161 | pcre2 | 10.32-3.0.1.an8_6 | 同上 |
| CVE-2026-74860, CVE-2026-86140 | libxml2 | 2.9.7-21.0.1.an8.6 | 产品 RPM 声明依赖，见暴露面 |
| CVE-2026-11822, CVE-2026-11824 | sqlite-libs | 3.26.0-21.an8 | 基础层 |
| CVE-2025-68973 | gnupg2, gnupg2-smime | 2.2.20-4.an8 | 基础层 |
| CVE-2025-6176 | brotli | 1.0.6-4.an8 | 基础层 |
| CVE-2026-45186 | expat | 2.5.0-2.an8 | RHEL 修复版本 0:2.5.0-2.el8_10 |
| CVE-2026-73073 | vim-minimal | 2:8.0.1763-31.0.1.an8 | 基础层 |

### 暴露面

- 交付镜像入口为 `/usr/bin/apisix`（OpenResty/Lua），不提供 shell 或包管理入口；
- 上表组件除 `libxml2`（产品 RPM 声明的依赖）外均为基础层负载，agw 运行时不调用；
- 默认配置不对外提供 XML 上传/转换入口，libxml2 相关 CVE 无已知触发路径；
- 产品 RPM 的 `requires` 只有 `openldap`、`pcre`、`which`、`libxml2`、`libxslt`。

### 复核

- 复核期限：2026-10-14（与第二批同一日期，见文末）。到期后删除 `.grype.yaml` 与 `.trivyignore` 中全部条目并重扫；
- 若 Anolis 已发布对应勘误，先升级基础包再删除条目，不得直接延长豁免；
- 例外按「CVE + 组件 + 已装版本」精确匹配，任何基础包版本变化都会使条目失效，
  门禁自动重新拦截并要求重新评估。

## 已批准风险接受（2026-09-20 批次）

触发：`build.yml` 供应链门禁推进到 Grype 步骤 —— run `35501804881` / job
`106056425557`，`grype -c .grype.yaml agw:3.18.0-agw.1 -o sarif --fail-on high`
退出码 2，报出 10 条 HIGH/CRITICAL；该 run 的 Trivy 步骤未执行（串行且未加
`always()`），随后 run `35503276333` 复验：Grype 转绿，Trivy 因 secret 扫描红灯，
见「Trivy secret 扫描白名单」。

扫描对象为本地 daemon tag（未发布镜像），digest
`sha256:4e3d2bc386f24b3ee2690378fddc530124556d144355bcd86647e1bcf1db2dcd`。

### 无修复依据

- `packaging/docker/Dockerfile` 构建阶段已执行 `dnf -y update`，镜像内版本即 Anolis
  8.10 仓库当前最新；
- 本批 10 条的 Grype `Fix Version` 均为空（未知/未修复），Anolis 侧无可用升级目标；
- 与首批结论一致：Grype 匹配数据源 `redhat:distro:redhat:8` 给出的修复版本均指向
  RHEL el8_10 勘误，Anolis 8 尚未合入。

### 例外清单

| CVE | 组件 | 已装版本 | 严重度 | 说明 |
| --- | --- | --- | --- | --- |
| CVE-2026-19666 / 19667 / 80274 | bind-export-libs | 32:9.11.36-16.0.1.an8.14 | HIGH | 基础层 |
| CVE-2026-66046 | expat | 2.5.0-2.an8 | HIGH | 与首批 CVE-2026-45186 同组件同版本 |
| CVE-2026-81634 / 82717 | unbound-libs, python3-unbound | 1.16.2-9.0.3.an8 | HIGH | 基础层 |
| CVE-2026-81642 | unbound-libs, python3-unbound | 1.16.2-9.0.3.an8 | CRITICAL | 基础层 |

### 暴露面

- `bind-export-libs` 为 BIND 导出库，仅在被 `named` 等程序加载后才可达；交付镜像
  `CMD` 为 `/usr/bin/apisix init && /usr/bin/apisix init_etcd && openresty -g 'daemon off;'`，
  不启动 `named`；
- `unbound-libs` / `python3-unbound` 同理：镜像内不启动 `unbound`，无 53 端口监听；
  镜像 `EXPOSE` 仅 9080/9443；
- 上述组件均为基础层负载，agw 运行时不加载，无对外入口；`CVE-2026-81642`
  （CRITICAL）需先在本机取得代码执行权限才可能触发，不构成远程可利用面。

### 复核

- 复核期限：2026-10-14（与首批同一日期，便于一次复核清理两批）；
- 到期后删除 `.grype.yaml` 与 `.trivyignore` 中本批条目并重扫；若 Anolis 已发布勘误，
  先升级基础包再删除条目，不得直接延长豁免；
- 条目按「CVE + 组件 + 已装版本」精确匹配，基础包版本一变即失效并重新拦截。

## 扫描器在 Anolis 8.10 上的实际覆盖面（2026-09-20）

镜像 `agw:3.18.0-agw.1`（run `35503276333` / job `106060147486`）的 Trivy 输出：

- `Detected OS family="none" version=""` 与 `WARN Unsupported os` —— Trivy **不识别
  Anolis OS**，不解析 `/var/lib/rpm/rpmdb.sqlite`：对基础层 RPM 的 CVE 既不报出、
  也不否定；
- 该 run 中 Trivy 的命中**全部来自 secret 扫描**，无一条 CVE；
- 结论：RPM 层 CVE 的权威门禁是 Grype（数据源 `redhat:distro:redhat:8`）；
  `.trivyignore` 条目是口径对齐与前向兼容，不能当作交叉验证证据。

## Trivy secret 扫描白名单（2026-09-20）

Trivy 默认启用 secret 扫描。本次命中 2 条 HIGH（规则 `private-key`），均为上游自带文件：

| 镜像内路径 | 性质 | 依据 |
| --- | --- | --- |
| `/usr/local/apisix/conf/cert/ssl_PLACE_HOLDER.key` | Apache APISIX 自带的占位私钥 | 同一 commit 的 `apisix/cli/ops.lua` 默认写入 `ssl_cert_key = "cert/ssl_PLACE_HOLDER.key"`（未配置证书时用于启用 9443 监听）；文件本身在 apache/apisix 公开仓库中 |
| `/usr/local/openresty/pod/lua-resty-rsa-*.pod` | lua-resty-rsa rock 的文档示例密钥 | 随 rock 文档安装，非 AGW 构建产物 |

处置：`build.yml` 的 Trivy 步骤用 `--skip-files` 放行这两条路径（doublestar glob，
同时给出绝对路径与 `**/` 两种写法），**其余路径仍启用 secret 扫描**，新增命中照常
红灯。依据：Trivy 官方文档「Skip Files and Directories」明确该开关对 Secret 扫描器
生效。

运维提示：`ssl_PLACE_HOLDER.key` 是**公开的占位私钥**。若生产环境直接暴露 9443 且未
配置站点证书，TLS 不提供机密性（任何人持有该私钥即可解密或冒充）。AGW 不替换该文件
（改 `ops.lua` 属上游行为变更，超出「仅发行层差异」定位）；运维必须自行下发站点证书，
或关闭 9443 监听。

## 已知缺口

1. **发布镜像不做 CVE 复扫**：`publish.yml` 不对已推送 digest 执行 Grype/Trivy，门禁
   结论来自同一 commit 的 `build.yml`，而发布镜像是重新构建的（digest 不同）。缓解：
   发布清单记录 digest 与 source commit。建议后续在 pullback 校验后追加一步 registry
   直扫、失败即不创建 Release；该改动改变发布语义，需单独评审。
2. **Trivy 在 Anolis 上的 OS 覆盖为零**（见上节）。若需要第二意见，可后续引入支持
   Anolis 的扫描数据源，或对基础镜像单独扫描。
3. **例外清单需按复核期限清理**（当前 2026-10-14，见两批批次记录）。
