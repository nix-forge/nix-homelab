# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
mkdir -p project/modules/iot project/tests
cp -r @modules_iot_scripts@ project/modules/iot/scripts
cp -r @tests_iot@ project/tests/iot
cd project || exit
python3 -B -m pytest -q tests/iot
touch "$out"
