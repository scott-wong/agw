# SBOM 归档（04-sbom）

本目录由 GitHub Actions 生成，包含最终 RPM 与发布镜像的 CycloneDX SBOM。
`build.yml` 将 RPM SBOM 回填到本目录并以 artifact 归档；`publish.yml` 对
GHCR 发布镜像再次生成 SBOM 并随 GitHub Release 附件发布。权威归档即本目录
与对应 GitHub Actions run 记录（run URL 由发布清单 `workflowRun` 字段给出）。
