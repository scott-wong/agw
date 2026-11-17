<!-- 由 `scripts/gen-evidence.py` 生成；不要手工修改。 -->
# 基线来源

长期基线事实源是 `scripts/baseline.env`。`make fetch` 会校验 tag/commit、源码归档
SHA256、基础镜像 digest，然后解压 APISIX 到 `build/src/`。

## 上游与运行时

| 项 | 版本/tag/口径 | commit 或 SHA256 |
|---|---|---|
| APISIX | 3.20.0 | `bc1e687fdb82883f86d1bca9fa4fbd6bb433682b` |
| APISIX Dashboard | `apache/apisix-dashboard:master` | 每次构建解析并记录 commit |
| OpenResty | 1.31.8.1 | `265baf62de60397452f306d61b168ab2c1809d41` |
| Tongsuo | 8.5.0 | `80cfbe3eb194a4d30da90742273c305ad4d096be` |
| Tongsuo/OpenSSL 内核 | 3.5.4 | - |
| API7 runtime 口径 | apisix-runtime/1.4.2 | `6aaa033823d3b041952a1da6360b5d11ccb99c08` |
| PCRE2 | 10.49 | `6f9d7c1373262c541324a16a358785b33ef116cf` |
| zlib | 1.3.2 | `bb329a0a2cd0274d05519d61c667c062e06990d72e125ee2dfa8de64f0119d16` |
| LuaRocks | 3.12.0 | `745e3c5df2f955ecaf60ba1361cfc224564ef7ec210e9a784a3858ae853e9f7c` |
| wasmtime C API | v0.38.1 | `686efb2a47eae17e11897c8e18116b38c1515bc2a74464d4d222c6265d1cff30` |

## 运行时模块

| 模块 | tag | commit |
|---|---|---|
| ngx_multi_upstream_module | 1.4.1 | `1271391a52e947b576ecbfced05d8bedcd22d04f` |
| apisix-nginx-module | 1.20.3 | `fa0559cd8916427183e50db8e5e12a6acf671ac2` |
| wasm-nginx-module | 0.7.0 | `0b4b31d6ecfdbc587e8ea455ed6e920a98aadff1` |
| lua-var-nginx-module | v0.5.3 | `dc04c71e14e8a0407831f9019043d7e6da61b3c3` |
| mod_dubbo | 1.0.2 | `4aabf9448fe4a49ca71009af8e03645ee5dadd15` |
| lua-resty-events | 0.2.0 | `8448a92cec36ac04ea522e78f6496ba03c9b1fd8` |
| ngx_http_ffi_client | v0.1.3 | `ea8374ddf416ee2553a8aff60189310ca1b6b0c0` |

另以 `lua-resty-limit-traffic v1.2.0` 替换
OpenResty bundle 中的同名组件。

## 基础镜像

| 变体 | 固定引用 |
|---|---|
| openEuler | `quay.io/openeuler/openeuler:24.03-lts-sp4@sha256:17c15554be2a5bc46023acb6e04d609d77642b8c20e236e88deb18e41ae4558e` |
| Ubuntu | `ubuntu:24.04@sha256:73b999393d07f2bf65a40373778a44dc9a6d54ad7718d29247d8ff9413c4d6a8` |
| Admin UI builder | `node:22-alpine@sha256:1314fb30ec37592d5845e5a160d522c0e680972aa534549940b8d73bde88481a`（amd64 `sha256:12f54cafa58d0e96554ae05871e29663ff7241836377dc9a7916449b8adb062c`） |
| 测试 etcd | `quay.io/coreos/etcd:v3.5.21@sha256:a3ccd299377af4b9968d8cbaaf9722fe354297f11908f74a846075e1e5f4ee89` |
