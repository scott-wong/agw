# 构建说明（05-build）

正式构建采用“运行时镜像 -> 最终 RPM”链（同一 run 串行完成）：
1. 运行时镜像：从锁定的 OpenResty release tarball（SHA256 校验）+ 7 个锁定模块 + Tongsuo（commit 固定）编译 `/usr/local/openresty`；
2. `agw` RPM：APISIX 3.18.0（tag commit 校验）+ 内嵌 runtime 树，fpm 打包为 `agw-3.18.0-agw.1.el8.x86_64.rpm`（Release `agw.1`）。

`apisix-runtime` 0.0.0-0 与 `apisix` RPM 仅为兼容历史调试流程保留，不进入
`out/`，不属于正式交付物；`build.yml` 对 `out/` 断言只允许最终 `agw-*.rpm`。
构建底座：`packaging/fpm`（打包工具镜像，不进交付物）；Smoke 底座：Anolis 8.10。
每次构建记录 OpenResty provenance stamp（`/tmp/openresty-commit`，release-<版本>），
并在 `scripts/build-apisix-runtime.sh` 内断言 `nginx` 的 `libssl.so` / `libcrypto.so`
解析到 Tongsuo 前缀（`ldd` 硬校验），国密补丁未生效即构建失败。
