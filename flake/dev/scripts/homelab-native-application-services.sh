# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
if rg --line-number \
  '(oci-containers|docker-compose|docker[[:space:]]+(compose|run)|podman[[:space:]]+(compose|run)|\bimage[[:space:]]*=[[:space:]]*")' \
  @runtimeConfiguration@; then
  echo 'Homelab modules and examples must use native packages and NixOS services.' >&2
  exit 1
fi
touch "$out"
