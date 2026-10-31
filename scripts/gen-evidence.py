#!/usr/bin/env python3
"""Generate the source-controlled AGW evidence documents.

The generated files are deterministic and are checked by `make verify`.
Run `make evidence` after changing VERSION, scripts/baseline.env, patches, or
modules.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parent.parent
EVIDENCE = ROOT / "evidence"
BASELINE = ROOT / "scripts" / "baseline.env"
VERSION_FILE = ROOT / "VERSION"
RATIO_FILE = EVIDENCE / "09-ip" / "self-developed-ratio.json"

GENERATED = "<!-- 由 `scripts/gen-evidence.py` 生成；不要手工修改。 -->"

MODULES = (
    (
        "ngx_multi_upstream_module",
        "NGX_MULTI_UPSTREAM_MODULE_REPO",
        "NGX_MULTI_UPSTREAM_MODULE_TAG",
        "NGX_MULTI_UPSTREAM_MODULE_COMMIT",
    ),
    (
        "apisix-nginx-module",
        "APISIX_NGINX_MODULE_REPO",
        "APISIX_NGINX_MODULE_TAG",
        "APISIX_NGINX_MODULE_COMMIT",
    ),
    (
        "wasm-nginx-module",
        "WASM_NGINX_MODULE_REPO",
        "WASM_NGINX_MODULE_TAG",
        "WASM_NGINX_MODULE_COMMIT",
    ),
    (
        "lua-var-nginx-module",
        "LUA_VAR_NGINX_MODULE_REPO",
        "LUA_VAR_NGINX_MODULE_TAG",
        "LUA_VAR_NGINX_MODULE_COMMIT",
    ),
    (
        "mod_dubbo",
        "MOD_DUBBO_REPO",
        "MOD_DUBBO_TAG",
        "MOD_DUBBO_COMMIT",
    ),
    (
        "lua-resty-events",
        "LUA_RESTY_EVENTS_REPO",
        "LUA_RESTY_EVENTS_TAG",
        "LUA_RESTY_EVENTS_COMMIT",
    ),
    (
        "ngx_http_ffi_client",
        "NGX_HTTP_FFI_CLIENT_REPO",
        "NGX_HTTP_FFI_CLIENT_TAG",
        "NGX_HTTP_FFI_CLIENT_COMMIT",
    ),
)


def load_env(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
            value = value[1:-1]
        values[key] = value
    return values


def source_ratio() -> dict[str, Any]:
    patch_added = 0
    for patch in sorted((ROOT / "patches").rglob("*.patch")):
        for line in patch.read_text(encoding="utf-8").splitlines():
            if line.startswith("+") and not line.startswith("+++"):
                patch_added += 1

    module_extensions = {
        ".c",
        ".h",
        ".cpp",
        ".hpp",
        ".java",
        ".xml",
        ".go",
        ".rs",
        ".py",
        ".sh",
    }
    module_lines = 0
    for path in sorted((ROOT / "modules").rglob("*")):
        if path.is_file() and path.suffix in module_extensions:
            module_lines += len(path.read_text(encoding="utf-8").splitlines())

    source_root = ROOT / "build" / "src"
    if not source_root.is_dir():
        raise RuntimeError("build/src 缺失；先执行 make fetch")
    denominator = 0
    for path in sorted(source_root.rglob("*")):
        if path.is_file() and path.suffix in {".lua", ".c", ".h"}:
            denominator += len(path.read_text(encoding="utf-8", errors="replace").splitlines())
    if denominator == 0:
        raise RuntimeError("APISIX 源码行数分母为 0")

    numerator = patch_added + module_lines
    return {
        "numerator": numerator,
        "numerator_detail": {
            "vendor_patch_added_lines": patch_added,
            "module_code_lines": module_lines,
        },
        "denominator": denominator,
        "ratio": round(numerator / denominator, 6),
    }


def table_row(*cells: object) -> str:
    return "| " + " | ".join(str(cell) for cell in cells) + " |"


def generated_documents(
    env: dict[str, str], version: str, ratio: dict[str, Any]
) -> dict[Path, str]:
    upstream = version.split("-", 1)[0]
    module_rows = "\n".join(
        table_row(name, env[tag], f"`{env[commit]}`")
        for name, _repo, tag, commit in MODULES
    )
    ratio_json = {
        "product": "AGW",
        "version": version,
        "numerator": ratio["numerator"],
        "numerator_detail": ratio["numerator_detail"],
        "denominator": ratio["denominator"],
        "denominator_detail": (
            f"Apache APISIX {env['APISIX_TAG']} 基线源码行数（lua/c/h）"
        ),
        "ratio": ratio["ratio"],
    }

    documents: dict[Path, str] = {}
    documents[EVIDENCE / "README.md"] = f"""{GENERATED}
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
"""

    documents[EVIDENCE / "01-product" / "PRODUCT.md"] = f"""{GENERATED}
