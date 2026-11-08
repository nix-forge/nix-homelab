# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
cp -r @workflowSource@ project
chmod -R u+w project
cd project || exit
python3 -B -m unittest discover -s tests/workflows -v
touch "$out"
