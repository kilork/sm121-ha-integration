# sm121 Home Assistant Add-on

Runs the [sm121](https://git.kilork.org/sm121/sm121-launcher) DGX Spark
cluster launcher **inside Home Assistant as a Docker add-on** — 24/7,
independent of the Mac. Recipes + config live in **git recipe repos**;
the add-on clones/pulls them, keeps them fresh, and serves the `sm121
web` dashboard on port **3100** (serve/stop/power from the browser).

Design: [`ha-addon-recipe-repos.md`](https://git.kilork.org/sm121/sm121-launcher/blob/master/specs/tech-architecture/ha-addon-recipe-repos.md)
in the launcher repo.

## Layout

| File | What |
|------|------|
| `config.yaml` | the HA add-on manifest (options schema → the entrypoint's env vars) |
| `Dockerfile` | reference build (the image is built by the launcher repo) |
| `custom_components/sm121/` | **superseded** custom-integration prototype (commit `1ccd032`) — kept as reference; HA *entities* are a phase-2 nicety over the add-on's REST API |

## The image

Built by the **launcher repo** — a THIN image (debian-slim + git/jq + the
pinned Rust toolchain; no sm121 binary): the **Pi is the build host**.
On first boot the entrypoint compiles sm121 from the launcher repo
(`sm121_launcher_url` @ `sm121_launcher_rev`, cached in the add-on's
data folder), so the arch always matches (HAOS has no Docker to build
with) and the binary never goes stale. First boot = a full release
build (minutes on a Pi 5, longer on a Pi 4; `sm121_build_jobs` defaults
to 2 so a Pi 4 doesn't OOM under HA).

```sh
cd sm121-launcher
make addon-image   # → sm121-addon:latest
make addon-push    # → ghcr.io/kilork/sm121-addon:latest  (docker login ghcr.io first)
scripts/smoke-addon.sh   # entrypoint + file:// recipe repo + file:// launcher checkout + curl /api/state
```

`config.yaml` pulls `ghcr.io/kilork/sm121-addon`.

## Install

1. `make addon-push` from the launcher repo (after any launcher change).
2. In HA: *Settings → Add-ons & Storage → Add-on Store* → install the
   add-on from this repo (HAOS add-on: copy this directory into
   `/addon/sm121/` on the HA host, or use the add-on builder for a
   local store entry).
3. *Options*:
   - **Recipe repos** — ordered `{url, token}` list; the **first entry
     wins on a recipe-name collision** (production first, playground
     second).
   - **SSH user** + **SSH private key (base64)** — `base64 -i
     ~/.ssh/id_ed25519`; written to `/etc/sm121/ssh_key` (chmod 600) in
     the container, never baked into the image.
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
