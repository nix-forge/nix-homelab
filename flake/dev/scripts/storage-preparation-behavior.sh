# shellcheck shell=bash
# Nix supplies the output path to the builder.
# shellcheck disable=SC2154
set -euo pipefail
export PYTEST_DISABLE_PLUGIN_AUTOLOAD=1
export PYTHONPYCACHEPREFIX="$TMPDIR/pycache"
python3 -m pytest -q -p no:cacheprovider @source@/tests/storage @source@/tests/indexers
touch "$out"
