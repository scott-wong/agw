# 发布记录（10-release）

正式发布流程：在 GitHub 仓库打 tag `v<版本>` 触发 `publish.yml`，校验
`RELEASE_VERSION` 与 `VERSION` 一致 -> 构建并验证候选镜像（Anolis 8.10 回拉 +
`apisix version` + `smoke-docker.sh`）-> 推送 `ghcr.io/scott-wong/agw` ->
按 `<版本>` / `<上游版本>` / `latest` 打标 -> 生成镜像 SBOM 与发布清单 ->
创建 GitHub Release 并上传 RPM、SBOM、发布清单。`<版本>` 与 Git tag 不可移动，
需要变更时 bump `VERSION`。

| 版本 | Git tag | 镜像 | 发布渠道/状态 |
|------|---------|------|---------------|
| 3.18.0-agw.1 | `v3.18.0-agw.1` | `ghcr.io/scott-wong/agw:3.18.0-agw.1` | GitHub Releases + GHCR，已发布并完成回拉验证（见下） |

唯一发布渠道为 GitHub（Actions + GHCR + Releases）；无其他制品库参与。

## 发布验证记录（3.18.0-agw.1）

| 项 | 记录 |
|----|------|
| 门禁来源 | `build.yml` run [35506156429](https://github.com/scott-wong/agw/actions/runs/35506156429)，head `08ed5ca`，7/7 job 成功（基线漂移、去字符、自研比例、两段 RPM 链、Anolis 8.10 RPM 冒烟、镜像 standalone + 国密握手、供应链 Grype + Trivy） |
| 发布流水线 | `publish.yml` run [35509208524](https://github.com/scott-wong/agw/actions/runs/35509208524)，job `106074063933`，12/12 step 成功 |
| 源码定位 | commit `08ed5ca0e35a59e1a02db7fc28af249655c46e16`；annotated tag `v3.18.0-agw.1` = `20f163139cd95737ba053e1ed68872ff677b22c7` |
| RPM | `agw-3.18.0-agw.1.el8.x86_64.rpm`，56285321 B，SHA256 `a5786bfd45217254669ba7d77ee14c578581e49d8af6f27dcef75bcd5a649200`（Release 附件重新下载复算，与 `release-manifest.json` 及 GitHub 资产 digest 三方一致） |
| 镜像 | `ghcr.io/scott-wong/agw:3.18.0-agw.1` / `:3.18.0` / `:latest`，三标签同指 digest `sha256:f2dcf016d2e4d5a0e962b5d4bbda990813facfc0364fc802e8c7225e60ea3a12`，平台 `linux/amd64` |
| 回拉断言（CI 内） | `docker pull` → `/etc/os-release` 含 Anolis → `apisix version` → `scripts/smoke-docker.sh`（`apisix init`、standalone 文件驱动启动、`Server: agw`、Tongsuo 链接与 SM2 双证书 NTLS 真握手） |
| 发布附件 | RPM、`agw-3.18.0-agw.1-image.cyclonedx.json`、`release-manifest.json`（Release `v3.18.0-agw.1`） |
| 验证边界 | 开发机为 Darwin arm64 且无 docker/podman，镜像真机行为全部在 GitHub Actions runner 上执行；本机只做了 RPM SHA256 复算与 GHCR 匿名 manifest 复算（未在本地运行容器）。 |
