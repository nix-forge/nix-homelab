# shellcheck shell=bash
set -euo pipefail
umask 077
backup_dir=/var/lib/wardrowbe-backup
temp_file="$backup_dir/latest.dump.tmp"
trap 'rm -f "$temp_file"' EXIT
@lib_getExe_config_services_postgresql_package_pg_dump@ --host @postgresSocket@ --port @postgresPort@ \
  --format=custom --no-owner --file="$temp_file" @lib_escapeShellArg_cfg_databaseName@
mv -f "$temp_file" "$backup_dir/latest.dump"
