# 构建期以 Tongsuo 替代 OpenSSL，且不传 `--with-openssl`

运行时编译时用 Tongsuo（铜锁）替代 OpenSSL，以 `enable-ntls` 提供国密 NTLS
双证书能力。基线锁定 `Tongsuo-Project/Tongsuo` 的 `master` 上某个 commit，而不是
分支名——master 会前进，commit 不会。

关键点是**不给 OpenResty 的 `./configure` 传 `--with-openssl`**：nginx 该选项要求
OpenSSL **源码目录**，会拿 nginx 自己的参数重跑 `Configure`，从而丢掉 `enable-ntls`，
并且把 OpenSSL 静态编入而不便替换。这里改为只通过 `cc_opt` / `ld_opt` 与 rpath 指定
`$OPENSSL_PREFIX`，让 `nginx` 动态链接 Tongsuo 的 `libssl.so` / `libcrypto.so`；
`scripts/build-apisix-runtime.sh` 用 `ldd` 断言链接来源，漂移即构建失败。

## Considered Options

- **给 `./configure` 传 `--with-openssl=$OPENSSL_PREFIX`**：被否。要求源码目录，且会
  用 nginx 参数重跑 `Configure`，`enable-ntls` 失效。
- **继续用 OpenSSL**：被否。拿不到 NTLS/国密套件支持。

## Consequences

- Tongsuo 以动态库形式随运行时镜像分发，`OPENSSL_PREFIX`（默认
  `/usr/local/openresty/tongsuo`，`libdir=lib64`）成为构建契约的一部分。
- 上游 master 前进即触发基线门禁红灯，必须复核国密握手并显式 bump commit。