# AGW 产品说明

- 产品：AGW，独立开放的 API 网关发行版。
- 当前版本：`{version}`。
- 上游关系：based on Apache APISIX `{upstream}`。
- 交付物：`linux/amd64` 的 openEuler 与 Ubuntu 两个最终容器镜像。
- 不交付：RPM、fpm 中间包、离线镜像 tar、全局 `<版本>` 或 `latest` 标签。
- 运行用户：继承基础镜像默认用户；当前为 `root`，Nginx worker 为 `nobody`。
- etcd：外置部署，由使用方提供兼容版本；镜像不捆绑 etcd。
- TLS：Tongsuo `{env['TONGSHUO_VERSION']}` 动态链接，启用 TLCP/NTLS
  双证书能力，并支持同一 SNI 下普通 TLS 与 TLCP 双栈。
- 品牌头：`apisix.server_header` 缺省 `agw`，自定义字符串生效，`false` 抑制。
- Admin UI：内置 APISIX Admin UI 静态资源，入口位于 Admin API 的 `/ui/`。

兼容承诺仅覆盖上游 APISIX `{upstream}` 的协议与 Admin API 行为，以及本仓文档明确
列出的发行层差异。
"""

    documents[EVIDENCE / "02-source" / "BASELINE.md"] = f"""{GENERATED}
# 基线来源

唯一事实源是 `scripts/baseline.env`。`make fetch` 会校验 tag/commit、源码归档
SHA256、基础镜像 digest，然后解压 APISIX 到 `build/src/`。

## 上游与运行时

| 项 | 版本/tag/口径 | commit 或 SHA256 |
|---|---|---|
{table_row("APISIX", env["APISIX_TAG"], f"`{env['APISIX_COMMIT']}`")}
{table_row("APISIX Admin UI", env["APISIX_UI_DEB_VERSION"], f"`{env['APISIX_UI_DEB_SHA256']}`")}
{table_row("OpenResty", env["OPENRESTY_VERSION"], f"`{env['OPENRESTY_COMMIT']}`")}
{table_row("Tongsuo", env["TONGSHUO_VERSION"], f"`{env['TONGSHUO_COMMIT']}`")}
{table_row("Tongsuo/OpenSSL 内核", env["TONGSHUO_OPENSSL_VERSION"], "-")}
{table_row("API7 runtime 口径", env["BUILD_TOOLS_TAG"], f"`{env['BUILD_TOOLS_COMMIT']}`")}
{table_row("PCRE2", env["PCRE2_VERSION"], f"`{env['PCRE2_COMMIT']}`")}
{table_row("zlib", env["ZLIB_VERSION"], f"`{env['ZLIB_SHA256']}`")}
{table_row("LuaRocks", env["LUAROCKS_VERSION"], f"`{env['LUAROCKS_SHA256']}`")}
{table_row("wasmtime C API", env["WASMTIME_C_API_VERSION"], f"`{env['WASMTIME_C_API_SHA256']}`")}

## 运行时模块

