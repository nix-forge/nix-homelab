# shellcheck shell=bash
install -m 600 /dev/null /run/restic-password
printf '%s' disposable-fixture-password >/run/restic-password
