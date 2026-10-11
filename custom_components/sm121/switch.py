"""Power switches for the sm121 integration (one per cluster)."""

from __future__ import annotations

from typing import Any

from homeassistant.components.switch import SwitchEntity, SwitchEntityDescription
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddEntities

from .const import DOMAIN
from .coordinator import Sm121Coordinator
from .entity import Sm121Entity


async def async_setup_entry(
    hass: HomeAssistant, entry: ConfigEntry, async_add_entities: AddEntities
) -> None:
    """Create one power switch per configured cluster."""
    coordinator: Sm121Coordinator = hass.data[DOMAIN][entry.entry_id]
    clusters: list[dict[str, Any]] = entry.data.get("clusters", [])
    entities: list[Sm121Entity] = []
    for cluster in clusters:
        name = cluster.get("name", "")
        if not name:
            continue
        entities.append(Sm121PowerSwitch(coordinator, entry, name))
    async_add_entities(entities)


class Sm121PowerSwitch(Sm121Entity, SwitchEntity):
    """A switch that powers a cluster on/off via POST /api/power."""

    _attr_name = None

    def __init__(
        self, coordinator: Sm121Coordinator, entry: ConfigEntry, cluster: str
    ) -> None:
        super().__init__(coordinator, entry)
        self._cluster = cluster
        self._attr_unique_id = f"{entry.entry_id}-power-{cluster}"
        self._attr_name = f"sm121 {cluster} power"
        self._attr_device_info = self._cluster_device(cluster)

    @property
    def is_on(self) -> bool | None:
        """ON when any node of the cluster reports reachable (up)."""
        snap = self.coordinator.data
        if not snap:
            return None
        for c in snap.get("clusters", []):
            if c.get("name") == self._cluster:
                return bool(c.get("up", False))
        return None

    async def async_turn_on(self, **kwargs: Any) -> None:
        await self.coordinator.api_post(
            "/api/power", {"cluster": self._cluster, "action": "on"}
        )
        self.async_schedule_coordinator_refresh()

    async def async_turn_off(self, **kwargs: Any) -> None:
        await self.coordinator.api_post(
            "/api/power", {"cluster": self._cluster, "action": "off"}
        )
        self.async_schedule_coordinator_refresh()
