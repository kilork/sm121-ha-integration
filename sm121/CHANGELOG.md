# Changelog

Home Assistant shows the section of this file that matches the installed
add-on version. **Every version bump adds its own `## <version>` section at the
top** (same version as `config.yaml`); the entry describes what changed in the
launcher between that version and the previous one, in user terms (what an
operator will notice in the dashboard or in their recipes).

## 1.3.3

- **Fixed: the recipes panel kept lanes "active" after they were stopped.** The
  panel only refreshed when a report file changed, while `serve`/`stop` rewrite
  the recipe's run ledger (`.lock`) — so a stopped lane stayed green (or orange
  "stale") until some bench produced a report. The ledger now triggers a
  refresh, and the 30-second tick compares the panel's state against the ledger
  and re-checks the fleet, so a stopped lane disappears within half a minute.
  The stale/up flags are also recomputed each pass instead of sticking — which
  matters most on the add-on machine, where the live fleet probe is the only
  running signal.

## 1.3.2

- **Recipe hooks live with the recipe.** A `before_serve` / `after_stop` entry
  can now name a script *relative to the recipe directory*
  (`{ script = "scripts/prepare.sh" }`). The launcher uploads it and runs it with
  `NODE_RANK` exported, exactly like a built-in alias — so recipe-specific
  staging (NAS paths, model revisions, per-rank packs) ships in the synced
  recipe repo and updates with it, instead of requiring a new add-on image.
  Absolute paths and `..` traversal are refused. The TensorFold 2x 1017 staging
  script moved to its recipe this way.
- **Pre-serve hooks get the serve-local `NODE_RANK`.** On a subset launch (2 of
  a 4-node cluster) hooks saw the config rank (dgx7 = "rank 2") while the
  containers were renumbered 0..N-1, so per-rank staging built the wrong packs.
- **Bench**: `served_model()` also reads TensorFold's `--name` flag, so
  `sm121 bench` works on the TensorFold lanes without a fake
  `--served-model-name`.

## 1.3.1

- **Fixed: window drag/resize died over the recipes panel.** The recipes window
  is an iframe; once the pointer crossed into it the dashboard stopped getting
  move events, so a log window opened on top of the panel could only be shrunk
  and a titlebar drag could not cross it. Drags now take a pointer capture.

## 1.3.0

- **New: ⚙ settings dialog** in the recipes panel, right after ⚡ bench. Pick
  your agent (pi, Claude Code, Codex, Cline/Roo, generic OpenAI client), tick
  "include provider" to get the endpoint section too, and copy a paste-ready
  block. The endpoint, model name, context window and reasoning/tools flags come
  from the recipe plus the node actually serving it — nothing to type by hand.
- Backed by a new pure endpoint `GET /api/model-settings?recipe=<name>`.

## 1.2.0

- Engines: `tensorfold` driver (`python -m tensorfold serve`), plus built-in
  host hooks running with `NODE_RANK` so a hook can stage per-rank artifacts.
- Power: `off` never cuts a shared cluster extra (fabric switch/fan) that
  another cluster's open run still references.
- Serve: `--cold` overlays a recipe's `cold_args` by flag name (first-launch
  safety valve); multi-node recipes without `distributed_backend` are refused;
  subset launches renumber ranks; `--mirror` verifies repos by content.
- Bench: `--node` pins the target inside a cluster, `--no-think` / `--timeout`
  passthrough, no more "engine down" mislabels on slow boots.
- Recipes panel: logs open in a dashboard window instead of an inline stream.

## 1.1.12

- Recipes panel row controls moved into the expanded section (above the toml
  link): serve/stop, a live log window (▤ logs, node picker) and ⚡ bench.

## 1.1.11

- Interactive recipes panel: manual repo sync (⟳), per-row serve/stop through
  the dashboard job API, fleet-derived running state (works without a local run
  ledger, e.g. on the Pi), launch counter.
- Bench ergonomics: optional `--label`, opt-in depth suite, caveated perf cells.

## 1.1.10

- Root-caused the daily OOM: the report file watcher watched the cwd (`.`, which
  is `/` in the container) and followed the `/sys` symlink loops. It now watches
  real recipe workspaces only, shares one HA REST client, and refreshes lazily.
  RSS is flat at ~40 MiB instead of growing ~270 MiB/h.

## 1.1.9

- The launcher is built with the mimalloc allocator (musl's default malloc never
  returned memory to the OS) — the backstop for the watcher leak above.

## 1.1.8

- The web server owns the recipe-repo resync loop
  (`--repo-sync-interval`, from `SM121_REPO_RESYNC_MINUTES`).

## 1.1.7

- `HOME=/data`: the synced recipe repos and caches survive a container
  recreation instead of being re-cloned.

## 1.1.6

- The repo browser resolves against the synced recipe-repo roots (docker-image
  links work from the Pi).

## 1.1.5

- Rebuild on the launcher auth commit (the previous run raced the launcher push).

## 1.1.4

- Dashboard auth: bearer token + session cookie, no token in URLs; the
  `sm121_insecure` option runs it unauthenticated on an isolated LAN.

## 1.1.2

- Launcher gains probe-failure logging.