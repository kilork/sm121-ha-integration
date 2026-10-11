"""Health binary sensor for the sm121 integration (one per cluster)."""

from __future__ import annotations

from typing import Any

from homeassistant.components.binary_sensor import (
    BinarySensorDeviceClass,
    BinarySensorEntity,
)
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddEntities

from .const import DOMAIN
from .coordinator import Sm121Coordinator
from .entity import Sm121Entity


async def async_setup_entry(
    hass: HomeAssistant, entry: ConfigEntry, async_add_entities: AddEntities
) -> None:
    """Create a health binary sensor per configured cluster."""
    coordinator: Sm121Coordinator = hass.data[DOMAIN][entry.entry_id]
    clusters: list[dict[str, Any]] = entry.data.get("clusters", [])
    entities: list[Sm121Entity] = []
    for cluster in clusters:
        name = cluster.get("name", "")
        if name:
            entities.append(Sm121HealthBinarySensor(coordinator, entry, name))
    async_add_entities(entities)


class Sm121HealthBinarySensor(Sm121Entity, BinarySensorEntity):
    """ON when the cluster is UP (all nodes reachable + blocking extras on)."""

    _attr_device_class = BinarySensorDeviceClass.CONNECTIVITY
    _attr_name = None

    def __init__(
        self, coordinator: Sm121Coordinator, entry: ConfigEntry, cluster: str
    ) -> None:
        super().__init__(coordinator, entry)
        self._cluster = cluster
        self._attr_unique_id = f"{entry.entry_id}-health-{cluster}"
        self._attr_name = "health"
        self._attr_device_info = self._cluster_device(cluster)

    @property
    def is_on(self) -> bool | None:
        snap = self.coordinator.data
        if not snap:
            return None
        for c in snap.get("clusters", []):
            if c.get("name") == self._cluster:
                return bool(c.get("up", False))
        return None
