# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
mkdir -p project/modules/services/scripts project/tests/keycloak
cp @modules_services_scripts_keycloak_admin_py@ project/modules/services/scripts/keycloak_admin.py
cp @tests_keycloak_test_admin_py@ project/tests/keycloak/test_admin.py
python3 -B -m unittest discover -s project/tests/keycloak -v
touch "$out"
