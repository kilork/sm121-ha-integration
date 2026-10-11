"""Base entity for the sm121 integration."""

from __future__ import annotations

from typing import Any

from homeassistant.config_entries import ConfigEntry
from homeassistant.helpers.entity import Entity

from .const import DOMAIN
from .coordinator import Sm121Coordinator


class Sm121Entity(Entity):
    """Base class for sm121 entities — shared coordinator + device info."""

    def __init__(self, coordinator: Sm121Coordinator, entry: ConfigEntry) -> None:
        self.coordinator = coordinator
        self._entry = entry
        self._attr_has_entity_name = True

    def _cluster_device(self, cluster: str) -> dict[str, Any]:
        return {
            "identifiers": {(DOMAIN, self._entry.entry_id)},
            "name": f"sm121 {cluster}",
            "manufacturer": "sm121",
            "model": "DGX Spark cluster",
            "configuration_url": self._entry.data.get("api_url", ""),
        }

    def async_schedule_coordinator_refresh(self) -> None:
        """Trigger an immediate coordinator refresh after an action."""
        self.async_schedule_update_ha_state()
        # Schedule a coordinator refresh (the action changed server state)
        import asyncio

        asyncio.create_task(self.coordinator.async_refresh())
