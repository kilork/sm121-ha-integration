# sm121 Home Assistant Add-on

Runs the [sm121](https://git.kilork.org/sm121/launcher) DGX Spark
cluster launcher **inside Home Assistant as a Docker add-on** — 24/7,
independent of the Mac. Recipes + config live in **git recipe repos**;
the add-on clones/pulls them, keeps them fresh, and serves the `sm121
web` dashboard on port **3100** (serve/stop/power from the browser).

Design: [`ha-addon-recipe-repos.md`](https://git.kilork.org/sm121/launcher/blob/main/specs/tech-architecture/ha-addon-recipe-repos.md)
in the launcher repo.

## Layout

| File | What |
|------|------|
| `repository.json` | HA **add-on store** manifest — HA installs this add-on from this repo |
| `sm121/config.yaml` | the HA add-on manifest (options schema → the entrypoint's env vars) |
| `sm121/Dockerfile` + `sm121/rootfs/` | the thin image (no sm121 binary, no toolchain) + the entrypoint |
| `.github/workflows/` | GitHub Actions (the `home-assistant/builder` actions, same pattern as `kilork/cups-addon`): builds each arch natively, pushes `ghcr.io/kilork/sm121-addon` via OIDC — **no `docker login` anywhere** |
| `custom_components/sm121/` | **superseded** custom-integration prototype (commit `1ccd032`) — kept as reference; HA *entities* are a phase-2 nicety over the add-on's REST API |

**Cluster config is NOT in the (public) recipe repo** — it carries
private network details. It lives in the **private**
`git.kilork.org/sm121/cluster-config` repo, fetched at boot via the
`sm121_base_config` (+ `sm121_base_config_token`) options and used as the
base config (a private repo may carry `[home_assistant]` / `[mikrotik]`).

## The image

A THIN image (debian-slim + git/jq/curl/gcc; ~250 MB, small enough for
GHCR's free tier): the **Pi is the build host**. On first boot the
entrypoint installs rustup (cached in the add-on's data folder) and
compiles sm121 from the launcher repo (`sm121_launcher_url` @
`sm121_launcher_rev`), so the arch always matches (HAOS has no Docker to
build with) and the binary never goes stale. First boot = toolchain
download + a full release build (minutes on a Pi 5, longer on a Pi 4;
`sm121_build_jobs` defaults to 2 so a Pi 4 doesn't OOM under HA).

**Built by GitHub Actions** (on push to `main`): one native build per
arch in `config.yaml` (aarch64 + amd64) → `ghcr.io/kilork/sm121-addon`
(`:latest` + `:1.0.0`) + the multi-arch manifest. Pushing needs no
credentials (OIDC `GITHUB_TOKEN`) — but the GHCR package is created
**private** on first push: set it *public* in the GitHub UI once, so HA
can pull it anonymously.

Local dev / smoke (no CI needed):

```sh
docker build -t sm121-addon:latest sm121/    # from this repo
# launcher repo: scripts/smoke-addon.sh   # entrypoint + file:// recipe repo + file:// launcher checkout + curl /api/state
```

## Install

1. Push to `main` (CI builds + publishes the image); set the GHCR
   package `sm121-addon` to *public* (first time only).
2. In HA: *Settings → Add-ons & Storage → Add-on Store → (⚙) → Add
   repository* → `https://github.com/kilork/sm121-ha-integration`,
   then install **sm121**.
3. *Options*:
   - **Recipe repos** — ordered `{url, token}` list; the **first entry
     wins on a recipe-name collision** (production first, playground
     second).
   - **SSH user** + **SSH private key (base64)** — `base64 -i
     ~/.ssh/id_ed25519`; written to `/etc/sm121/ssh_key` (chmod 600) in
     the container, never baked into the image.
   - **Cluster config repo** (private git URL + PAT) — the base config
     (clusters/nccl with the private IPs + `[home_assistant]` /
     `[mikrotik]`), fetched at boot from `git.kilork.org/sm121/cluster-config`.
   - **HA URL / token** — for the launcher's power entities (optional).
   - **Image registry base** — e.g. `ghcr.io/kilork`; enables
     `--image-source registry` pulls of prebuilt images.
   - **Launcher repo / rev / build jobs** — sm121 is compiled on the Pi
     from the launcher repo on first boot (default `main`; set a commit
     hash to pin the binary — changing it recompiles once; `2` jobs so
     a Pi 4 doesn't OOM under HA).
   - **Extra config (raw TOML)** — appended verbatim to the generated
     config; this is where per-install CREDENTIALS live (e.g. a
     `[mikrotik]` block with its password) — the shared recipe repo's
     `config.toml` is credential-free (the repo may be shared with other
     users), so secrets that can't be flat options go here, kept out of
     the log.
   - **Re-sync interval** — the background supervisor re-pulls the recipe
     repos every N minutes (new recipes land without a restart).
   - **Dashboard bearer token** — required (the dashboard binds
     `0.0.0.0` and refuses to serve data endpoints without one).
4. Start the add-on; open `http://<ha-host>:3100` with the token.

The entrypoint: (1) writes the effective `config.toml` from the options
(an optional base config — e.g. a recipe repo's curated `config.toml`,
credential-free by contract: `[[clusters]]`/`[nccl]` only, no secrets —
mounts at `/etc/sm121/base.toml`; a `[mikrotik]` block, which carries a
password, comes from the `sm121_config_extra` option, never from the
repo), (2) drops the SSH key,
(3) `sm121 repos sync`, (4) `sm121 web --port 3100 --bind 0.0.0.0` with a
re-sync supervisor. A crash exits the container; HA's restart policy
re-runs the entrypoint (state lives in the recipe repos + the ledger, not
the container).

## Network reachability (operator's job)

The HA host must route to, on the same links the Mac uses today:

- the cluster nodes' **SSH IPs** (10G mgmt) — serve/stop/logs/health
- the **HA REST API** (`sm121_ha_url`/`token`) — power entities
- the **Mikrotik devices** (RouterOS API, TCP 8728) — graceful router
  power-off
- the **registry** (ghcr.io) — the add-on image itself + `--image-source registry` pulls
- **git.kilork.org + crates.io** — first boot only (the launcher-repo
  clone + the cargo fetch; both are cached afterwards)

## The single-launcher rule

The run ledger (`recipes/<name>/.lock` in the recipe repo) is the
serialization point: a second launcher that `serve`s the same recipe
sees the open run and refuses. **Run ONE launcher as the source of
truth (this add-on); the Mac launcher is for dev** (dry-runs, building,
`sm121 promote`, bench campaigns from a workstation). Two launchers
serving the same recipe at once will fight over the ledger.

## Promotion flow (the playground → production loop)

1. New recipe lands in the **playground** repo → the add-on's re-sync
   picks it up → serve/bench it from the dashboard.
2. Qualified: `sm121 promote <recipe> --from <playground> --to
   <production> --apply` (from the Mac; git mv + commit + push, target
   first so a failure duplicates, never deletes).
3. The add-on serves it from production on its next sync.
4. A repo full of retired lanes: `sm121 archive <url>` (it is skipped by
   sync; `sm121 unarchive <url>` brings it back).
