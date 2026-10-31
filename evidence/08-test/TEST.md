<!-- 由 `scripts/gen-evidence.py` 生成；不要手工修改。 -->
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
- 默认 `Server: agw`；自定义值生效；`false` 完全抑制；非法值被 schema 拒绝。
- SM2 签名/加密双证书完成真实 NTLSv1.1 握手并通过证书链校验。
- standalone 文件驱动可启动。
- 外置 etcd 下 Admin API 与数据面均可启动并返回配置后的 `Server` 头。

## 供应链

- Syft 生成 CycloneDX JSON。
- Trivy 执行阻断式 HIGH/CRITICAL 漏洞与 secret 扫描。
- openEuler 额外采集非阻断 `dnf updateinfo --security`。
