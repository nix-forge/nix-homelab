# shellcheck shell=bash
printf '%s' disposable-backup-password >/run/restic-password
chmod 600 /run/restic-password
