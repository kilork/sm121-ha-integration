"""Data coordinator for the sm121 integration — polls GET /api/state."""

from __future__ import annotations

import logging
from typing import Any

import aiohttp
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant
from homeassistant.helpers.update_coordinator import DataUpdateCoordinator, UpdateFailed

from .const import DOMAIN, POLL_INTERVAL_SECONDS

_LOGGER = logging.getLogger(__name__)


class Sm121Coordinator(DataUpdateCoordinator[dict[str, Any]]):
    """Poll the sm121 web dashboard's /api/state every POLL_INTERVAL_SECONDS."""

    def __init__(self, hass: HomeAssistant, entry: ConfigEntry) -> None:
        super().__init__(
            hass,
            _LOGGER,
            name=f"{DOMAIN}-{entry.entry_id}",
            update_interval=POLL_INTERVAL_SECONDS,
        )
        self._api_url: str = entry.options.get(
            "api_url", entry.data.get("api_url", "")
        ).rstrip("/")
        self._token: str = entry.options.get(
            "token", entry.data.get("token", "")
        )
        self._session: aiohttp.ClientSession | None = None

    async def _get_session(self) -> aiohttp.ClientSession:
        if self._session is None or self._session.closed:
            self._session = aiohttp.ClientSession(
                timeout=aiohttp.ClientTimeout(total=15)
            )
        return self._session

    async def _fetch_state(self) -> dict[str, Any]:
        """Fetch the /api/state snapshot from the sm121 web dashboard."""
        session = await self._get_session()
        url = f"{self._api_url}/api/state"
        headers = {"Authorization": f"Bearer {self._token}"} if self._token else {}
        async with session.get(url, headers=headers) as resp:
            if resp.status != 200:
                raise UpdateFailed(f"sm121 /api/state returned {resp.status}")
            return await resp.json()

    async def _async_update_data(self) -> dict[str, Any]:
        try:
            return await self._fetch_state()
        except aiohttp.ClientError as err:
            raise UpdateFailed(f"sm121 API unreachable: {err}") from err

    async def api_post(self, path: str, payload: dict[str, Any]) -> dict[str, Any]:
        """POST to the sm121 web API (serve/stop/power)."""
        session = await self._get_session()
        url = f"{self._api_url}{path}"
        headers = {"Authorization": f"Bearer {self._token}"} if self._token else {}
        async with session.post(url, json=payload, headers=headers) as resp:
            data = await resp.json()
            if resp.status >= 400:
                raise RuntimeError(f"sm121 {path} -> {resp.status}: {data}")
            return data

    async def close(self) -> None:
        if self._session and not self._session.closed:
            await self._session.close()
