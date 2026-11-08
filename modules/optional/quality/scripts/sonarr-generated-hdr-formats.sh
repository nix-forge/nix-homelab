# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
mkdir -p "$out"
cp @guides@/docs/json/radarr/cf/generated-dynamic-hdr.json "$out"/
