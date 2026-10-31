<!-- 由 `scripts/gen-evidence.py` 生成；不要手工修改。 -->
# 安全门禁

## 阻断项

- Trivy `v0.76.1` 是唯一阻断式漏洞与 secret 扫描器。
- 级别固定为 `HIGH,CRITICAL`，命中即失败。
- 仅跳过两个上游公开占位文件：
  - `/usr/local/apisix/conf/cert/ssl_PLACE_HOLDER.key`
  - `lua-resty-rsa` rock 的 `.pod` 文档示例密钥
- Syft `v1.51.1` 只生成 CycloneDX SBOM，不承担门禁决策。

## 覆盖面

| 变体 | Trivy OS 覆盖 | 补充证据 |
|---|---|---|
| openEuler 24.03 LTS SP4 | `unsupported`，不解析 openEuler RPM 漏洞 | 镜像内 `dnf updateinfo --security`，非阻断 |
| Ubuntu 24.04 | 使用 Trivy Ubuntu 漏洞库 | Trivy 报告 |

`unsupported` 不等于无漏洞，也不等于漏洞已清零。openEuler 的安全公告统计必须与
Trivy 结论分开陈述。AGW 不对标 OpenSSL 的 CVE 修复状态；发布清单记录
`tongsuoCveParity: not-audited`。

## 证据位置

每个 workflow 上传 SBOM、Trivy SARIF、Trivy 文本报告和构建事实。正式发布清单记录
被提升镜像的精确 digest、SBOM SHA256、基础镜像 digest 和 workflow run URL。
