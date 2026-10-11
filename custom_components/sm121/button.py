"""Serve/stop buttons for the sm121 integration (per cluster + recipe)."""

from __future__ import annotations

from typing import Any

from homeassistant.components.button import ButtonEntity
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddEntities

from .const import DOMAIN
from .coordinator import Sm121Coordinator
from .entity import Sm121Entity


async def async_setup_entry(
    hass: HomeAssistant, entry: ConfigEntry, async_add_entities: AddEntities
) -> None:
    """Create serve buttons (one per recipe) + a stop button per cluster."""
    coordinator: Sm121Coordinator = hass.data[DOMAIN][entry.entry_id]
    clusters: list[dict[str, Any]] = entry.data.get("clusters", [])
    entities: list[Sm121Entity] = []
    for cluster in clusters:
        cname = cluster.get("name", "")
        if not cname:
            continue
        # Stop button (one per cluster)
        entities.append(Sm121StopButton(coordinator, entry, cname))
        # Serve buttons (one per recipe in the cluster's fixed list)
        for recipe in cluster.get("recipes", []):
            entities.append(Sm121ServeButton(coordinator, entry, cname, recipe))
    async_add_entities(entities)


class Sm121ServeButton(Sm121Entity, ButtonEntity):
    """A button that serves a recipe on a cluster via POST /api/serve."""

    def __init__(
        self,
        coordinator: Sm121Coordinator,
        entry: ConfigEntry,
        cluster: str,
        recipe: str,
    ) -> None:
        super().__init__(coordinator, entry)
        self._cluster = cluster
        self._recipe = recipe
        self._attr_unique_id = f"{entry.entry_id}-serve-{cluster}-{recipe}"
        self._attr_name = f"serve {recipe}"
        self._attr_device_info = self._cluster_device(cluster)

    async def async_press(self) -> None:
        await self.coordinator.api_post(
            "/api/serve", {"cluster": self._cluster, "recipe": self._recipe}
        )
        self.async_schedule_coordinator_refresh()


class Sm121StopButton(Sm121Entity, ButtonEntity):
    """A button that stops all containers on a cluster via POST /api/stop."""

    def __init__(
        self, coordinator: Sm121Coordinator, entry: ConfigEntry, cluster: str
    ) -> None:
        super().__init__(coordinator, entry)
        self._cluster = cluster
        self._attr_unique_id = f"{entry.entry_id}-stop-{cluster}"
        self._attr_name = "stop cluster"
        self._attr_device_info = self._cluster_device(cluster)

    async def async_press(self) -> None:
        await self.coordinator.api_post(
            "/api/stop", {"cluster": self._cluster}
        )
        self.async_schedule_coordinator_refresh()
