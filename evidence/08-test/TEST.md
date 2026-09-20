# 测试报告（08-test）

CI 冒烟链（每次构建，GitHub Actions `build.yml`）：
- 基线校验：7 模块 tag commit + Tongsuo master/tag 双校验 + OpenResty tarball SHA256（`make fetch`）
- RPM：Anolis 8.10 容器内 localinstall + `openresty -V` + `apisix version` + 限流 lua 加载
- TLS：`openresty -V` 含 Tongsuo 版本、`ldd` 断言动态链接 Tongsuo、`openssl ciphers` 含 NTLSv1.1 套件
- 国密：`apisix init` + 默认插件表含 `gm` + SM2 双证书 NTLS 真实握手（`test/smoke/gm-ntls-handshake.sh`）
- 镜像：`apisix init`（无 etcd 生成 nginx.conf）+ standalone 文件驱动启动断言 `Server: agw`
- 门禁：去字符 grep（dashboard / apisix-base 等）零命中、Grype/Trivy 阈值

etcd 集群 HA 不在强制测试范围（v1 网关本体可审计优先）。
