# xmlsec1 关闭 RIPEMD160 以适配 Tongsuo

`lua-resty-saml 0.2.5`（`saml-auth` 插件的原生依赖）自带 `xmlsec1-1.2.28`，
默认编译 RIPEMD160 变换，引用 `EVP_ripemd160`。Tongsuo 8.5.0-pre2 的密码库不再
提供该符号（OpenSSL 3.5 内核里 RIPEMD160 已属遗留算法，铜锁直接移除），于是链接
`xmlsec1` 与 `saml.so` 时报 `undefined reference to 'EVP_ripemd160'` 而中断构建。

xmlsec1 对 RIPEMD160 的每处引用都在 `#ifndef XMLSEC_NO_RIPEMD160` 内，其
`configure --disable-ripemd160` 就是置这个宏。但该 rock 的 Makefile 把 configure
参数写死（`CFLAGS="-std=c99" ./configure --with-openssl=... --with-pic
--disable-crypto-dl --disable-apps-crypto-dl`），命令行上无法追加参数，因此在
`luarocks make` 前用 `CPPFLAGS=-DXMLSEC_NO_RIPEMD160=1` 注入同一个宏。

## Considered Options

- **改用 OpenSSL 1.1.1（上游 OpenResty 自带）**：被否。那就没有 NTLS/国密套件，
  与本项目的 TLS 基线冲突。
- **升级/替换 xmlsec1**：被否。它由 `lua-resty-saml` 的 rock 固定拉取
  `api7/xmlsec-fork` 的 1.2.28 tarball，替换版本等于自带一份 rock 与补丁，
  维护成本和审计面都大于关闭一个遗留摘要算法。
- **放弃 `saml-auth`（从 rockspec 里删掉该依赖）**：被否。`saml-auth` 在 APISIX
  默认插件表内，删依赖会让每次启动都记一条插件加载失败，且无谓损失上游能力。
- **在 Tongsuo 里补回 RIPEMD160**：被否。TLS 基线不得为了一个 XML 摘要算法改动。

## Consequences

- `saml-auth` 其余能力（断言解析、签名校验、属性映射）不受影响；仅使用
  RIPEMD160 的 XML 签名/摘要不可用——该算法在 SAML 实践中罕见，且早已不被推荐。
- 该宏只出现在 `scripts/install-common.sh` 的 `luarocks make` 一行，作用域限本次
  依赖构建；回归判据是 APISIX 能加载 `saml-auth`（standalone 冒烟里的
  `apisix init` + 插件加载）。
- 若上游 `lua-resty-saml` 换用支持 OpenSSL 3 的 xmlsec1，或 Tongsuo 恢复该符号，
  本条即应删除并复核。
