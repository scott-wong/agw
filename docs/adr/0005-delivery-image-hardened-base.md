# 交付镜像改用自建加固基础层并以非 root 运行

交付镜像（`packaging/docker/Dockerfile`）的基础层从上游
`registry.openanolis.cn/openanolis/anolisos:8.10` 换成自建加固基线
`ghcr.io/scott-wong/anolis-secure:latest`（Anolis 8.10 + 全量包更新，每周一重建，
默认用户 `appuser:10001`），并且交付镜像**继承该非 root 用户运行**，不再以 root 启动。

理由有三点：其一，上游 Anolis 基础镜像不做全量更新，镜像内 RPM 版本会停在构建点，
供应链门禁每次都要为同一批未修复 CVE 重新评估；自建基线每周重建并自带 Trivy
CRITICAL/HIGH 门禁，等于把"底座是否干净"这件事前置到另一个可审计的流水线。
其二，issue / 下载 / 排障都集中在同一账号下，使用者不必依赖第三方镜像站可用性。
其三，非 root 运行是容器交付的默认预期，镜像此前以 root 启动属于历史遗留。

## 落地方式

- 基础层引用写 `ghcr.io/scott-wong/anolis-secure:latest`：`latest` 是该上游唯一的
  滚动标签，但**漂移必须可见**，因此 `scripts/baseline.env` 登记它当前指向的
  manifest index digest，`scripts/verify-baseline.sh` 在每次构建前强校验；漂移即红灯，
  必须先重扫 Grype/Trivy（含 `.grype.yaml` 例外复核），再更新 digest 并 bump `VERSION`。
- 安装 RPM 必须 root：Dockerfile 在构建阶段显式 `USER root`，装完后切回 `USER 10001:10001`。
  上游加固基线的"下游不要回 root"指的是**运行期**，本仓以最终 `USER` 指令为准。
- APISIX 运行期需要写的路径显式授权：`/usr/local/apisix/conf`（`apisix init` 生成
  `nginx.conf`）、`/usr/local/apisix/logs`（日志、pid、worker socket）与 nginx 的 5 个
  编译默认 temp 路径。授权后在**运行期用户**下真跑一次 `apisix init`，权限不对即构建失败。

## Consequences

- 交付镜像的运行用户是 `10001:10001`。挂载配置/日志卷时必须保证该 uid 可写；
  需要特权端口或额外目录的场景应在部署侧（如 k8s `securityContext`）显式声明，而不是把镜像改回 root。
- RPM 冒烟（`make verify`）仍在官方 `openanolis/anolisos:8.10` 上以 root 安装验证，
  保留"干净上游 EL8 上可装可跑"这一独立数据点；交付镜像则证明"加固基线 + 非 root 可用"。
- 镜像基础层随上游每周重建而前进，`build.yml` 会周期性因 digest 漂移变红——这是
  设计行为（提示复核底座），不是故障；处理流程见 `scripts/baseline.env` 注释。
- 该决策不改变 RPM 交付物本身的内容与安装位置。
