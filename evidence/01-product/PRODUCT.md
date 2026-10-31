<!-- 由 `scripts/gen-evidence.py` 生成；不要手工修改。 -->
# AGW 产品说明

- 产品：AGW，独立开放的 API 网关发行版。
- 当前版本：`3.19.0-agw.1`。
- 上游关系：based on Apache APISIX `3.19.0`。
- 交付物：`linux/amd64` 的 openEuler 与 Ubuntu 两个最终容器镜像。
- 不交付：RPM、fpm 中间包、离线镜像 tar、全局 `<版本>` 或 `latest` 标签。
- 运行用户：继承基础镜像默认用户；当前为 `root`，Nginx worker 为 `nobody`。
- etcd：外置部署，由使用方提供兼容版本；镜像不捆绑 etcd。
- TLS：Tongsuo `8.5.0` 动态链接，启用 NTLS/国密双证书能力。
- 品牌头：`apisix.server_header` 缺省 `agw`，自定义字符串生效，`false` 抑制。

兼容承诺仅覆盖上游 APISIX `3.19.0` 的协议与 Admin API 行为，以及本仓文档明确
列出的发行层差异。
