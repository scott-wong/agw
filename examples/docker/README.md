# AGW Docker Compose 示例

这里提供两套部署示例：

- `agw-single`：单节点 AGW + 单节点 etcd
- `agw-ha`：三节点 AGW + 三节点 etcd

两套示例共用 `../etcd-init` 和 `../wasm`，请从仓库复制整个 `examples/docker`，
不要只复制其中一个子目录。

示例使用 host 网络。默认监听 `80/443`，rootless Podman 环境（例如
`ip_unprivileged_port_start=1024`）应把 `AGW_HTTP_PORT` / `AGW_HTTPS_PORT`
改为 `8080` / `8443`。示例不包含 `init-etcd.sh`；etcd 认证由 Compose 中的
一次性 `etcd-init` 服务完成。

## 前置条件

- Docker Compose v2，或 Podman + Podman Compose
- 能拉取 `AGW_IMAGE` 和 `ETCD_IMAGE`
- 宿主机没有占用 80/443、2379/2380、9180、9091
- 三节点模式需要三台主机之间互通 2379/2380，并且 `NODE_IP` 使用节点实际可路由地址

## 单节点

```bash
cd agw-single
cp .env.example .env
```

编辑 `.env`，至少填写：

```dotenv
AGW_ADMIN_KEY=<set-a-strong-admin-key>
ETCD_ROOT_PASSWORD=<set-a-strong-etcd-password>
```

宿主机上的配置文件必须能被容器内 `nobody` worker 读取；在严格 umask 或打包传输
后先执行：

```bash
chmod 0644 agw_conf/config*.yaml
chmod -R a+rX site
```

启动：

```bash
docker compose up -d
```

`etcd-init` 会等待 etcd 可连接，创建 root 用户并启用认证；`agw` 随后启动。

验证：

```bash
set -a
. ./.env
set +a
curl 'http://[::1]:9180/ui/'
curl "http://127.0.0.1:${AGW_HTTP_PORT}/hi/"
```

rootless Podman 示例：

```bash
sed -i 's/^AGW_HTTP_PORT=.*/AGW_HTTP_PORT=8080/' .env
sed -i 's/^AGW_HTTPS_PORT=.*/AGW_HTTPS_PORT=8443/' .env
podman-compose up -d
curl http://127.0.0.1:8080/hi/
```

## 三节点

在三台主机上分别复制 `agw-ha`，并且每个节点都填写相同的
`NODE1_IP` / `NODE2_IP` / `NODE3_IP` 和相同的两个 secret：

```dotenv
NODE_NAME=etcd-1          # etcd-2 / etcd-3 on the other hosts
NODE_IP=192.168.1.10      # this host's address
NODE1_IP=192.168.1.10
NODE2_IP=192.168.1.11
NODE3_IP=192.168.1.12
```

先在三台主机启动 etcd：

```bash
docker compose up -d etcd
```

只在一台节点执行一次认证初始化：

```bash
docker compose --profile init run --rm etcd-init
```

Podman 环境把命令替换为 `podman-compose --profile init run --rm etcd-init`。

然后三台主机启动 AGW：

```bash
docker compose up -d agw
```

每个 AGW 都会把三台 etcd 地址都作为配置中心端点，避免单台 etcd 故障时失去
配置访问。

不要在正常启动命令中启用 `init` profile；认证状态保存在 etcd 集群中，由一次性
初始化服务写入。重新执行初始化服务是幂等的：如果认证已经启用且密码正确，它会直接
返回成功。

## 可选 WAF

基础 Compose 不要求 WASM 文件。需要使用 Coraza WAF 时，在 `examples/docker`
目录把 WASM 放到共享目录：

```bash
curl -fL \
  -o wasm/waf.wasm \
  https://github.com/scott-wong/coraza-proxy-wasm/releases/download/v0.8.0/coraza-proxy-wasm.wasm
```

上游 release 资产名仍是 `coraza-proxy-wasm.wasm`，保存到本地时统一命名为
`waf.wasm`。然后进入示例目录，确保配置文件可由容器 worker 读取，并使用 overlay
启动：

```bash
cd agw-single
chmod 0644 agw_conf/config.waf.yaml
docker compose -f docker-compose.yml -f docker-compose.waf.yml up -d
./scripts/apply-global-rules.sh
```

HA 的 WAF overlay 用法相同。`waf.wasm` 是唯一约定的文件名；配置中的挂载路径为
`/usr/local/apisix/conf/waf.wasm`。

## 说明

- `AGW_IMAGE` 默认使用 `latest-openeuler`，便于跟随当前发布线；生产部署应固定为
  具体版本标签或 digest。
- 基础配置的 `ssl.enable` 为 `false`；需要 HTTPS 时自行挂载证书、开启 SSL，并设置
  `AGW_HTTPS_PORT`。
- `etcd_data`、`.env`、`tls` 中的实际文件和 `waf.wasm` 不进入版本控制。
- `apply-global-rules.sh` 只应用于已启用 WAF overlay 的部署，不属于启动初始化流程。
