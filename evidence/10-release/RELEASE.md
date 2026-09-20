# 发布记录（10-release）

正式发布流程：在 GitHub 仓库打 tag `v<版本>` 触发 `publish.yml`，校验
`RELEASE_VERSION` 与 `VERSION` 一致 -> 构建并验证候选镜像（Anolis 8.10 回拉 +
`apisix version` + `smoke-docker.sh`）-> 推送 `ghcr.io/scott-wong/agw` ->
按 `<版本>` / `<上游版本>` / `latest` 打标 -> 生成镜像 SBOM 与发布清单 ->
创建 GitHub Release 并上传 RPM、SBOM、发布清单。`<版本>` 与 Git tag 不可移动，
需要变更时 bump `VERSION`。

| 版本 | Git tag | 镜像 | 发布渠道/状态 |
|------|---------|------|---------------|
| 3.18.0-agw.1 | `v3.18.0-agw.1` | `ghcr.io/scott-wong/agw:3.18.0-agw.1` | GitHub Releases + GHCR，首发（待首次流水线验证） |

唯一发布渠道为 GitHub（Actions + GHCR + Releases）；无其他制品库参与。