| 模块 | tag | commit |
|---|---|---|
{module_rows}

另以 `lua-resty-limit-traffic {env['LUA_RESTY_LIMIT_TRAFFIC_TAG']}` 替换
OpenResty bundle 中的同名组件。

## 基础镜像

| 变体 | 固定引用 |
|---|---|
{table_row("openEuler", f"`{env['OPENEULER_BASE_REF']}`")}
{table_row("Ubuntu", f"`{env['UBUNTU_BASE_REF']}`")}
{table_row("测试 etcd", f"`{env['ETCD_TEST_IMAGE']}@{env['ETCD_TEST_IMAGE_DIGEST']}`")}
"""

    documents[EVIDENCE / "03-license" / "LICENSES.md"] = f"""{GENERATED}
# 许可证与归属

- Apache APISIX `{env['APISIX_TAG']}`：Apache License 2.0。
- APISIX Admin UI 静态资源：来自官方 `{env['APISIX_UI_DEB_NAME']}`，Apache License 2.0。
- OpenResty `{env['OPENRESTY_VERSION']}`、Tongsuo `{env['TONGSHUO_VERSION']}`、
  PCRE2、zlib、LuaRocks 与运行时模块：以各自源码归档内 LICENSE/NOTICE 为准。
- 最终镜像保留 APISIX 与 OpenResty 目录内的上游许可证、NOTICE 和第三方归属文件。
- 本仓自行编写的构建与验证脚本按仓库根 `LICENSE`（Apache-2.0）分发。
- 对外只使用关系性表述 `based on Apache APISIX`，不以 Apache APISIX 名义发布。

CycloneDX SBOM 会记录实际编目的组件和版本；许可证扫描的权威输出以对应 CI run 的
SBOM artifact 为准。
"""

    documents[EVIDENCE / "04-sbom" / "README.md"] = f"""{GENERATED}
# SBOM 归档策略

每个变体在 CI 中由 Syft `{env['SYFT_VERSION']}` 生成 CycloneDX JSON：

- `agw-{version}-openeuler.cyclonedx.json`
- `agw-{version}-ubuntu.cyclonedx.json`

运行 SBOM 保存在对应 GitHub Actions artifact 中；正式发布时由 `publish.yml`
重新生成并作为 GitHub Release 附件上传。仓库不再提交多 MB、会随基础镜像和 CI run
变化的 SBOM 副本，避免用户把历史文件误认为当前镜像事实。
"""

    documents[EVIDENCE / "05-build" / "BUILD.md"] = f"""{GENERATED}
# 构建链

`packaging/docker/Dockerfile` 有两个 builder 和两个 final stage：

```text
openeuler-builder -> openeuler-final
ubuntu-builder    -> ubuntu-final
```

每个 builder 在目标发行版内独立完成：

1. 安装构建依赖；
2. 从已校验归档构建 PCRE2 `{env['PCRE2_VERSION']}` 与 zlib `{env['ZLIB_VERSION']}`；
3. 构建 Tongsuo `{env['TONGSHUO_VERSION']}`，启用 `enable-ntls`；
4. 按 API7 runtime `{env['BUILD_TOOLS_TAG']}` 口径构建 OpenResty
   `{env['OPENRESTY_VERSION']}`；
5. 安装 LuaRocks `{env['LUAROCKS_VERSION']}`，构建 APISIX 依赖并安装
   APISIX `{env['APISIX_TAG']}`。

APISIX 源码发布包不包含已构建的 Admin UI。构建过程从固定 SHA256 的官方
`{env['APISIX_UI_DEB_NAME']}` 中只提取 `/usr/local/apisix/ui`，不安装官方包内的
OpenResty 或 APISIX 运行时。

final stage 只复制运行目录，不带编译器、头文件、静态库或包管理器缓存。私有库通过
RPATH 定位，不设置全局 `LD_LIBRARY_PATH`，避免污染 `dnf`、`git` 等系统工具使用的
OpenSSL ABI。

