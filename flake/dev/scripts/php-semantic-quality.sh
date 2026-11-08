# shellcheck shell=bash
# The builder supplies sourcePath and out.
# shellcheck disable=SC2154
set -euo pipefail
homelab-phpstan "$sourcePath"
touch "$out"
