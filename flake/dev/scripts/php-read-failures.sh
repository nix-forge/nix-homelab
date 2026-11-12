# shellcheck shell=bash
# The builder supplies sourcePath and out.
# shellcheck disable=SC2154
set -euo pipefail
cd "$sourcePath"
export PYTEST_DISABLE_PLUGIN_AUTOLOAD=1
export PYTHONPYCACHEPREFIX="$TMPDIR/python-pycache"
python3 -m pytest -o cache_dir="$TMPDIR/pytest-cache" tests/optional/test_freshrss_reads.py
touch "$out"