openEuler RPM 依赖优先从境外 XTOM 镜像获取，ACCUM 回退，官方源最后；RPM 仍启用
openEuler GPG 校验。GitHub Actions 使用 GHA BuildKit 缓存保存已验证的 builder
阶段，源码归档由 `actions/cache` 保存。
"""

    documents[EVIDENCE / "06-security" / "SECURITY.md"] = f"""{GENERATED}
# 安全门禁

## 阻断项

- Trivy `{env['TRIVY_VERSION']}` 是唯一阻断式漏洞与 secret 扫描器。
- 级别固定为 `HIGH,CRITICAL`，命中即失败。
- 仅跳过两个上游公开占位文件：
  - `/usr/local/apisix/conf/cert/ssl_PLACE_HOLDER.key`
  - `lua-resty-rsa` rock 的 `.pod` 文档示例密钥
- Syft `{env['SYFT_VERSION']}` 只生成 CycloneDX SBOM，不承担门禁决策。

## 覆盖面

| 变体 | Trivy OS 覆盖 | 补充证据 |
|---|---|---|
| openEuler 24.03 LTS SP4 | `unsupported`，不解析 openEuler RPM 漏洞 | 镜像内 `dnf updateinfo --security`，非阻断 |
| Ubuntu 24.04 | 使用 Trivy Ubuntu 漏洞库 | Trivy 报告 |

`unsupported` 不等于无漏洞，也不等于漏洞已清零。openEuler 的安全公告统计必须与
Trivy 结论分开陈述。AGW 不对标 OpenSSL 的 CVE 修复状态；发布清单记录
`tongsuoCveParity: {env['TONGSUO_CVE_PARITY']}`。

## 证据位置

每个 workflow 上传 SBOM、Trivy SARIF、Trivy 文本报告和构建事实。正式发布清单记录
被提升镜像的精确 digest、SBOM SHA256、基础镜像 digest 和 workflow run URL。
"""

    documents[EVIDENCE / "07-adaptation" / "MATRIX.md"] = f"""{GENERATED}
# 适配矩阵

| 目标 | 平台 | 状态 |
|---|---|---|
| openEuler 24.03 LTS SP4 | `linux/amd64` | 必需；独立构建与门禁 |
| Ubuntu 24.04 | `linux/amd64` | 必需；独立构建与门禁 |
| aarch64 | 任意 | 当前不承诺 |

两个变体必须在各自发行版内编译和测试，禁止复制另一发行版的运行时。正式发布要求
两个 candidate 的全部构建、回拉、冒烟和 Trivy 门禁通过。
"""

    documents[EVIDENCE / "08-test" / "TEST.md"] = f"""{GENERATED}
# 自动测试

## 静态与基线

- 校验 APISIX、OpenResty、Tongsuo、PCRE2、7 个运行时模块的 tag/commit 与归档哈希。
- 校验 openEuler、Ubuntu、etcd 测试镜像的 index digest。
- 验证跟踪补丁可应用、Lua 语法、workflow YAML、shell 语法与去字符门禁。
- 以 `--check` 验证本目录生成文件与 `VERSION`/基线/补丁/模块事实一致。

## 镜像冒烟

- 最终镜像无 gcc、g++、make。
- 最终镜像不设置全局 `LD_LIBRARY_PATH`。
- OpenResty、APISIX CLI、捆绑 PCRE2/zlib 与 `lua-resty-limit-traffic` 可加载。
- Admin UI 入口与 JavaScript/CSS/SVG 静态资源已打包；`/ui/`、静态资源和 SPA
  fallback 可通过 Admin API 端口访问。
- 默认 `Server: agw`；自定义值生效；`false` 完全抑制；非法值被 schema 拒绝。
- Admin UI 的 SSL 详情页兼容 Admin API 隐藏私钥后缺失的 `keys` 字段。
- 真实 APISIX 进程验证同 SNI 普通 TLS 与 TLCP 双栈。
- TLCP ECC 与 ECDHE strict 的 GCM/CBC 套件完成 NTLSv1.1 握手并通过证书链校验。
- Server Header 冒烟在容器内规范化夹具权限，并拒绝 worker 初始化错误。
- standalone 文件驱动可启动。
- 外置 etcd 下 Admin API 与数据面均可启动并返回配置后的 `Server` 头。

