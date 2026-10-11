# sm121 Home Assistant Integration

A [Home Assistant](https://www.home-assistant.io/) custom integration that
exposes the [sm121](https://git.kilork.org/sm121/sm121-launcher) DGX Spark
cluster launcher as HA entities — control serve/stop/power from the HA UI.

## How it works

The integration talks to the **sm121 web dashboard** (`sm121 web`) REST API:

| Endpoint | Used by |
|----------|---------|
| `GET /api/state` | polled every 30 s → cluster health, running recipes |
| `POST /api/serve` | serve buttons |
| `POST /api/stop` | stop buttons |
| `POST /api/power` | power switches |

The sm121 web dashboard must be running (`sm121 web --port 3100`) and
reachable from the HA host.

## Entities (per cluster)

| Domain | Entity | Action / meaning |
|--------|--------|------------------|
| `switch` | `switch.sm121_<cluster>_power` | cluster power on/off |
| `button` | `button.sm121_<cluster>_serve_<recipe>` | serve a recipe |
| `button` | `button.sm121_<cluster>_stop` | stop all containers |
| `binary_sensor` | `binary_sensor.sm121_<cluster>_health` | cluster UP/DOWN |
| `sensor` | `sensor.sm121_<cluster>_running` | running recipe / `idle` |

Clusters + their recipe lists are set in the config entry (a fixed, curated
list — not auto-discovered).

## Install

1. Copy the `custom_components/sm121/` directory into your HA config:
   ```
   /config/custom_components/sm121/
   ```
   (or add this repo as a HACS custom repo).
2. Restart HA.
3. *Settings → Devices & Services → Add Integration → sm121 Launcher*.
4. Enter the **API URL** (e.g. `http://<mac-ip>:3100`) + **token** (the
   `sm121 web` token). Clusters are auto-listed from `/api/state`; add your
   recipes per cluster in the entry options.

## Config entry shape

```json
{
  "api_url": "http://192.168.1.50:3100",
  "token": "123",
  "clusters": [
    {"name": "8nodes-switch", "recipes": ["mimo26-pro-mopd-8x-sparkring"]},
    {"name": "4nodes-switch", "recipes": ["glm53-kindling-4x"]},
    {"name": "2nodes-dac", "recipes": ["mimo26-flash-mopd-2x-sparkring"]}
  ]
}
```

## Notes

- The integration is **read-only for state** (it polls `/api/state`) and
  **write-only for actions** (serve/stop/power). It never reads/writes the
  cluster directly — everything goes through the sm121 launcher, which owns
  the SSH, the image sync, the ledger, and the readiness checks.
- A `serve` action is a tracked job on the launcher side; the running-recipe
  sensor reflects it.
