# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
mkdir -p "$out/downloaders" "$out/integration"
cp @scripts_downloaders_qbittorrent_config_py@ "$out/downloaders/qbittorrent_config.py"
cp @scripts_integration_common_py@ "$out/integration/common.py"
