# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
mkdir -p project/scripts/services project/tests/services
cp @scripts_services_bootstrap_bookorbit_py@ project/scripts/services/bootstrap_bookorbit.py
cp @tests_services_test_bookorbit_bootstrap_py@ project/tests/services/test_bookorbit_bootstrap.py
cd project || exit
python3 -B -m unittest discover -s tests/services -p 'test_bookorbit_bootstrap.py' -q
touch "$out"
