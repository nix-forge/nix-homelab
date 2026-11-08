# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
mkdir -p project/modules/services/scripts project/tests/wardrowbe
cp @modules_services_scripts_wardrowbe_codex_py@ project/modules/services/scripts/wardrowbe_codex.py
cp @tests_wardrowbe_test_codex_py@ project/tests/wardrowbe/test_codex.py
cp -R @wardrowbeFixtures@ project/tests/wardrowbe/fixtures
python3 -B -m unittest discover -s project/tests/wardrowbe -v
touch "$out"
