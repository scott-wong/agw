# 构建链路说明（agw）

## 构建链（make build-rpm）

```text
packaging/fpm/Dockerfile                  fpm 打包工具镜像（构建期专用，不进交付物）
packaging/rpm/Dockerfile.runtime          UBI9 内编译 Tongsuo + OpenResty 1.31.1.1 + 7 个模块
                                          （scripts/build-apisix-runtime.sh）
packaging/rpm/Dockerfile.package-runtime  fpm 打包 runtime RPM（兼容/调试目标，不进交付物）
packaging/rpm/Dockerfile.apisix           runtime 树之上构建 APISIX（tag checkout，含 Server 头改写 + gm 插件）
packaging/rpm/Dockerfile.package-apisix   fpm 打包 agw RPM（Release=agw.N）
packaging/docker/Dockerfile               Anolis 8.10 底座 + dnf localinstall rpms/*.rpm
```

`make build-rpm` 仍以独立的 runtime 镜像作为输入，但只把
`agw-<上游版本>-agw.N.el8.x86_64.rpm` 收敛到 `out/`。`package-runtime` 目标仅为
兼容调试流程保留，其 `apisix-runtime` RPM 不属于正式交付物；`build-rpm` 末尾用
断言强制 `out/` 无中间 RPM。

## TLS 基线：Tongsuo（国密）

`scripts/build-apisix-runtime.sh` 的 `install_tongsuo()` 在编译 OpenResty 之前：

1. `git clone --depth 1 --branch master https://github.com/Tongsuo-Project/Tongsuo.git`，
   并断言 `HEAD == scripts/baseline.env` 里登记的 `TONGSHUO_COMMIT`（master 漂移即失败）；
2. `./config shared enable-ntls zlib ... --libdir=lib64`（`--libdir=lib64` 是 RPM 体系要求；
   Tongsuo 已移除的 `enable-camellia` / `enable-seed` / `enable-md2` 不再传入）；
3. `make install_sw install_ssldirs`，并把本仓 `packaging/rpm/conf/tongsuo/openssl.cnf`
   覆盖到 `$OPENSSL_PREFIX/ssl/openssl.cnf`；
4. 断言 `$OPENSSL_PREFIX/bin/openssl version` 以 `Tongsuo: Tongsuo ` 开头。

OpenResty 侧通过 `cc_opt` / `ld_opt` 指向 `$OPENSSL_PREFIX`（`lib64` + rpath）来链接
Tongsuo，**刻意不传 `--with-openssl=`**：nginx 的该选项要求 OpenSSL *源码目录* 并用
nginx 自己的参数重新 Configure（会丢掉 `enable-ntls`）并把 SSL 静态编进 nginx；
上游国密构建口径（`apache/apisix` / `api7/apisix-plugin-gm` 的 gm.md）走的就是
动态链接 + rpath 这条路。`make install` 之后 `assert_tongsuo_linkage()` 用 `ldd` 断言
`nginx` 解析到的 `libssl.so` / `libcrypto.so` 确实来自 `$OPENSSL_PREFIX/lib64/`，
并用 `openssl ciphers -v ECDHE-SM2-SM4-GCM-SM3` 断言套件协议是 `NTLSv1.1`。

`apisix-nginx-module` 的 `nginx-enable_ntls.patch` 受 `TONGSUO_VERSION_NUMBER` 保护
（该宏只由 Tongsuo 头文件提供），因此上面两条断言同时也是国密补丁生效的判据。

## 与上游构建工具的差异

- 中间镜像命名空间 `agw-build/*`；交付镜像本地 tag `agw:<版本>`
- 交付镜像推送到 GHCR `ghcr.io/scott-wong/agw`（tag 触发，见 `.github/workflows/publish.yml`）
- fpm `-n agw`（主 RPM 名 `<产品>-<上游版本>-agw.N`），`--iteration agw.N`
- 基线（模块 tag/commit、OpenResty tarball SHA256、Tongsuo commit）一律取自
  `scripts/baseline.env`，`make fetch` 与运行时脚本各自强制校验
- vendor patch 模块位于 `vendor-patches/0001-…`、`0002-…`（来源 PR 与回退条件见头注）
- `Server: agw` 改写与断言见 `scripts/install-common.sh` + `scripts/smoke-docker.sh`
- `gm` 插件插入 APISIX 默认插件表同样在 `scripts/install-common.sh`（断言 `"gm",`）

## provenance

runtime 镜像内 `/tmp/openresty-commit` = `release-<版本>`（master 模式为 commit SHA，判非发行）；
`/tmp/openresty-version` = 实际 OpenResty 版本。Tongsuo 的版本/commit 由构建日志与
`openssl version` 印记记录。两段产物一致性由同一 run 串行保证。

## CI 与发布

- `.github/workflows/build.yml`：push main / PR / 手工触发，执行 fetch、最终 RPM、
  RPM 与镜像冒烟（含国密握手）、自研比例、SBOM、Grype/Trivy 和去字符门禁。
  供应链门禁的 SBOM 会回填 `evidence/04-sbom/`。
- `.github/workflows/publish.yml`：tag `v*` 或手工触发，推送 GHCR 三标签镜像，
  回拉后重跑 standalone/国密冒烟，再生成发布物 SBOM 与 `release-manifest.json`
  并附到 GitHub Release。
- 两个工作流都是自洽的：不引用任何外部仓库的 reusable workflow / composite action。

## 版本与不可变性

`VERSION` 是唯一事实源（`3.18.0-agw.1` = `<上游版本>-agw.<发行号>`）。
Git tag `v<版本>` 与 GHCR `<版本>` 标签一经发布不可移动；重新发布一律 bump `VERSION`。
