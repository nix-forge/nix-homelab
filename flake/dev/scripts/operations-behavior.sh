# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
mkdir -p project/scripts project/tests
cp -r @scripts_operations@ project/scripts/operations
cp -r @tests_operations@ project/tests/operations
chmod -R u+w project
python3 -B -m unittest discover -s project/tests/operations -v
touch "$out"
