# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
mkdir -p "$out/lib/karakeep"
ln -s @web@ "$out/lib/karakeep/start-web"
ln -s @workers@ "$out/lib/karakeep/start-workers"
ln -s @migrate@ "$out/lib/karakeep/migrate"
