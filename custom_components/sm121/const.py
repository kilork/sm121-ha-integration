"""Constants for the sm121 Launcher Home Assistant integration."""

DOMAIN = "sm121"

# Config entries
CONF_API_URL = "api_url"
CONF_TOKEN = "token"
CONF_CLUSTERS = "clusters"

# Cluster config keys (each cluster is a dict)
CLUSTER_NAME = "name"
CLUSTER_RECIPES = "recipes"

# Coordinator
POLL_INTERVAL_SECONDS = 30

# Entity prefixes
SWITCH_POWER = "power"
BUTTON_SERVE = "serve"
BUTTON_STOP = "stop"
BINARY_SENSOR_HEALTH = "health"
SENSOR_RUNNING = "running"
