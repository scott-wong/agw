# 安全扫描（06-security）

## CI 门禁（GitHub Actions）

`.github/workflows/build.yml` 与 `.github/workflows/publish.yml` 均执行：

- Syft 生成 RPM 与镜像 CycloneDX SBOM；
- Grype 镜像扫描（`-c .grype.yaml`），HIGH 及以上失败即红灯；
- Trivy 镜像扫描（自动加载仓库根 .trivyignore），HIGH/CRITICAL 失败即红灯；
- SBOM、扫描报告与门禁结果随 Actions artifact 归档。

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

AGW `build.yml` 对同一基线重新扫描的结论：本批 19 个 CVE 全部复现一致，例外按登记
继续保持（Trivy 对同镜像仍未报出）；同一 run 另新增 7 个 CVE，按第二批登记，见文末。
扫描报告（SARIF/SBOM）随 Actions run 归档，run URL 由发布清单 `workflowRun` 字段记录。

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
退出码 2，报出 10 条 HIGH/CRITICAL；Trivy 步骤在该 job 内未执行（串行且未加
`always()`，属预期行为，补齐例外后需以新 run 复验 Trivy 结果）。

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
