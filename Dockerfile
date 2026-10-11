# Reference Dockerfile for the sm121 add-on image.
#
# The image is built by the LAUNCHER repo (docker-images/sm121-addon/ —
# multi-stage: sm121 is compiled in-container, so the binary always
# matches the container's arch):
#
#   cd sm121-launcher
#   make addon-image     # → sm121-addon:latest
#   make addon-push      # → ghcr.io/kilork/sm121-addon:latest
#
# and config.yaml pulls that pushed image. This file only layers the
# (empty) add-on repo on top — a local build shortcut:
#
#   docker build -t sm121-addon:local .
#
FROM ghcr.io/kilork/sm121-addon:latest
