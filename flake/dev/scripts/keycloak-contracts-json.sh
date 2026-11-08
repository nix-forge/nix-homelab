# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
test -x @c_systemd_services_keycloak_postStart@
cp @pkgs_writeText_keycloak_contract_results_json_builtins_toJSO@ "$out"
