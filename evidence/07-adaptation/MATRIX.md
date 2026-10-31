<!-- 由 `scripts/gen-evidence.py` 生成；不要手工修改。 -->
# 适配矩阵

| 目标 | 平台 | 状态 |
|---|---|---|
| openEuler 24.03 LTS SP4 | `linux/amd64` | 必需；独立构建与门禁 |
| Ubuntu 24.04 | `linux/amd64` | 必需；独立构建与门禁 |
| aarch64 | 任意 | 当前不承诺 |

两个变体必须在各自发行版内编译和测试，禁止复制另一发行版的运行时。正式发布要求
两个 candidate 的全部构建、回拉、冒烟和 Trivy 门禁通过。
