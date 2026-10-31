<!-- 由 `scripts/gen-evidence.py` 生成；不要手工修改。 -->
# 发布契约

当前版本为 `3.19.0-agw.4`，上游版本为 `3.19.0`。正式发布由 tag
`v3.19.0-agw.4` 触发 `publish.yml`。

1. 为 openEuler 与 Ubuntu 分别构建并推送 `<版本>-<变体>-candidate`。
2. 两个 candidate 都必须通过回拉、镜像冒烟、外置 etcd、Syft 和 Trivy。
3. 只按 candidate 的精确 digest 提升以下派生标签：
   - `<版本>-openeuler`、`<上游版本>-openeuler`、`latest-openeuler`
   - `<版本>-ubuntu`、`<上游版本>-ubuntu`、`latest-ubuntu`
4. 已存在正式标签禁止移动；需要变更时必须 bump `VERSION`。
5. Release 附件只包含两个 SBOM 和 `release-manifest.json`，不包含 RPM。

本证据目录不维护旧 3.18 RPM 发布记录。当前 3.19 线是否已经发布，以 GitHub
Release、GHCR 精确 digest 和 `release-manifest.json` 为准。
