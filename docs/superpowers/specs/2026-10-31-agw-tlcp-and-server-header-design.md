# AGW TLCP 双栈与 Server Header 设计

## 目标

让 AGW 镜像原生支持同一端口、同一 SNI 下普通 TLS 与 TLCP，并修复镜像冒烟中
`server_header` 自定义值不稳定的问题。

## 范围

- Tongsuo `enable-ntls` 作为 TLCP 1.1（GB/T 38636-2020）协议栈。
- APISIX `gm` 插件接受一个 SM2 签名证书、一个 SM2 加密证书，以及一个可选的
  普通 TLS 证书。
- 同一 SSL 对象中，`certs[1]`/`keys[1]` 为 SM2 签名对，`certs[2]`/`keys[2]`
  为普通 TLS 对，`cert`/`key` 为 SM2 加密对。
- 镜像冒烟必须覆盖普通 TLS、TLCP 静态 ECC 套件、TLCP ECDHE 严格编码和
  普通 HTTPS 回归。
- `server_header` 测试不再依赖宿主机挂载文件权限，并显式拒绝 worker 初始化错误。

## 非目标

- 不新增 TLCP 专用监听端口。
- 不修改 Tongsuo 的协议实现。
- 不承诺 Chrome、Edge、Firefox 或 Safari 原生支持 TLCP；这些客户端仍需国密
  浏览器或 TLCP 测试客户端。
- 本次不以第三方浏览器完成互操作认证；自动化以 Tongsuo 严格 TLCP 客户端验证。

## 方案

1. 新增 APISIX `gm.lua` 跟踪补丁，允许 `gm: true` 的 SSL 对象拥有两个以上
   `certs`/`keys`。签名对用于 TLCP，后续证书对通过 `ngx.ssl.set_cert()` 和
   `ngx.ssl.set_priv_key()` 安装为普通 TLS 证书。
2. 构建时依次应用所有跟踪补丁，并断言双栈补丁标记存在。
3. 新增 APISIX 级冒烟：容器内生成 CA、SM2 签名/加密证书和 P-256 普通证书，
   写入 standalone SSL 对象，启动 APISIX 后分别执行普通 TLS 与 TLCP 握手。
4. 冒烟夹具从只读 `/smoke` 挂载复制到镜像内并显式设为 `0644`，避免 Nginx
   `nobody` worker 无法读取宿主机 `0600` 文件；同时检查 error log 中不存在
   `init_worker_by_lua error`。

## 约束

- 保持两个发行版各自构建，不跨发行版复制运行时。
- P-256 普通证书仅用于自动化测试，不作为默认生产证书。
- TLCP 证书必须满足签名证书 `digitalSignature`、加密证书 `keyEncipherment`。
- 普通 TLS 与 TLCP 共用同一 SNI 和监听端口。

