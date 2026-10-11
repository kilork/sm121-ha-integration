# sm121 HA add-on image — THIN: the Pi is the build host.
#
# HAOS has no Docker to build with, so the image carries NO sm121 binary
# and NO Rust toolchain: the entrypoint installs rustup (first boot, cached
# in the add-on's data folder) and compiles sm121 from the launcher repo
# (sm121_launcher_url @ sm121_launcher_rev). The arch always matches, the
# binary never goes stale, and the image stays small enough for GHCR's
# free tier (2 archs × ~250 MB).
#
# Built by GitHub Actions (this repo's .github/workflows/) for the archs
# in config.yaml → ghcr.io/kilork/sm121-addon.
#
# specs/tech-architecture/ha-addon-recipe-repos.md (launcher repo) +
# addendum: "the HAOS build variant — the Pi is the build host".

FROM debian:bookworm-slim

# git (launcher-repo fetch + recipe-repo sync) + jq (env → config) +
# ca-certs (https) + curl (rustup) + gcc/libc6-dev (ring's C backend, via
# russh — the compile happens in-container, so the compiler lives here)
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      git ca-certificates jq curl gcc libc6-dev \
 && rm -rf /var/lib/apt/lists/*

# HA add-on convention: rootfs/ is copied to the container root.
COPY rootfs/ /
RUN chmod 755 /entrypoint.sh

ENV SM121_WEB_PORT=3100
EXPOSE 3100
ENTRYPOINT ["/entrypoint.sh"]
