<!-- 由 `scripts/gen-evidence.py` 生成；不要手工修改。 -->
# 构建链

`packaging/docker/Dockerfile` 有一个 Admin UI builder、两个发行版 builder 和两个
final stage：

```text
dashboard-builder -> both final stages
openeuler-builder -> openeuler-final
ubuntu-builder    -> ubuntu-final
```

每个 builder 在目标发行版内独立完成：

1. 安装构建依赖；
2. 从已校验归档构建 PCRE2 `10.49` 与 zlib `1.3.2`；
3. 构建 Tongsuo `8.5.0`，启用 `enable-ntls`；
4. 按 API7 runtime `apisix-runtime/1.4.2` 口径构建 OpenResty
   `1.31.8.1`；
5. 安装 LuaRocks `3.12.0`，构建 APISIX 依赖并安装
   APISIX `3.19.0`。

APISIX 源码发布包不包含已构建的 Admin UI。CI 在每次 workflow 开始时只解析一次
`apache/apisix-dashboard` master HEAD，下载该精确 commit 的源码归档，并由
`dashboard-builder` 使用 Node `22-alpine`、pnpm
`12.16.1` 执行 lint、单测和生产构建。两个镜像变体共享同一
commit；同版本在不同日期重新构建时可使用不同 master。

AGW 源码补丁将页面标题和动态 `document.title` 统一为 `AGW Dashboard`，移除
APISIX Logo/favicon、右上角 Docs、语言菜单翻译 CTA，并保留 SSL 详情页对隐藏私钥
字段的兼容修复。

final stage 只复制运行目录，不带编译器、头文件、静态库或包管理器缓存。私有库通过
RPATH 定位，不设置全局 `LD_LIBRARY_PATH`，避免污染 `dnf`、`git` 等系统工具使用的
OpenSSL ABI。

openEuler RPM 依赖优先从境外 XTOM 镜像获取，ACCUM 回退，官方源最后；RPM 仍启用
openEuler GPG 校验。GitHub Actions 使用 GHA BuildKit 缓存保存已验证的 builder
阶段，源码归档由 `actions/cache` 保存。
