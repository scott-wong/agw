# AGW

AGW is an independent, open API gateway distribution built on
[Apache APISIX](https://github.com/apache/apisix). It ships exactly two
deliverables — one RPM and one container image — for a fixed, verifiable
platform baseline, with a Tongsuo-based TLS runtime that provides Chinese
national cryptography (SM2/SM3/SM4, NTLS).

[中文说明（简体）](./README.zh-CN.md)

- Upstream relationship: **based on Apache APISIX**. AGW carries no routing,
  plugin or protocol behavior changes of its own; the differences are all
  distribution-level (see below).
- Guaranteed platform: **Anolis OS 8.10 × x86_64**. Other platforms are not
  tested and not promised.
- Scope of v1: gateway runtime only. The Admin UI, etcd and any enterprise
  add-ons are not part of the deliverables.

## Deliverables

| Artifact | Name | Notes |
|----------|------|-------|
| RPM (EL8) | `agw-3.18.0-agw.1.el8.x86_64.rpm` | the only RPM delivered; no intermediate `apisix-runtime` / `apisix` packages |
| Image | `ghcr.io/scott-wong/agw:3.18.0-agw.1` | tags `3.18.0-agw.1` (immutable), `3.18.0`, `latest` |

Release assets are attached to GitHub Releases, together with a CycloneDX
SBOM of the published image and a `release-manifest.json` that records the
RPM SHA256 and the image digest.

## Baseline

`scripts/baseline.env` is the single source of truth. `make fetch` verifies
every pin against upstream before a build starts, and fails on drift.

| Item | Pin |
|------|-----|
| Gateway | Apache APISIX `3.18.0` @ `0796d9c2cbedb1f8bf8194292ff526599f4fde20` |
| Runtime | OpenResty `1.31.1.1` (release tarball, SHA256 verified) |
| TLS | [Tongsuo](https://github.com/Tongsuo-Project/Tongsuo) `master` @ `540603a3ff952ce00590bca022015feffbfb7597` (tag `8.5.0-pre2`, OpenSSL 3.5.4 core), built with `enable-ntls` |
| Runtime modules | 7 upstream modules, each pinned to a tag + commit |

Both `ngx_multi_upstream_module` and `apisix-nginx-module` patch nginx /
OpenResty bundle sources, which is what makes the OpenResty version a hard
constraint. The pins for OpenResty `1.31.1.1` are carried as vendored patches
under `vendor-patches/` (upstream master + the relevant PR); each `patch.sh`
header records its source PR and the condition for dropping the override.

## Differences from upstream APISIX

| Aspect | Upstream APISIX 3.18.0 | AGW |
|--------|------------------------|-----|
| Response header | `Server: APISIX/<version>` | `Server: agw` (rewritten while packaging; asserted in the standalone smoke test) |
| TLS runtime | official prebuilt OpenResty | OpenResty compiled against Tongsuo, `enable-ntls` |
| GM plugin | opt-in, needs a Tongsuo runtime | `gm` is part of the default plugin list; the image/RPM smoke test performs a real SM2 dual-certificate NTLS handshake |
| Deliverables | deb / rpm / apk / Docker / Helm | RPM (EL8) + Anolis 8.10 image only |
| Admin UI | separate upstream product | not delivered |
| Config store | etcd built-in or external | etcd must be external (3.5.x / 3.6); standalone file-driven mode (`config_provider: yaml`) is supported |

## Chinese national cryptography (GM / NTLS)

The runtime links Tongsuo's `libssl.so.3` / `libcrypto.so.3`, so NTLS with SM2
dual certificates is available out of the box:

```sh
# in the container / on the RPM host
/usr/local/openresty/tongsuo/bin/openssl version
# Tongsuo: Tongsuo 8.5.0-pre2 (Library: Tongsuo 8.5.0-pre2)
```

APISIX's default cipher list does not contain the GM suites, so enable them in
`conf/config.yaml` when you terminate GM TLS:

```yaml
apisix:
  ssl:
    ssl_ciphers: ECDHE-SM2-WITH-SM4-SM3:HIGH:!aNULL:!MD5
```

The `gm` plugin (dual-certificate configuration) is already in the default
plugin list of AGW builds, so per-SNI GM certificates can be managed through the
Admin API as documented upstream in `docs/zh/latest/plugins/gm.md`.

## Repository layout

```text
VERSION                  single source of truth for the version
Makefile                 fetch / build-rpm / build-docker / verify / verify-docker / release-assets / clean
scripts/                 build scripts + baseline.env (baseline source of truth)
vendor-patches/          numbered vendored patch modules (source PR + drop condition in each patch.sh header)
modules/                 AGW-owned modules (empty placeholder in v1; zero self-developed code)
packaging/rpm/           runtime image, final RPM Dockerfiles, fpm input tree and the Tongsuo openssl.cnf
packaging/docker/        Anolis 8.10 delivery image
test/smoke/              smoke assets (limit lua, standalone config, Tongsuo GM handshake, runtime assertions)
evidence/01…10/          evidence pack (authoritative archive; 04-sbom / 09-ip are filled by CI)
docs/build-notes.md      build chain notes
docs/adr/                architecture decision records
```

## Build locally (requires Docker)

```sh
make fetch          # verify every baseline pin, then fetch the APISIX snapshot into build/src
make build-rpm      # runtime image -> final agw RPM (out/ holds exactly one product RPM)
make verify         # Anolis 8.10 container: install the RPM + Tongsuo/GM + openresty -V + apisix version + limit lua
make build-docker   # stage rpms/ and assemble the delivery image agw:<version>
make verify-docker  # image smoke: apisix init + standalone Server: agw assertion + SM2/NTLS handshake
make clean
```

## CI/CD

Everything runs on GitHub Actions and GHCR; there is no other CI system.

- `.github/workflows/build.yml` (push to `main`, pull requests, manual):
  baseline drift check → two-stage RPM chain → RPM smoke on Anolis 8.10 →
  delivery image + standalone/GM smoke → self-developed ratio → supply-chain
  gates (SBOM + Grype HIGH + Trivy HIGH/CRITICAL) → de-brand grep gate.
- `.github/workflows/publish.yml` (tag `v*`, manual): builds the final RPM,
  pushes the image to GHCR with the three tags above, verifies the image by
  pulling it back and re-running the standalone/GM smoke test, then publishes
  the RPM, the image SBOM and `release-manifest.json` to a GitHub Release.

Both workflows are self-contained: they reference no reusable workflow or
composite action from another repository.

Releases are immutable. `<version>` tags (and Git tags) are never moved —
publishing again always means bumping `VERSION`.

## License

Apache License 2.0 — see [LICENSE](./LICENSE).
