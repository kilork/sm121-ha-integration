#!/bin/sh
# sm121 HA add-on entrypoint (specs/tech-architecture/ha-addon-recipe-repos.md):
#
#   1. write the effective /etc/sm121/config.toml from the add-on options
#      (env vars); an optional base config at /etc/sm121/base.toml (e.g.
#      mounted in the standalone flow) — the generated sections are
#      APPENDED, so the base must not define them. The CLUSTER CONFIG
#      (private IPs) is NOT a file/repo: it is the sm121_config_extra
#      option (raw TOML) — HA option storage is private and on the Pi.
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
#   SM121_CONFIG_EXTRA        raw TOML appended verbatim — THE CLUSTER
#                             CONFIG lives here ([[clusters]]/nccl with the
#                             private IPs, [home_assistant], [mikrotik]):
#                             a HA option = private, on the Pi, never in
#                             the public recipe repo. If it carries
#                             [home_assistant]/[registry], leave the
#                             matching flat options empty (duplicate TOML
#                             tables fail the parse). Kept out of the log.
#   SM121_REPO_RESYNC_MINUTES background re-sync interval (default 10)
#   SM121_WEB_PORT            dashboard port (default 3100)
#   SM121_WEB_BIND            dashboard bind (default 0.0.0.0)
#   SM121_WEB_TOKEN           bearer token (REQUIRED for a non-loopback bind)
#
# The sm121 binary ships IN THE IMAGE (CI compiles it from the launcher
# repo per arch — see .github/workflows/build-addon.yaml + Dockerfile).
# No toolchain, no compile-on-boot: a 4 GB Pi must not OOM on a release
# build. Launcher change → re-run the add-on repo's CI → new image tag.
set -eu

CONFIG=/etc/sm121/config.toml
mkdir -p /etc/sm121

# --- 1. the effective config --------------------------------------------------
# Base: an optional /etc/sm121/base.toml (standalone/docker-secret flow).
# The CLUSTER CONFIG for the HA flow is NOT a repo or file — it is the
# sm121_config_extra option (raw TOML, appended below): [[clusters]]/nccl
# carry private IPs, so they live in HA's own option storage (private,
# on the Pi), never in the public recipe repo.
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

# --- 3 + 4. sync + web, with the re-sync supervisor ----------------------------
# The sm121 binary is baked into the image (CI-compiled per arch — see
# the Dockerfile); first boot is just a recipe-repo sync: seconds.
SM121="/usr/local/bin/sm121 --config $CONFIG"
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