## 供应链

- Syft 生成 CycloneDX JSON。
- Trivy 执行阻断式 HIGH/CRITICAL 漏洞与 secret 扫描。
- openEuler 额外采集非阻断 `dnf updateinfo --security`。
"""

    documents[EVIDENCE / "09-ip" / "SELF_DEVELOPED.md"] = f"""{GENERATED}
# 自研比例

口径只统计本仓原创的 APISIX 跟踪补丁新增行与 `modules/` 代码行，不把上游源码、
构建脚本、文档或生成文件计入分子。

| 项 | 值 |
|---|---|
| 版本 | `{version}` |
| APISIX 补丁新增行 | {ratio['numerator_detail']['vendor_patch_added_lines']} |
| modules 代码行 | {ratio['numerator_detail']['module_code_lines']} |
| 分子 | {ratio['numerator']} |
| 分母：APISIX `{env['APISIX_TAG']}` 源码行（lua/c/h） | {ratio['denominator']} |
| 比例 | {ratio['ratio']:.6f} |

机器可读结果见同目录 `self-developed-ratio.json`，由同一生成器维护。
"""

    documents[EVIDENCE / "10-release" / "RELEASE.md"] = f"""{GENERATED}
# 发布契约

当前版本为 `{version}`，上游版本为 `{upstream}`。正式发布由 tag
`v{version}` 触发 `publish.yml`。

1. 为 openEuler 与 Ubuntu 分别构建并推送 `<版本>-<变体>-candidate`。
2. 两个 candidate 都必须通过回拉、镜像冒烟、外置 etcd、Syft 和 Trivy。
3. 只按 candidate 的精确 digest 提升以下派生标签：
   - `<版本>-openeuler`、`<上游版本>-openeuler`、`latest-openeuler`
   - `<版本>-ubuntu`、`<上游版本>-ubuntu`、`latest-ubuntu`
4. 已存在正式标签禁止移动；需要变更时必须 bump `VERSION`。
5. Release 附件只包含两个 SBOM 和 `release-manifest.json`，不包含 RPM。

本证据目录不维护旧 3.18 RPM 发布记录。当前 3.19 线是否已经发布，以 GitHub
Release、GHCR 精确 digest 和 `release-manifest.json` 为准。
"""

    documents[RATIO_FILE] = json.dumps(ratio_json, ensure_ascii=False, indent=2) + "\n"
    return documents


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--check",
        action="store_true",
        help="只检查生成文件是否最新，不写入磁盘",
    )
    args = parser.parse_args()

    env = load_env(BASELINE)
    version = VERSION_FILE.read_text(encoding="utf-8").strip()
    if not re.fullmatch(r"\d+\.\d+\.\d+-agw\.\d+", version):
        raise RuntimeError(f"VERSION 格式非法: {version}")

    try:
        ratio = source_ratio()
    except RuntimeError as exc:
        print(f"错误: {exc}", file=sys.stderr)
        return 1

    documents = generated_documents(env, version, ratio)
    if args.check:
        drift = []
        for path, expected in sorted(documents.items()):
            actual = path.read_text(encoding="utf-8") if path.exists() else None
            if actual != expected:
                drift.append(path.relative_to(ROOT))
        if drift:
            print("[evidence] 生成文件已过期：", file=sys.stderr)
            for path in drift:
                print(f"  - {path}", file=sys.stderr)
            print("请执行: make evidence", file=sys.stderr)
            return 1
        print(f"[evidence] {len(documents)} 个生成文件均为最新")
        return 0

    for path, content in documents.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
    print(f"[evidence] 已更新 {len(documents)} 个文件")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
