# 测试报告（08-test）

CI 冒烟链（每次构建，GitHub Actions `build.yml`）：
- 基线校验：7 模块 tag commit + Tongsuo master/tag 双校验 + OpenResty tarball SHA256（`make fetch`）
- RPM：Anolis 8.10 容器内 localinstall + `openresty -V` + `apisix version` + 限流 lua 加载
- TLS：`openresty -V` 含 Tongsuo 版本、`ldd` 断言动态链接 Tongsuo、`openssl ciphers` 含 NTLSv1.1 套件
- 国密：`apisix init` + 默认插件表含 `gm` + SM2 双证书 NTLS 真实握手（`test/smoke/gm-ntls-handshake.sh`）
- 镜像：`apisix init`（无 etcd 生成 nginx.conf）+ standalone 文件驱动启动断言 `Server: agw`
- 镜像构建期：在运行期用户（`10001:10001`）下真跑 `apisix init`，断言 `conf/` 与 `logs/` 可写（非 root 运行的前置条件）
- 门禁：去字符 grep（dashboard / apisix-base 等）零命中、Grype/Trivy 阈值

etcd 集群 HA 不在强制测试范围（v1 网关本体可审计优先）。

## CI 稳定性修复（2026-09-20）

run `35504679448` 的 RPM 冒烟（job `106064029821`）在 `openresty -V | head` 处随机以
`Error 141` 退出：`set -o pipefail` 下 `head` 读满即关闭管道，写端（openresty / docker）
的后续写入拿到 SIGPIPE，整条管道被判非零。断言内容本身没有变，失败与产物无关。

已把这类「短读 + pipefail」用法换成读完全部输入的等价写法：

- `test/smoke/runtime-smoke.sh`、`scripts/smoke-docker.sh`：`| head -n N` → `| sed -n '1,Np'`
- `scripts/build-apisix-runtime.sh`、`scripts/install-security-tools.sh`：`find ... | head -n 1` → `find ... -print -quit`

门禁强度不变，去掉的是随机失败面（同一 run 的镜像冒烟走同一脚本却通过，即该竞态的实证）。
