# 发布渠道只保留 GitHub

AGW 的构建、镜像分发与发布记录全部落在 GitHub：GitHub Actions 跑构建与门禁，
GHCR 托管镜像，GitHub Releases 承载 RPM、SBOM 与发布清单。不再接入任何其他
制品库或平台流水线。

理由是公开项目需要外部使用者能够从单一入口复现"某个版本对应哪次构建、哪个
镜像 digest、哪个 RPM 哈希"。分散到多个平台会迫使使用者拼凑证据链，也让仓库内的
workflow 不得不引用外部共享层，从而在公开仓库里留下内部依赖。

## Consequences

- `.github/workflows/` 必须自洽：不引用任何跨仓 workflow 或 composite action。
- 镜像标签为 `<版本>` / `<上游版本>` / `latest`，发布以 tag `v<版本>` 触发；
  `<版本>` 与 tag 一经发布不可移动，需变更时 bump `VERSION`。
- 任何"多平台同步发布"的需求都意味着重新评估本决策，而不是顺手加一条推送。
