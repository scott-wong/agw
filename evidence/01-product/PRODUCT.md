# AGW 产品说明（01-product）

AGW：独立开放的 API 网关发行版，基于 Apache APISIX，面向自托管与独立部署场景。
- 版本：`3.18.0-agw.2`（`<上游版本>-agw.N`）
- 交付物：最终 RPM（EL8）+ Anolis 8.10 Docker 镜像（`ghcr.io/scott-wong/agw`）；不交付 `apisix-runtime` / `apisix` 中间 RPM
- 镜像基础层：自建加固基线 `ghcr.io/scott-wong/anolis-secure:latest`（digest 锁定在 `scripts/baseline.env`），以非 root 用户 `10001:10001` 运行（见 `docs/adr/0005`）
- 兼容定位：仅承诺"与上游 APISIX 3.18 同版本协议与 Admin API 兼容"；不承诺商业增强
- TLS：构建期以 Tongsuo（铜锁）替代 OpenSSL，提供国密 NTLS / SM2 双证书能力
- etcd：外置（用户自备，兼容 3.5.x / 3.6），发布物不捆绑
- 强制组合：Anolis 8.10 × x86_64；aarch64 不承诺
