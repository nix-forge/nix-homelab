# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
mkdir -p project/scripts/optional project/tests/optional
cp @scripts_optional_bootstrap_miniflux_py@ project/scripts/optional/bootstrap_miniflux.py
cp @tests_optional_test_miniflux_upgrade_py@ project/tests/optional/test_miniflux_upgrade.py
python3 -B -m unittest discover -s project/tests/optional -v
touch "$out"
