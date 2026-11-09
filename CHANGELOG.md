# Changelog

本文件记录 AGW 面向用户的发布变更。格式参考 Keep a Changelog，版本号与
`VERSION` 保持一致；正式镜像标签和 digest 以 GitHub Release 与
`release-manifest.json` 为准。

## [Unreleased]

## [3.19.0-agw.13] - 2026-11-09

### Fixed
- 兼容旧版生成的缺失语言和版本前缀的文档 URL，自动跳转到当前语言的正确路径。

## [3.19.0-agw.12] - 2026-11-09

### Fixed
- 文档目录中的缺失静态文件返回 `404`，不再错误回退到 Dashboard 首页。
- 嵌套文档页面始终加载所属语言的根侧边栏，避免导航栏消失。

## [3.19.0-agw.11] - 2026-11-09

### Fixed
- 修复内置文档的相对链接和图片路径丢失语言、版本或站点前缀的问题。
- 修复点击侧边栏或正文文档链接后显示空白的问题。
- 修复中文文档中的内部页面链接错误跳转到英文文档或静态 Markdown 文件的问题。

## [3.19.0-agw.10] - 2026-11-09

### Added
- 在 Dashboard 内置中英文 AGW 文档，默认中文，并提供本地 `/ui/docs/` 入口。
- 文档构建会过滤社区、用户案例、博客和上游品牌资源，并记录外部图片来源。

### Changed
- Dashboard header 恢复“文档”入口，指向本地文档并保留 Dashboard 当前操作状态。
- 移除镜像体积门禁，文档随基础镜像按构建结果发布。
- 更新 Node 文档/UI builder 基础镜像到当前 `22-alpine` digest。

### Fixed
- 修复 Admin UI 将 `/ui/docs/` 目录请求回退到 Dashboard 首页的问题。

## [3.19.0-agw.9] - 2026-11-05

### Added
- 新增面向发布的 CHANGELOG，并在构建校验和 GitHub Release 流程中检查当前版本条目。

### Changed
- 精简最终镜像层：在 builder 阶段清理 OpenResty 头文件、静态库、pkgconfig 和文档；
  复用已有 OpenResty 二进制，避免最终镜像重复打包。

### Fixed
- 更新 Ubuntu 最终镜像中的 apt 安全补丁，保持基础镜像 pin 不变。

## [3.19.0-agw.7] - 2026-11-05

### Changed
- Dashboard 改为基于上游最新源码的精确 commit 构建。
- 移除上游 Dashboard 文档链接、Logo 和翻译入口。

### Fixed
- zlib 源码下载增加备用源并继续校验 SHA256。
- Trivy 报告未修复漏洞，但仅对可修复漏洞阻断发布。

## [3.19.0-agw.6] - 2026-10-31

### Added
- 增加同 SNI 普通 TLS 与 TLCP/NTLS 双栈支持。
- 内置 AGW 品牌化的 Admin Dashboard，并支持 SSL 双证书展示。

### Fixed
- 修复 SSL 详情页在私钥字段被隐藏时的 Dashboard 错误。
- 修复 Admin UI 的 Server header 和缓存头行为。

## [3.19.0-agw.1] - 2026-10-31

### Added
- 首个 AGW 3.19.0 独立发行版，交付 openEuler 24.03 LTS SP4 和 Ubuntu 24.04
  两个镜像变体。
- 基于 Tongsuo 8.5.0 提供 NTLS/TLCP SM2 双证书支持。
- 支持可配置的 AGW `Server` 头。

[3.19.0-agw.13]: https://github.com/scott-wong/agw/releases/tag/v3.19.0-agw.13
[3.19.0-agw.12]: https://github.com/scott-wong/agw/releases/tag/v3.19.0-agw.12
[3.19.0-agw.11]: https://github.com/scott-wong/agw/releases/tag/v3.19.0-agw.11
[3.19.0-agw.10]: https://github.com/scott-wong/agw/releases/tag/v3.19.0-agw.10
[3.19.0-agw.9]: https://github.com/scott-wong/agw/releases/tag/v3.19.0-agw.9
[3.19.0-agw.7]: https://github.com/scott-wong/agw/releases/tag/v3.19.0-agw.7
[3.19.0-agw.6]: https://github.com/scott-wong/agw/releases/tag/v3.19.0-agw.6
[3.19.0-agw.1]: https://github.com/scott-wong/agw/releases/tag/v3.19.0-agw.1
