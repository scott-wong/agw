<!-- 由 `scripts/gen-evidence.py` 生成；不要手工修改。 -->
# AGW 证据索引

本目录只保留当前 3.19 双镜像交付仍然有效的证据。所有 Markdown 与自研比例 JSON
均由 `scripts/gen-evidence.py` 生成，事实源为 `VERSION`、`scripts/baseline.env`、
`patches/`、`modules/` 和已校验的 `build/src/`。

更新与校验：

```sh
make fetch
make evidence
make verify
```

`make verify` 会以 `--check` 模式运行生成器；生成文件与事实源不一致时直接失败。
单次 CI 的镜像 digest、SBOM、SARIF、Trivy 和 `dnf updateinfo` 输出保存在对应
GitHub Actions artifact 中，不把大体积、易过期的运行产物提交进仓库。

| 目录 | 内容 |
|---|---|
| `01-product` | 当前产品与交付边界 |
| `02-source` | 上游版本、commit、归档哈希和基础镜像 |
| `03-license` | 分发许可与归属原则 |
| `04-sbom` | SBOM 归档策略 |
| `05-build` | 双发行版镜像构建链 |
| `06-security` | 阻断门禁与实际覆盖面 |
| `07-adaptation` | 支持矩阵 |
| `08-test` | 自动测试与冒烟范围 |
| `09-ip` | 自研比例及计算明细 |
| `10-release` | 当前发布契约和标签规则 |
