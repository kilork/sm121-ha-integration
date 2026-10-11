"""Running-recipe sensor for the sm121 integration (one per cluster)."""

from __future__ import annotations

from typing import Any

from homeassistant.components.sensor import SensorEntity
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddEntities

from .const import DOMAIN
from .coordinator import Sm121Coordinator
from .entity import Sm121Entity


async def async_setup_entry(
    hass: HomeAssistant, entry: ConfigEntry, async_add_entities: AddEntities
) -> None:
    """Create a running-recipe sensor per configured cluster."""
    coordinator: Sm121Coordinator = hass.data[DOMAIN][entry.entry_id]
    clusters: list[dict[str, Any]] = entry.data.get("clusters", [])
    entities: list[Sm121Entity] = []
    for cluster in clusters:
        name = cluster.get("name", "")
        if name:
            entities.append(Sm121RunningSensor(coordinator, entry, name))
    async_add_entities(entities)


class Sm121RunningSensor(Sm121Entity, SensorEntity):
    """The recipe currently running on the cluster (from jobs/containers),
    or 'idle' when nothing is running."""

    _attr_name = None

    def __init__(
        self, coordinator: Sm121Coordinator, entry: ConfigEntry, cluster: str
    ) -> None:
        super().__init__(coordinator, entry)
        self._cluster = cluster
        self._attr_unique_id = f"{entry.entry_id}-running-{cluster}"
        self._attr_name = "running recipe"
        self._attr_device_info = self._cluster_device(cluster)

    @property
    def state(self) -> str | None:
        snap = self.coordinator.data
        if not snap:
            return None
        # Running (not-done) serve jobs for this cluster
        running = [
            j
            for j in snap.get("jobs", [])
            if j.get("cluster") == self._cluster
            and not j.get("done", True)
            and j.get("kind") == "serve"
        ]
        if running:
            latest = max(running, key=lambda j: str(j.get("id", "")))
            return str(latest.get("recipe", "?"))
        # Fall back: a container of a known recipe is running
        for c in snap.get("clusters", []):
            if c.get("name") == self._cluster:
                recipes = {
                    str(ct.get("recipe"))
                    for n in c.get("nodes", [])
                    for ct in n.get("containers", [])
                    if ct.get("recipe")
                }
                if recipes:
                    return ", ".join(sorted(recipes))
        return "idle"
