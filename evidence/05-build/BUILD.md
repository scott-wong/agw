<!-- 由 `scripts/gen-evidence.py` 生成；不要手工修改。 -->
# 构建链

`packaging/docker/Dockerfile` 有两个 builder 和两个 final stage：

```text
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

APISIX 源码发布包不包含已构建的 Admin UI。构建过程从固定 SHA256 的官方
`apisix_3.19.0-0_amd64.deb` 中只提取 `/usr/local/apisix/ui`，不安装官方包内的
OpenResty 或 APISIX 运行时。

final stage 只复制运行目录，不带编译器、头文件、静态库或包管理器缓存。私有库通过
RPATH 定位，不设置全局 `LD_LIBRARY_PATH`，避免污染 `dnf`、`git` 等系统工具使用的
OpenSSL ABI。

openEuler RPM 依赖优先从境外 XTOM 镜像获取，ACCUM 回退，官方源最后；RPM 仍启用
openEuler GPG 校验。GitHub Actions 使用 GHA BuildKit 缓存保存已验证的 builder
阶段，源码归档由 `actions/cache` 保存。
