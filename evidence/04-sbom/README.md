<!-- 由 `scripts/gen-evidence.py` 生成；不要手工修改。 -->
# SBOM 归档策略

每个变体在 CI 中由 Syft `v1.51.1` 生成 CycloneDX JSON：

- `agw-3.19.0-agw.4-openeuler.cyclonedx.json`
- `agw-3.19.0-agw.4-ubuntu.cyclonedx.json`

运行 SBOM 保存在对应 GitHub Actions artifact 中；正式发布时由 `publish.yml`
重新生成并作为 GitHub Release 附件上传。仓库不再提交多 MB、会随基础镜像和 CI run
变化的 SBOM 副本，避免用户把历史文件误认为当前镜像事实。
