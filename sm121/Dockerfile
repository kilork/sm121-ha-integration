# syntax=docker/dockerfile:1
# sm121 HA add-on — a THIN alpine image that SHIPS a precompiled sm121
# binary.
#
# builder: pinned rust:alpine, a TRIVIAL build — no --target, no
#          RUSTFLAGS, no CC overrides. The default target is the
#          runner's own arch (the CI matrix runs each arch on its own
#          runner: aarch64 → aarch64-unknown-linux-musl, amd64 →
#          x86_64-unknown-linux-musl), so the binary always matches the
#          container's arch. No +crt-static: that flag makes the musl
#          target refuse the proc-macro crate type (clap/serde derives),
#          and a plain dynamic-musl binary runs fine on the alpine
#          final image (musl runtime included).
# final:   alpine + runtime deps (git — sm121 shells out for the recipe
#          repo sync; jq/curl; ca-certificates for https) + the binary
#          + the entrypoint. ~19 MB. No toolchain in the image, no
#          compile-on-boot: a 4 GB Pi must not OOM on a release build —
#          that's why the binary is baked in by CI, not compiled there.
#
# Pinned base images (reproducible builds; bump deliberately):
#   rust:1.98.1-alpine3.22  (matches the launcher's local toolchain)
#   alpine:3.22
#
# Context layout (CI): the sm121-ha-integration repo root, with the
# launcher checkout at launcher-src/ (actions/checkout, second checkout).

FROM rust:1.98.1-alpine3.22 AS builder
# The add-on version, baked into the binary so the dashboard can show it.
ARG SM121_VERSION=dev
COPY launcher-src/ /src/
# Cache mounts are EPHEMERAL (detached after the RUN), so the cargo
# target dir lives on a cache mount and the finished binary is copied to
# /out (real stage fs) for the final stage's COPY. `env` (not a bare
# VAR=x &&) so the variable reaches cargo in the image's /bin/sh.
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/build/target \
    cd /src \
    && env CARGO_TARGET_DIR=/build/target SM121_VERSION=$SM121_VERSION cargo build --release --features mimalloc \
    && mkdir -p /out \
    && cp /build/target/release/sm121 /out/sm121

FROM alpine:3.22
RUN apk add --no-cache git jq curl ca-certificates
COPY --from=builder /out/sm121 /usr/local/bin/sm121
COPY sm121/rootfs/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENV SM121_WEB_PORT=3100
EXPOSE 3100
ENTRYPOINT ["/entrypoint.sh"]
