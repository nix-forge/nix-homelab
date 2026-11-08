# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
python3 @script@ --help >/dev/null
touch "$out"
