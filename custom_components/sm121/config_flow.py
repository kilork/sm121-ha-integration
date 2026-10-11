"""Config flow for the sm121 Launcher integration."""

from __future__ import annotations

import logging
from typing import Any

import aiohttp
from homeassistant import config_entries
from homeassistant.config_entries import ConfigFlow
from homeassistant.data_entry_flow import FlowResult

from .const import CONF_API_URL, CONF_CLUSTERS, CONF_TOKEN, DOMAIN

_LOGGER = logging.getLogger(__name__)

STEP_USER = "user"


class Sm121ConfigFlow(ConfigFlow, domain=DOMAIN):
    """Config flow: API URL + token + cluster/recipe list."""

    async def async_step_user(
        self, user_input: dict[str, Any] | None = None
    ) -> FlowResult:
        errors: dict[str, str] = {}
        if user_input is not None:
            # Validate: reach the sm121 web API
            api_url = user_input[CONF_API_URL].rstrip("/")
            token = user_input.get(CONF_TOKEN, "")
            try:
                async with aiohttp.ClientSession() as session:
                    headers = (
                        {"Authorization": f"Bearer {token}"} if token else {}
                    )
                    async with session.get(
                        f"{api_url}/api/state",
                        headers=headers,
                        timeout=aiohttp.ClientTimeout(total=10),
                    ) as resp:
                        if resp.status != 200:
                            errors["base"] = f"API returned {resp.status}"
                        else:
                            data = await resp.json()
                            # Auto-populate clusters from the snapshot
                            clusters = user_input.get(CONF_CLUSTERS, [])
                            if not clusters:
                                for c in data.get("clusters", []):
                                    clusters.append(
                                        {"name": c.get("name", ""), "recipes": []}
                                    )
                            return self.async_create_entry(
                                title=f"sm121 @ {api_url}",
                                data={
                                    CONF_API_URL: api_url,
                                    CONF_TOKEN: token,
                                    CONF_CLUSTERS: clusters,
                                },
                            )
            except aiohttp.ClientError as err:
                errors["base"] = f"Cannot reach API: {err}"

        return self._show_form(user_input, errors)

    def _show_form(
        self, user_input: dict[str, Any] | None, errors: dict[str, str]
    ) -> FlowResult:
        import voluptuous as vol

        schema = vol.Schema(
            {
                vol.Required(
                    CONF_API_URL,
                    default=(user_input or {}).get(CONF_API_URL, "http://127.0.0.1:3100"),
                ): str,
                vol.Optional(
                    CONF_TOKEN, default=(user_input or {}).get(CONF_TOKEN, "")
                ): str,
                # clusters are auto-populated from the API; the operator can
                # add recipes per cluster in the options flow
            }
        )
        return self.async_show_form(
            step_id=STEP_USER, data_schema=schema, errors=errors
        )
