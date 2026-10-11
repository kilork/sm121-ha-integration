#!/bin/sh
# sm121 HA add-on entrypoint (specs/tech-architecture/ha-addon-recipe-repos.md):
#
#   1. write the effective /etc/sm121/config.toml from the add-on options
#      (env vars); an optional base config at /etc/sm121/base.toml (e.g. a
#      recipe repo's config.toml, mounted) carries the cluster definitions
#      — the generated sections (recipe_repos / home_assistant / registry)
#      are APPENDED, so the base must not define them
#   2. drop the SSH key (a mounted secret) at SM121_SSH_KEY_PATH
#   3. sync the recipe repos (clone/pull)
#   4. run `sm121 web` on 3100; a supervisor loop re-syncs the repos every
#      SM121_REPO_RESYNC_MINUTES so new recipes land without a restart
#
# Env (the add-on options — HA maps each `sm121_*` option to the
# uppercased env var; the standalone flow sets the same names directly):
#   SM121_RECIPE_REPOS        JSON list of {"url","token"} → [[recipe_repos]]
#   SM121_SSH_USER            ssh_user
#   SM121_SSH_KEY_B64         base64 private key (HA option; written to KEY_PATH)
#   SM121_SSH_KEY             path to a mounted private key (docker secret mount)
#   SM121_SSH_KEY_PATH        where the key lands (default /etc/sm121/ssh_key)
#   SM121_HA_URL / SM121_HA_TOKEN   → [home_assistant]
#   SM121_REGISTRY_BASE       → [registry] base (for --image-source registry)
#   SM121_CONFIG_EXTRA        raw TOML appended verbatim (per-install
#                             credentials that must not live in the shared
#                             repo, e.g. a [mikrotik] block with its password)
#   SM121_LAUNCHER_URL        launcher repo (default git.kilork.org/sm121/
#                             sm121-launcher) — sm121 is COMPILED from it on
#                             first boot (the Pi is the build host)
#   SM121_LAUNCHER_REV        rev to compile (default main; a commit hash
#                             pins the binary)
#   SM121_BUILD_JOBS          cargo -j (default 2 — a Pi 4 must not OOM)
#   SM121_RUST_TOOLCHAIN      rustup toolchain for the compile (default
#                             1.98.1; edition 2024 + let-chains need ≥ 1.88)
#   SM121_REPO_RESYNC_MINUTES background re-sync interval (default 10)
#   SM121_WEB_PORT            dashboard port (default 3100)
#   SM121_WEB_BIND            dashboard bind (default 0.0.0.0)
#   SM121_WEB_TOKEN           bearer token (REQUIRED for a non-loopback bind)
set -eu

CONFIG=/etc/sm121/config.toml
mkdir -p /etc/sm121

# --- 1. the effective config --------------------------------------------------
if [ -f /etc/sm121/base.toml ]; then
  cp /etc/sm121/base.toml "$CONFIG"
else
  : > "$CONFIG"
fi

{
  # (if-form, not `&&`: a false condition must not trip `set -e`)
  if [ -n "${SM121_SSH_USER:-}" ]; then printf 'ssh_user = "%s"\n' "$SM121_SSH_USER"; fi
  if [ -n "${SM121_SSH_KEY_PATH:-}" ]; then printf 'ssh_key_path = "%s"\n' "$SM121_SSH_KEY_PATH"; fi
} >> "$CONFIG"

# JSON list of {"url","token"} → [[recipe_repos]] blocks (tojson keeps the
# values properly escaped — JSON basic strings ARE valid TOML strings).
if [ -n "${SM121_RECIPE_REPOS:-}" ]; then
  printf '%s' "$SM121_RECIPE_REPOS" | jq -r '
    .[] | ("[[recipe_repos]]\nurl = " + (.url | tojson) + "\n"
           + (if .token then "token = " + (.token | tojson) + "\n" else "" end))
  ' >> "$CONFIG"
fi

if [ -n "${SM121_HA_URL:-}" ] && [ -n "${SM121_HA_TOKEN:-}" ]; then
  printf '[home_assistant]\nurl = "%s"\ntoken = "%s"\n' \
    "$SM121_HA_URL" "$SM121_HA_TOKEN" >> "$CONFIG"
fi
if [ -n "${SM121_REGISTRY_BASE:-}" ]; then
  printf '[registry]\nbase = "%s"\n' "$SM121_REGISTRY_BASE" >> "$CONFIG"
fi

# Raw per-install TOML, appended verbatim (the option is a multi-line
# string). This is where credentials that can't be expressed as flat
# options live — e.g. a [mikrotik] block (it carries a password, so it is
# deliberately NOT in the shared recipe repo's config.toml). Never logged.
if [ -n "${SM121_CONFIG_EXTRA:-}" ]; then
  printf '%s\n' "$SM121_CONFIG_EXTRA" >> "$CONFIG"
fi

# --- 2. the SSH key ------------------------------------------------------------
# HA add-on options cannot mount files: the key arrives base64-encoded as
# SM121_SSH_KEY_B64 (the `sm121_ssh_key_b64` option) and is written to
# SM121_SSH_KEY_PATH (default /etc/sm121/ssh_key). A plain file path
# (SM121_SSH_KEY, e.g. a docker secret mount) is also accepted.
KEY_PATH="${SM121_SSH_KEY_PATH:-/etc/sm121/ssh_key}"
if [ -n "${SM121_SSH_KEY_B64:-}" ]; then
  mkdir -p "$(dirname "$KEY_PATH")"
  printf '%s' "$SM121_SSH_KEY_B64" | base64 -d > "$KEY_PATH"
  chmod 600 "$KEY_PATH"
elif [ -n "${SM121_SSH_KEY:-}" ] && [ -f "$SM121_SSH_KEY" ]; then
  cp "$SM121_SSH_KEY" "$KEY_PATH"
  chmod 600 "$KEY_PATH"
fi

# --- 2a. the Rust toolchain (first boot: install into the data folder) ------
# NOT baked into the image (GHCR's free tier is 1 GiB of storage; a baked
# toolchain × 2 archs would bust it). rustup installs into $HOME/.rustup +
# $HOME/.cargo — the add-on's data folder, so the ~350 MB download happens
# once per install and survives restarts.
HOME="${HOME:-/root}"
if [ ! -x "$HOME/.cargo/bin/cargo" ]; then
  echo "sm121: installing the Rust toolchain (first boot, ~350 MB download)"
  curl -sSf https://sh.rustup.rs \
    | sh -s -- --no-modify-path -y --profile minimal \
              --default-toolchain "${SM121_RUST_TOOLCHAIN:-1.98.1}"
fi
export PATH="$HOME/.cargo/bin:$PATH"

# --- 2b. compile sm121 if needed (the Pi is the build host) ------------------
# The launcher source comes from the launcher repo (SM121_LAUNCHER_URL @
# SM121_LAUNCHER_REV). The binary + a rev stamp + the cargo target cache
# live in the add-on's data folder ($HOME — HA sets it to the add-on's data
# dir; falls back to /root), so a reboot with an unchanged rev is fast and
# a rev change recompiles once. First boot is slow (toolchain download + a
# full release build: minutes on a Pi 5, longer on a Pi 4) — the add-on
# just shows "starting".
SM121_BIN="$HOME/.sm121/bin/sm121"
LAUNCHER_URL="${SM121_LAUNCHER_URL:-https://git.kilork.org/sm121/sm121-launcher.git}"
LAUNCHER_REV="${SM121_LAUNCHER_REV:-main}"
STAMP="$HOME/.sm121/rev"
if [ ! -x "$SM121_BIN" ] || [ "$(cat "$STAMP" 2>/dev/null)" != "$LAUNCHER_REV" ]; then
  echo "sm121: compiling from $LAUNCHER_URL @ $LAUNCHER_REV (first boot / rev changed)"
  mkdir -p "$HOME/.sm121/bin"
  SRC="$(mktemp -d)"
  case "$LAUNCHER_REV" in
    main|master) git clone -q --depth 1 --branch "$LAUNCHER_REV" "$LAUNCHER_URL" "$SRC" ;;
    *) git clone -q "$LAUNCHER_URL" "$SRC" && git -C "$SRC" checkout -q "$LAUNCHER_REV" ;;
  esac
  CARGO_TARGET_DIR="$HOME/.sm121/target" \
  CARGO_BUILD_JOBS="${SM121_BUILD_JOBS:-2}" \
  cargo build --release --manifest-path "$SRC/Cargo.toml"
  cp "$HOME/.sm121/target/release/sm121" "$SM121_BIN"
  printf '%s' "$LAUNCHER_REV" > "$STAMP"
  rm -rf "$SRC"
  echo "sm121: built ($LAUNCHER_REV) → $SM121_BIN"
fi

# --- 3 + 4. sync + web, with the re-sync supervisor ----------------------------
SM121="$SM121_BIN --config $CONFIG"
$SM121 repos sync || echo "warning: initial repo sync failed (the supervisor retries)"

INTERVAL="${SM121_REPO_RESYNC_MINUTES:-10}"
(
  while :; do
    sleep "$((INTERVAL * 60))"
    $SM121 repos sync || true
  done
) &

# A web crash exits the container; the HA restart policy (always) re-runs
# this entrypoint (re-sync + fresh dashboard). No state is lost (the run
# ledger lives in the recipe repos, the cache in ~/.cache/sm121).
exec $SM121 web \
  --port "${SM121_WEB_PORT:-3100}" \
  --bind "${SM121_WEB_BIND:-0.0.0.0}" \
  ${SM121_WEB_TOKEN:+--token "$SM121_WEB_TOKEN"}
